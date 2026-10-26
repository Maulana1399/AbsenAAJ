import 'package:absen_aaj/core/auth/session_controller.dart';
import 'package:absen_aaj/core/errors/app_exception.dart';
import 'package:absen_aaj/features/attendance/data/attendance_repository.dart';
import 'package:absen_aaj/features/attendance/data/local/local_attendance_providers.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_outbox_event.dart';
import 'package:absen_aaj/features/home/application/home_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeLocalAttendanceReader localReader;
  late RecordingAttendanceRepository repository;

  setUp(() {
    localReader = FakeLocalAttendanceReader();
    repository = RecordingAttendanceRepository();

    container = ProviderContainer(
      overrides: [
        sessionControllerProvider.overrideWith(
          (ref) => FakeSessionController(ref),
        ),
        attendanceRepositoryProvider.overrideWithValue(repository),
        attendanceLocalReaderProvider.overrideWithValue(localReader),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('home status uses a local pending check-in while offline', () async {
    repository.historyError = const NetworkException();
    localReader.events.add(
      makeOutboxEvent(
        clientEventId: 'local-check-in',
        eventType: AttendanceEventType.checkIn,
      ),
    );

    await container.read(homeControllerProvider.notifier).reload();

    final state = container.read(homeControllerProvider);
    expect(state.phase, HomeLoadPhase.ready);
    expect(state.today.status, TodayAttendanceStatus.checkedIn);
    expect(state.today.checkIn?.clientEventId, 'local-check-in');
    expect(state.usingLocalData, isTrue);
  });

  test('home status uses a local pending check-out while offline', () async {
    repository.historyError = const NetworkException();
    localReader.events.addAll([
      makeOutboxEvent(
        clientEventId: 'local-check-in',
        eventType: AttendanceEventType.checkIn,
      ),
      makeOutboxEvent(
        clientEventId: 'local-check-out',
        eventType: AttendanceEventType.checkOut,
      ),
    ]);

    await container.read(homeControllerProvider.notifier).reload();

    final state = container.read(homeControllerProvider);
    expect(state.today.status, TodayAttendanceStatus.done);
    expect(state.today.checkOut?.clientEventId, 'local-check-out');
  });

  test('server events win over the matching local copy', () async {
    repository.historyEvents = [
      makeEvent(
        id: 7,
        clientEventId: 'local-check-in',
        eventType: 'CHECK_IN',
        status: 'LATE',
      ),
    ];
    localReader.events.add(
      makeOutboxEvent(
        clientEventId: 'local-check-in',
        state: AttendanceOutboxState.synced,
        serverStatus: 'PENDING_SYNC',
        serverEventId: 7,
      ),
    );

    await container.read(homeControllerProvider.notifier).reload();

    final state = container.read(homeControllerProvider);
    expect(state.today.status, TodayAttendanceStatus.checkedIn);
    expect(state.today.checkIn?.status, 'LATE');
    expect(state.usingLocalData, isFalse);
  });

  test('rejected local events do not make home look checked in', () async {
    repository.historyError = const NetworkException();
    localReader.events.add(
      makeOutboxEvent(
        clientEventId: 'rejected-check-in',
        state: AttendanceOutboxState.rejected,
      ),
    );

    await container.read(homeControllerProvider.notifier).reload();

    final state = container.read(homeControllerProvider);
    expect(state.today.status, TodayAttendanceStatus.none);
    expect(state.usingLocalData, isTrue);
  });
}
