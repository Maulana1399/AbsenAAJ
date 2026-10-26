import 'dart:async';
import 'dart:io';

import 'package:absen_aaj/core/auth/session_controller.dart';
import 'package:absen_aaj/core/errors/app_exception.dart';
import 'package:absen_aaj/core/storage/device_identity.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_policy.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_providers.dart';
import 'package:absen_aaj/features/attendance/application/attendance_sync_worker.dart';
import 'package:absen_aaj/features/attendance/data/attendance_repository.dart';
import 'package:absen_aaj/features/attendance/data/attendance_sync_api.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_database.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_repository.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_store.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_photo_storage.dart';
import 'package:absen_aaj/features/attendance/data/local/local_attendance_providers.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_outbox_event.dart';
import 'package:absen_aaj/features/attendance/services/camera_service.dart';
import 'package:absen_aaj/features/attendance/services/location_service.dart';
import 'package:absen_aaj/features/home/application/home_controller.dart';
import 'package:absen_aaj/features/home/presentation/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fakes.dart';
import 'data/local/sqlite_test_support.dart';

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

/// Enqueues one event into [outbox] using [validJpegBytes] so that photo
/// validation passes. Returns the persisted outbox event.
Future<AttendanceOutboxEvent> enqueueOne(
  AttendanceOutboxRepository outbox, {
  String clientEventId = 'event-1',
  int ownerUserId = 1,
  int employeeId = 10,
  AttendanceEventType type = AttendanceEventType.checkIn,
  DateTime? eventAt,
}) {
  final at = eventAt ?? DateTime.utc(2026, 10, 23, 8, 0);
  return outbox.enqueue(
    clientEventId: clientEventId,
    ownerUserId: ownerUserId,
    employeeId: employeeId,
    deviceUuid: 'device-uuid-test',
    eventType: type,
    eventAt: at,
    capturedAt: at.subtract(const Duration(seconds: 5)),
    gps: const GpsReading(
      latitude: -5.1477,
      longitude: 119.4326,
      accuracyMeters: 20,
    ),
    photoBytes: validJpegBytes,
  );
}

// ---------------------------------------------------------------------------
// Test 1–5: worker-level sync trigger behaviour (no UI required)
// ---------------------------------------------------------------------------

