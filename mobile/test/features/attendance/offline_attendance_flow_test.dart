import 'dart:io';

import 'package:absen_aaj/core/auth/session_controller.dart';
import 'package:absen_aaj/core/storage/device_identity.dart';
import 'package:absen_aaj/features/attendance/application/attendance_controller.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_policy.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_providers.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_worker.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_database.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_repository.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_store.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_photo_storage.dart';
import 'package:absen_aaj/features/attendance/data/local/local_attendance_providers.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_outbox_event.dart';
import 'package:absen_aaj/features/attendance/services/camera_service.dart';
import 'package:absen_aaj/features/attendance/services/location_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fakes.dart';
import 'data/local/sqlite_test_support.dart';

void main() {
  late Directory temp;
  late AttendanceOutboxDatabase database;
  late SqliteAttendanceOutboxStore store;
  late FileAttendancePhotoStorage photoStorage;
  late AttendanceOutboxRepository repository;
  late FakeSyncRunner runner;
  late ProviderContainer container;

  setUpAll(configureSqliteForTests);

  setUp(() async {
    temp = await createTempDirectory();
    database = AttendanceOutboxDatabase(
      factory: databaseFactoryFfiNoIsolate,
      pathProvider: () async => databasePathIn(temp),
    );
    store = SqliteAttendanceOutboxStore(database);
    photoStorage = FileAttendancePhotoStorage(
      directoryProvider: () async => Directory(p.join(temp.path, 'photos')),
    );
    repository = AttendanceOutboxRepository(store, photoStorage);
    runner = FakeSyncRunner();

    container = ProviderContainer(
      overrides: [
        locationServiceProvider.overrideWithValue(FakeLocationService()),
        cameraServiceProvider.overrideWithValue(
          FakeCameraService(
            result: SelfieResult(
              bytes: validJpegBytes,
              capturedAt: DateTime(2026, 10, 6, 8, 30),
            ),
          ),
        ),
        deviceIdentityProvider.overrideWithValue(FakeDeviceIdentity()),
        attendanceOutboxWriterProvider.overrideWithValue(repository),
        attendanceSyncRunnerProvider.overrideWithValue(runner),
        sessionControllerProvider.overrideWith(
          (ref) => FakeSessionController(ref),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<AttendanceOutboxEvent> queuedFromState() async {
    final event = container.read(attendanceSubmissionProvider).queuedEvent;
    expect(event, isNotNull);
    final persisted = await store.findForOwner(
      clientEventId: event!.clientEventId,
      ownerUserId: testUser.id,
    );
    expect(persisted, isNotNull);
    return persisted!;
  }

  void failSyncWithNetwork() {
    runner.onSync = (ownerUserId, employeeId) =>
        const AttendanceSyncRunResult(
          failure: AttendanceSyncFailure(
            kind: AttendanceSyncFailureKind.retryable,
            code: 'NETWORK_ERROR',
            message: 'offline',
          ),
        );
  }

  test('offline CHECK IN is durably stored in the outbox with its photo',
      () async {
    failSyncWithNetwork();

    await container
        .read(attendanceSubmissionProvider.notifier)
        .submitCheckIn();

    final persisted = await queuedFromState();
    expect(persisted.state, AttendanceOutboxState.pending);
    expect(persisted.eventType, AttendanceEventType.checkIn);
    expect(await photoStorage.exists(persisted.photoFilename), isTrue);
    expect(container.read(attendanceSubmissionProvider).isQueued, isTrue);
  });

  test('offline CHECK OUT is durably stored in the outbox with its photo',
      () async {
    failSyncWithNetwork();

    await container
        .read(attendanceSubmissionProvider.notifier)
        .submitCheckOut();

    final persisted = await queuedFromState();
    expect(persisted.state, AttendanceOutboxState.pending);
    expect(persisted.eventType, AttendanceEventType.checkOut);
    expect(await photoStorage.exists(persisted.photoFilename), isTrue);
  });

  test('socket/timeout after enqueue does not remove the local event',
      () async {
    runner.onSync = (ownerUserId, employeeId) =>
        throw const SocketException('network unreachable');

    await container
        .read(attendanceSubmissionProvider.notifier)
        .submitCheckIn();

    final persisted = await queuedFromState();
    expect(persisted.state, AttendanceOutboxState.pending);
    expect(await photoStorage.exists(persisted.photoFilename), isTrue);
    expect(
      container.read(attendanceSubmissionProvider).errorMessage,
      AttendanceSubmissionController.localQueuedMessage,
    );
  });

}
