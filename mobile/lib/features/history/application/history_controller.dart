import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/errors/app_exception.dart';
import '../../attendance/data/attendance_repository.dart';
import '../../attendance/data/local/attendance_local_reader.dart';
import '../../attendance/data/local/local_attendance_providers.dart';
import '../../attendance/domain/attendance_models.dart';

enum HistoryLoadPhase { loading, ready, error }

class HistoryState {
  const HistoryState({
    this.phase = HistoryLoadPhase.loading,
    this.events = const [],
    this.from,
    this.to,
    this.errorMessage,
    this.usingLocalData = false,
  });

  final HistoryLoadPhase phase;
  final List<AttendanceEvent> events;
  final DateTime? from;
  final DateTime? to;
  final String? errorMessage;
  final bool usingLocalData;

  HistoryState copyWith({
    HistoryLoadPhase? phase,
    List<AttendanceEvent>? events,
    DateTime? from,
    DateTime? to,
    String? errorMessage,
    bool? usingLocalData,
  }) {
    return HistoryState(
      phase: phase ?? this.phase,
      events: events ?? this.events,
      from: from ?? this.from,
      to: to ?? this.to,
      errorMessage: errorMessage ?? this.errorMessage,
      usingLocalData: usingLocalData ?? this.usingLocalData,
    );
  }
}

class HistoryController extends StateNotifier<HistoryState> {
  HistoryController(this._ref) : super(const HistoryState());

  final Ref _ref;

  Future<void> load({DateTime? from, DateTime? to}) async {
    final now = DateTime.now();
    final start = from ?? DateTime(now.year, now.month, 1);
    final end = to ?? DateTime(now.year, now.month, now.day);
    final endExclusive = DateTime(end.year, end.month, end.day + 1);
    final user = _ref.read(sessionControllerProvider).user;

    var localEvents = <AttendanceEvent>[];
    try {
      final local = await _ref
          .read(attendanceLocalReaderProvider)
          .eventsForOwner(
            user?.id ?? 0,
            from: start,
            to: endExclusive.subtract(const Duration(microseconds: 1)),
          );
      localEvents = local.map(localAttendanceEvent).toList(growable: false);
    } catch (_) {
      // The server request below can still succeed.
    }

    state = state.copyWith(
      phase: HistoryLoadPhase.loading,
      from: start,
      to: end,
      events: localEvents,
      usingLocalData: localEvents.isNotEmpty,
    );

    try {
      final events = await _ref.read(attendanceRepositoryProvider).history(
            from: start,
            to: end,
          );
      state = state.copyWith(
        phase: HistoryLoadPhase.ready,
        events: _mergeEvents(events, localEvents),
        usingLocalData: false,
      );
    } on AppException catch (error) {
      if (localEvents.isNotEmpty) {
        state = state.copyWith(
          phase: HistoryLoadPhase.ready,
          events: _mergeEvents(const [], localEvents),
          errorMessage: error.message,
          usingLocalData: true,
        );
        return;
      }
      state = state.copyWith(
        phase: HistoryLoadPhase.error,
        events: const [],
        errorMessage: error.message,
        usingLocalData: false,
      );
    }
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
    result.sort((a, b) {
      final left = a.eventAt;
      final right = b.eventAt;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return left.compareTo(right);
    });
    return result;
  }
}

final historyControllerProvider =
    StateNotifierProvider<HistoryController, HistoryState>(
  (ref) => HistoryController(ref),
);