void main() {
  late Directory temp;
  late AttendanceOutboxDatabase database;
  late SqliteAttendanceOutboxStore store;
  late FileAttendancePhotoStorage photoStorage;
  late AttendanceOutboxRepository outbox;
  late DateTime now;

  const ownerUserId = 1;
  const employeeId = 10;

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
    now = DateTime.utc(2026, 10, 23, 8, 0);
    outbox = AttendanceOutboxRepository(store, photoStorage, clock: () => now);
  });

  tearDown(() async {
    await database.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  // Helper: build worker backed by a real DB and a fake API
  AttendanceSyncWorker makeWorker(
    FakeSyncApi api, {
    bool sessionActive = true,
  }) {
    return AttendanceSyncWorker(
      outbox,
      photoStorage,
      api,
      clock: () => now,
      isSessionActive: () => sessionActive,
    );
  }

  // -------------------------------------------------------------------------
  // Test 1: Event pending tersinkron setelah jaringan pulih.
  // -------------------------------------------------------------------------
  test(
    'pending event syncs successfully when network becomes available',
    () async {
      final queued = await enqueueOne(outbox);

      final api = FakeSyncApi();
      api.handler = (s) => throw networkError();
      final worker = makeWorker(api);

      // Attempt 1: offline — event stays pending
      await worker.syncNow(ownerUserId: ownerUserId, employeeId: employeeId);
      var persisted = await outbox.findForOwner(
        clientEventId: queued.clientEventId,
        ownerUserId: ownerUserId,
      );
      expect(persisted!.state, AttendanceOutboxState.pending);
      expect(persisted.attemptCount, 2);

      // Advance clock past backoff so claimNext allows it
      now = now.add(const Duration(minutes: 2));

      // Attempt 2: network back — API succeeds
      api.handler = null; // default: ack
      final result = await worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );

      expect(result.failure, isNull);
      expect(result.acknowledged.single.clientEventId, queued.clientEventId);
      persisted = await outbox.findForOwner(
        clientEventId: queued.clientEventId,
        ownerUserId: ownerUserId,
      );
      expect(persisted!.state, AttendanceOutboxState.synced);
    },
  );

  // -------------------------------------------------------------------------
  // Test 2: App kembali ke foreground memicu sync dengan aman (widget test).
  //
  // Dibuktikan bahwa HomePage memanggil syncNow saat didChangeAppLifecycleState
  // dipanggil dengan AppLifecycleState.resumed.
  // -------------------------------------------------------------------------
  testWidgets(
    'HomePage triggers sync when app resumes from background',
    (tester) async {
      final runner = FakeSyncRunner();
      final repo = _StaticRepo(const []);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            locationServiceProvider.overrideWithValue(FakeLocationService()),
            cameraServiceProvider.overrideWithValue(FakeCameraService()),
            deviceIdentityProvider.overrideWithValue(FakeDeviceIdentity()),
            attendanceSyncRunnerProvider.overrideWithValue(runner),
            attendanceRepositoryProvider.overrideWithValue(repo),
            attendanceLocalReaderProvider.overrideWithValue(
              FakeLocalAttendanceReader(),
            ),
            sessionControllerProvider.overrideWith(
              (ref) => FakeSessionController(ref),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: HomePage())),
        ),
      );

      await tester.pumpAndSettle();
      final callsAfterInit = runner.calls;

      // Simulate app coming back to foreground
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      // Allow microtask in _triggerSync to run
      await tester.pump(Duration.zero);

      expect(
        runner.calls,
        greaterThan(callsAfterInit),
        reason: 'syncNow must be called when the app resumes',
      );
    },
  );

  // -------------------------------------------------------------------------
  // Test 3: Backoff yang belum jatuh tempo tetap dihormati.
  // -------------------------------------------------------------------------
  test(
    'backoff window is respected — event is skipped until next_attempt_at',
    () async {
      final queued = await enqueueOne(outbox);

      final api = FakeSyncApi();
      api.handler = (s) => throw networkError();
      final worker = makeWorker(api);

      // First attempt: fails, sets next_attempt_at = now + 30s
      await worker.syncNow(ownerUserId: ownerUserId, employeeId: employeeId);

      // Advance by only 10 seconds — still within backoff
      now = now.add(const Duration(seconds: 10));

      // Worker tries again but event is not yet due
      api.handler = null; // would succeed if reached
      final retryTooEarly = await worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );

      // No event claimed, no API call on second attempt
      expect(retryTooEarly.failure, isNull);
      expect(retryTooEarly.acknowledged, isEmpty);
      expect(api.submissions, hasLength(1)); // only the first failed attempt

      // Confirm event is still pending
      final persisted = await outbox.findForOwner(
        clientEventId: queued.clientEventId,
        ownerUserId: ownerUserId,
      );
      expect(persisted!.state, AttendanceOutboxState.pending);
    },
  );

  // -------------------------------------------------------------------------
  // Test 4: Dua trigger bersamaan tidak mengirim event duplikat.
  // -------------------------------------------------------------------------
  test(
    'concurrent sync triggers send the event exactly once',
    () async {
      final queued = await enqueueOne(outbox);

      final gate = Completer<void>();
      final api = FakeSyncApi();
      api.handler = (s) async {
        await gate.future;
        return ackFor(s);
      };
      final worker = makeWorker(api);

      // Two triggers in parallel (simulates page init + lifecycle resume)
      final first = worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );
      final second = worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );

      await Future<void>.delayed(Duration.zero);
      gate.complete();
      await Future.wait([first, second]);

      expect(api.submissions, hasLength(1));
      final persisted = await outbox.findForOwner(
        clientEventId: queued.clientEventId,
        ownerUserId: ownerUserId,
      );
      expect(persisted!.state, AttendanceOutboxState.synced);
      expect(persisted.attemptCount, 1);
    },
  );

  // -------------------------------------------------------------------------
  // Test 5: Kegagalan autentikasi tidak menghapus event lokal.
  // -------------------------------------------------------------------------
  test(
    'authentication failure does not delete local event or photo',
    () async {
      final queued = await enqueueOne(outbox);

      var sessionActive = false;
      final api = FakeSyncApi();
      final worker = AttendanceSyncWorker(
        outbox,
        photoStorage,
        api,
        clock: () => now,
        isSessionActive: () => sessionActive,
      );

      final result = await worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );

      expect(result.failure!.kind, AttendanceSyncFailureKind.authentication);
      expect(api.submissions, isEmpty);

      final persisted = await outbox.findForOwner(
        clientEventId: queued.clientEventId,
        ownerUserId: ownerUserId,
      );
      expect(persisted!.state, AttendanceOutboxState.pending);
      expect(await photoStorage.exists(queued.photoFilename), isTrue);

      // After session is restored, sync succeeds
      sessionActive = true;
      final resumed = await worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );
      expect(resumed.failure, isNull);
      expect(resumed.acknowledged.single.clientEventId, queued.clientEventId);
    },
  );

  // -------------------------------------------------------------------------
  // Test 6: UI berubah dari pending menjadi synced setelah server konfirmasi.
  // -------------------------------------------------------------------------
  testWidgets(
    'home status changes from checkedIn (pending) to checkedIn (synced) after sync',
    (tester) async {
      // Arrange: local outbox has one pending check-in
      final pendingEvent = makeOutboxEvent(
        clientEventId: 'sync-me',
        ownerUserId: ownerUserId,
        employeeId: employeeId,
        eventType: AttendanceEventType.checkIn,
        state: AttendanceOutboxState.pending,
        eventAt: DateTime.now(),
      );
      final localReader = FakeLocalAttendanceReader()..events.add(pendingEvent);

      // First load: server is unreachable
      final repo = _ErrorOnFirstThenSuccess(
        firstError: const NetworkException(),
        thenEvents: [
          makeEvent(
            id: 99,
            clientEventId: 'sync-me',
            eventType: 'CHECK_IN',
            status: 'ON_TIME',
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          sessionControllerProvider.overrideWith(
            (ref) => FakeSessionController(ref),
          ),
          attendanceRepositoryProvider.overrideWithValue(repo),
          attendanceLocalReaderProvider.overrideWithValue(localReader),
        ],
      );
      addTearDown(container.dispose);

      // Initial load: offline → shows local pending
      await container.read(homeControllerProvider.notifier).reload();
      var home = container.read(homeControllerProvider);
      expect(home.today.status, TodayAttendanceStatus.checkedIn);
      expect(home.usingLocalData, isTrue);

      // After "sync" the server responds with synced event
      await container.read(homeControllerProvider.notifier).reload();
      home = container.read(homeControllerProvider);
      expect(home.today.status, TodayAttendanceStatus.checkedIn);
      expect(home.usingLocalData, isFalse);
      expect(home.today.checkIn?.status, 'ON_TIME');
    },
  );

  // -------------------------------------------------------------------------
  // Test 7: Event pending tetap ada jika server tidak dapat dijangkau.
  // -------------------------------------------------------------------------
  test(
    'pending event survives when server is unreachable on retry attempt',
    () async {
      final queued = await enqueueOne(outbox);

      final api = FakeSyncApi()..handler = (s) => throw networkError();
      final worker = makeWorker(api);

      // First attempt
      await worker.syncNow(ownerUserId: ownerUserId, employeeId: employeeId);
      now = now.add(const Duration(minutes: 2));

      // Second attempt still fails
      await worker.syncNow(ownerUserId: ownerUserId, employeeId: employeeId);

      final persisted = await outbox.findForOwner(
        clientEventId: queued.clientEventId,
        ownerUserId: ownerUserId,
      );
      expect(persisted!.state, AttendanceOutboxState.pending);
      expect(await photoStorage.exists(queued.photoFilename), isTrue);
      // Both attempts were made with the same client_event_id
      expect(api.submissions, hasLength(2));
      expect(
        api.submissions.map((s) => s.clientEventId).toSet(),
        {queued.clientEventId},
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Local helpers
// ---------------------------------------------------------------------------

AttendanceSyncApiException networkError() => const AttendanceSyncApiException(
  code: 'NETWORK_ERROR',
  message: 'offline',
  isNetwork: true,
);

AttendanceSyncResponse ackFor(SyncSubmission s, {int id = 1}) {
  return AttendanceSyncResponse(
    statusCode: 201,
    event: AttendanceEvent(
      id: id,
      clientEventId: s.clientEventId,
      eventType: s.eventType.key,
      status: 'ON_TIME',
      eventAt: s.eventAt,
      serverReceivedAt: s.eventAt,
    ),
  );
}

class SyncSubmission {
  SyncSubmission({
    required this.index,
    required this.clientEventId,
    required this.deviceUuid,
    required this.eventType,
    required this.eventAt,
    required this.gps,
    required this.capturedAt,
    required this.photoBytes,
  });

  final int index;
  final String clientEventId;
  final String deviceUuid;
  final AttendanceEventType eventType;
  final DateTime eventAt;
  final GpsReading gps;
  final DateTime capturedAt;
  final List<int> photoBytes;

  int get attempt => index + 1;
}

class FakeSyncApi implements AttendanceSyncApi {
  final submissions = <SyncSubmission>[];
  FutureOr<AttendanceSyncResponse> Function(SyncSubmission)? handler;

  @override
  Future<AttendanceSyncResponse> submit({
    required String clientEventId,
    required String deviceUuid,
    required AttendanceEventType eventType,
    required DateTime eventAt,
    required GpsReading gps,
    required DateTime capturedAt,
    required List<int> photoBytes,
  }) async {
    final s = SyncSubmission(
      index: submissions.length,
      clientEventId: clientEventId,
      deviceUuid: deviceUuid,
      eventType: eventType,
      eventAt: eventAt,
      gps: gps,
      capturedAt: capturedAt,
      photoBytes: List<int>.of(photoBytes),
    );
    submissions.add(s);
    final cb = handler;
    if (cb != null) return cb(s);
    return ackFor(s);
  }
}

/// Fake repository that raises [firstError] on the first [history] call, then
/// returns [thenEvents] on subsequent calls.
class _ErrorOnFirstThenSuccess implements AttendanceRepository {
  _ErrorOnFirstThenSuccess({
    required this.firstError,
    required this.thenEvents,
  });

  final Object firstError;
  final List<AttendanceEvent> thenEvents;
  int _calls = 0;

  @override
  Future<List<AttendanceEvent>> history({DateTime? from, DateTime? to}) async {
    _calls++;
    if (_calls == 1) throw firstError;
    return thenEvents;
  }

  @override
  Future<AttendanceEvent> submitEvent({
    required String clientEventId,
    required String deviceUuid,
    required AttendanceEventType eventType,
    required DateTime eventAt,
    required GpsReading gps,
    required DateTime capturedAt,
    required List<int> photoBytes,
  }) => throw StateError('not used');

  @override
  Future<DeviceInfo> registerDevice({
    required String deviceUuid,
    String? manufacturer,
    String? model,
    String? appVersion,
  }) async => DeviceInfo(id: 1, deviceUuid: deviceUuid, status: 'ACTIVE');
}

class _StaticRepo implements AttendanceRepository {
  _StaticRepo(this._events);
  final List<AttendanceEvent> _events;

  @override
  Future<List<AttendanceEvent>> history({DateTime? from, DateTime? to}) async =>
      _events;

  @override
  Future<AttendanceEvent> submitEvent({
    required String clientEventId,
    required String deviceUuid,
    required AttendanceEventType eventType,
    required DateTime eventAt,
    required GpsReading gps,
    required DateTime capturedAt,
    required List<int> photoBytes,
  }) => throw StateError('not used');

  @override
  Future<DeviceInfo> registerDevice({
    required String deviceUuid,
    String? manufacturer,
    String? model,
    String? appVersion,
  }) async => DeviceInfo(id: 1, deviceUuid: deviceUuid, status: 'ACTIVE');
}
