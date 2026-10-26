import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/errors/app_exception.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/data/local/attendance_local_reader.dart';
import '../../attendance/data/local/local_attendance_providers.dart';
import '../../attendance/domain/attendance_models.dart';
import '../../attendance/domain/attendance_outbox_event.dart';

enum TodayAttendanceStatus { none, checkedIn, done }

class TodayAttendance {
  const TodayAttendance({this.checkIn, this.checkOut});

  final AttendanceEvent? checkIn;
  final AttendanceEvent? checkOut;

  TodayAttendanceStatus get status {
    if (checkOut != null) return TodayAttendanceStatus.done;
    if (checkIn != null) return TodayAttendanceStatus.checkedIn;
    return TodayAttendanceStatus.none;
  }
}

enum HomeLoadPhase { loading, ready, error }

class HomeState {
  const HomeState({
    this.phase = HomeLoadPhase.loading,
    this.today = const TodayAttendance(),
    this.employeeNumber,
    this.errorMessage,
    this.usingLocalData = false,
  });

  final HomeLoadPhase phase;
  final TodayAttendance today;
  final String? employeeNumber;
  final String? errorMessage;
  final bool usingLocalData;

  bool get isReady => phase == HomeLoadPhase.ready;
}

/// Loads the authenticated employee's "today" state.
///
/// The server remains the source of truth for accepted events. When the
/// network is unavailable, today's status comes from the durable local outbox
/// so queued check-in/check-out is still visible.
class HomeController extends StateNotifier<HomeState> {
  HomeController(this._ref) : super(const HomeState());

  final Ref _ref;

  Future<void> reload() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final user = _ref.read(sessionControllerProvider).user;
    final employeeNumber = user?.employee?.employeeNumber;

    var localEvents = <AttendanceEvent>[];
    var usingLocalData = false;
    try {
      localEvents = await _loadLocal(start, end, user?.id);
      usingLocalData = localEvents.isNotEmpty;
    } catch (_) {
      // The server request below can still succeed.
    }

    state = HomeState(
      phase: HomeLoadPhase.loading,
      today: _summarizeToday(localEvents),
      employeeNumber: employeeNumber,
      usingLocalData: usingLocalData,
    );

    try {
      final todayEvents = await _ref.read(attendanceRepositoryProvider).history(
            from: start,
            to: end,
          );

      state = HomeState(
        phase: HomeLoadPhase.ready,
        today: _summarizeToday(_mergeEvents(todayEvents, localEvents)),
        employeeNumber: employeeNumber,
      );
    } on AppException catch (error) {
      state = HomeState(
        phase: user == null ? HomeLoadPhase.error : HomeLoadPhase.ready,
        today: _summarizeToday(localEvents),
        employeeNumber: employeeNumber,
        errorMessage: error.message,
        usingLocalData: user != null,
      );
    }
  }

  Future<List<AttendanceEvent>> _loadLocal(
    DateTime start,
    DateTime end,
    int? ownerUserId,
  ) async {
    if (ownerUserId == null) return const [];

    final events = await _ref.read(attendanceLocalReaderProvider).eventsForOwner(
          ownerUserId,
          from: start,
          to: end,
        );

    return events
        .where((event) => event.state != AttendanceOutboxState.rejected)
        .map(localAttendanceEvent)
        .toList(growable: false);
  }

  List<AttendanceEvent> _mergeEvents(
    List<AttendanceEvent> serverEvents,
    List<AttendanceEvent> localEvents,
  ) {
    final merged = <String, AttendanceEvent>{};
    for (final event in serverEvents) {
      final key = event.clientEventId.isEmpty
          ? 'server-${event.id}'
          : event.clientEventId;
      merged[key] = event;
    }
    for (final event in localEvents) {
      merged.putIfAbsent(event.clientEventId, () => event);
    }

    final result = merged.values.toList();
    result.sort(_byEventTime);
    return result;
  }

  int _byEventTime(AttendanceEvent a, AttendanceEvent b) {
    final left = a.eventAt;
    final right = b.eventAt;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }

  TodayAttendance _summarizeToday(List<AttendanceEvent> events) {
    AttendanceEvent? checkIn;
    AttendanceEvent? checkOut;
    for (final event in events) {
      if (event.isCheckIn && checkIn == null) checkIn = event;
      if (!event.isCheckIn && checkOut == null) checkOut = event;
    }
    return TodayAttendance(checkIn: checkIn, checkOut: checkOut);
  }
}

final homeControllerProvider =
    StateNotifierProvider<HomeController, HomeState>(
  (ref) => HomeController(ref),
);
