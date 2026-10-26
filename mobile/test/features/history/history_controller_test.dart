import 'package:absen_aaj/core/auth/session_controller.dart';
import 'package:absen_aaj/core/errors/app_exception.dart';
import 'package:absen_aaj/features/attendance/data/attendance_repository.dart';
import 'package:absen_aaj/features/attendance/data/local/local_attendance_providers.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_outbox_event.dart';
import 'package:absen_aaj/features/history/application/history_controller.dart';
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

  test('history falls back to local outbox rows when offline', () async {
    repository.historyError = const NetworkException();
    localReader.events.add(
      makeOutboxEvent(
        clientEventId: 'offline-history',
        eventType: AttendanceEventType.checkIn,
      ),
    );

    await container.read(historyControllerProvider.notifier).load();

    final state = container.read(historyControllerProvider);
    expect(state.phase, HistoryLoadPhase.ready);
    expect(state.events.single.clientEventId, 'offline-history');
    expect(state.events.single.status, 'PENDING_SYNC');
    expect(state.usingLocalData, isTrue);
  });

  test('history does not duplicate a server event already in the outbox',
      () async {
    repository.historyEvents = [
      makeEvent(id: 3, clientEventId: 'same-event', status: 'ON_TIME'),
    ];
    localReader.events.add(
      makeOutboxEvent(
        clientEventId: 'same-event',
        state: AttendanceOutboxState.synced,
        serverStatus: 'ON_TIME',
        serverEventId: 3,
      ),
    );

    await container.read(historyControllerProvider.notifier).load();

    final state = container.read(historyControllerProvider);
    expect(state.events, hasLength(1));
    expect(state.events.single.id, 3);
    expect(state.usingLocalData, isFalse);
  });
}
