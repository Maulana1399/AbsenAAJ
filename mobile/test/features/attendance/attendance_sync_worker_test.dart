import 'dart:async';
import 'dart:io';

import 'package:absen_aaj/features/attendance/application/attendance_sync_worker.dart';
import 'package:absen_aaj/features/attendance/data/attendance_sync_api.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_database.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_repository.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_store.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_photo_storage.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_outbox_event.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'data/local/sqlite_test_support.dart';

void main() {
  late Directory temp;
  late AttendanceOutboxDatabase database;
  late SqliteAttendanceOutboxStore store;
  late FileAttendancePhotoStorage photoStorage;
  late AttendanceOutboxRepository outbox;
  late FakeSyncApi api;
  late AttendanceSyncWorker worker;
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
    api = FakeSyncApi();
    now = DateTime.utc(2026, 10, 6, 8, 30, 15);
    outbox = AttendanceOutboxRepository(store, photoStorage, clock: () => now);
    worker = AttendanceSyncWorker(outbox, photoStorage, api, clock: () => now);
  });

  tearDown(() async {
    await database.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<AttendanceOutboxEvent> enqueue({
    String clientEventId = 'event-1',
    int owner = ownerUserId,
    int employee = employeeId,
    AttendanceEventType type = AttendanceEventType.checkIn,
  }) {
    return outbox.enqueue(
      clientEventId: clientEventId,
      ownerUserId: owner,
      employeeId: employee,
      deviceUuid: 'device-1',
      eventType: type,
      eventAt: now,
      capturedAt: now.subtract(const Duration(minutes: 1)),
      gps: const GpsReading(
        latitude: -5.1477,
        longitude: 119.4326,
        accuracyMeters: 20,
      ),
      photoBytes: validJpegBytes,
    );
  }

  Future<AttendanceOutboxEvent?> stored(String id) =>
      outbox.findForOwner(clientEventId: id, ownerUserId: ownerUserId);

  test('acknowledges a valid server response and deletes the photo', () async {
    final queued = await enqueue();
    api.statusCode = 201;

    final result = await worker.syncNow(
      ownerUserId: ownerUserId,
      employeeId: employeeId,
    );

    expect(result.failure, isNull);
    expect(result.acknowledged.single.clientEventId, queued.clientEventId);
    final persisted = await stored(queued.clientEventId);
    expect(persisted!.state, AttendanceOutboxState.synced);
    expect(persisted.serverEventId, 1);
    expect(persisted.serverStatus, 'ON_TIME');
    expect(await photoStorage.exists(queued.photoFilename), isFalse);
  });

  test('acks with HTTP 200 replay as well as HTTP 201 creation', () async {
    final queued = await enqueue();
    api.statusCode = 200;

    final result = await worker.syncNow(
      ownerUserId: ownerUserId,
      employeeId: employeeId,
    );

    expect(result.failure, isNull);
    expect(
      (await stored(queued.clientEventId))!.state,
      AttendanceOutboxState.synced,
    );
  });

  test(
    'a network failure keeps the event and photo and schedules a retry',
    () async {
      final queued = await enqueue();
      api.handler = (submission) => throw networkFailure();

      final result = await worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );

      expect(result.failure!.kind.name, 'retryable');
      final persisted = await stored(queued.clientEventId);
      expect(persisted!.state, AttendanceOutboxState.pending);
      expect(persisted.attemptCount, 2);
      expect(persisted.lastErrorCode, 'NETWORK_ERROR');
      expect(persisted.nextAttemptAt, now.add(const Duration(seconds: 30)));
      expect(await photoStorage.exists(queued.photoFilename), isTrue);
    },
  );

  test('retries with the same id, timestamp, GPS and photo payload', () async {
    final queued = await enqueue(clientEventId: 'stable-id');
    api.handler = (submission) {
      if (submission.attempt == 1) throw networkFailure();
      return ackFor(submission);
    };

    await worker.syncNow(ownerUserId: ownerUserId, employeeId: employeeId);
    now = now.add(const Duration(minutes: 1));
    final second = await worker.syncNow(
      ownerUserId: ownerUserId,
      employeeId: employeeId,
    );

    expect(api.submissions, hasLength(2));
    final first = api.submissions[0];
    final retry = api.submissions[1];
    expect(retry.clientEventId, first.clientEventId);
    expect(retry.eventAt, first.eventAt);
    expect(retry.capturedAt, first.capturedAt);
    expect(retry.deviceUuid, first.deviceUuid);
    expect(retry.gps.latitude, first.gps.latitude);
    expect(retry.gps.longitude, first.gps.longitude);
    expect(retry.gps.accuracyMeters, first.gps.accuracyMeters);
    expect(retry.photoBytes, first.photoBytes);
    expect(second.failure, isNull);
    expect(
      (await stored(queued.clientEventId))!.state,
      AttendanceOutboxState.synced,
    );
  });

  test(
    'a timeout after the server saved replays the same event without a dup',
    () async {
      final queued = await enqueue(clientEventId: 'timeout-id');
      var serverSaved = false;
      api.handler = (submission) {
        if (!serverSaved) {
          serverSaved = true;
          throw networkFailure();
        }
        return ackFor(submission, id: 77);
      };

      await worker.syncNow(ownerUserId: ownerUserId, employeeId: employeeId);
      now = now.add(const Duration(minutes: 1));
      final replay = await worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );

      expect(api.submissions, hasLength(2));
      expect(api.submissions.map((s) => s.clientEventId).toSet(), {
        queued.clientEventId,
      });
      expect(replay.acknowledged.single.id, 77);
      expect((await stored(queued.clientEventId))!.serverEventId, 77);
    },
  );

  test(
    'syncs a check-in before a newer check-out for the same employee',
    () async {
      await enqueue(
        clientEventId: 'check-in',
        type: AttendanceEventType.checkIn,
      );
      await enqueue(
        clientEventId: 'check-out',
        type: AttendanceEventType.checkOut,
      );

      final result = await worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );

      expect(result.failure, isNull);
      expect(api.submissions.map((s) => s.eventType.key).toList(), [
        'CHECK_IN',
        'CHECK_OUT',
      ]);
    },
  );

  test(
    'a rejected older event does not block newer pending events for that employee',
    () async {
      final older = await enqueue(
        clientEventId: 'older',
        type: AttendanceEventType.checkIn,
      );
      await enqueue(clientEventId: 'newer', type: AttendanceEventType.checkOut);
      api.handler = (submission) {
        if (submission.clientEventId == 'older') {
          throw const AttendanceSyncApiException(
            statusCode: 422,
            code: 'OUTSIDE_GEOFENCE',
            message: 'outside',
          );
        }
        return ackFor(submission);
      };

      final result = await worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );

      expect(result.failure!.kind.name, 'permanentRejection');
      expect(
        (await stored(older.clientEventId))!.state,
        AttendanceOutboxState.rejected,
      );
      expect(api.submissions, hasLength(1));

      final second = await worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );
      expect(second.failure, isNull);
      expect(second.acknowledged.single.clientEventId, 'newer');
      expect(api.submissions, hasLength(2));
      expect(
        (await stored('newer'))!.state,
        AttendanceOutboxState.synced,
      );
    },
  );

  test('one employee failure does not block another employee', () async {
    await enqueue(clientEventId: 'blocked', employee: 10);
    await enqueue(clientEventId: 'independent', employee: 11);
    api.handler = (submission) {
      if (submission.clientEventId == 'blocked') {
        throw const AttendanceSyncApiException(
          statusCode: 422,
          code: 'OUTSIDE_GEOFENCE',
          message: 'outside',
        );
      }
      return ackFor(submission);
    };

    await worker.syncNow(ownerUserId: ownerUserId, employeeId: 10);
    final other = await worker.syncNow(
      ownerUserId: ownerUserId,
      employeeId: 11,
    );

    expect(other.failure, isNull);
    expect((await stored('independent'))!.state, AttendanceOutboxState.synced);
  });

  test('two concurrent triggers send the event only once', () async {
    final queued = await enqueue();
    final gate = Completer<void>();
    api.handler = (submission) async {
      await gate.future;
      return ackFor(submission);
    };

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
    final persisted = await stored(queued.clientEventId);
    expect(persisted!.state, AttendanceOutboxState.synced);
    expect(persisted.attemptCount, 1);
  });

  test('recovers an expired lease before sending', () async {
    final queued = await enqueue();
    await outbox.claimNextForEmployee(
      ownerUserId: ownerUserId,
      employeeId: employeeId,
      now: now,
    );

    now = now.add(const Duration(hours: 1));
    final result = await worker.syncNow(
      ownerUserId: ownerUserId,
      employeeId: employeeId,
    );

    expect(result.failure, isNull);
    expect(api.submissions, hasLength(1));
    expect(
      (await stored(queued.clientEventId))!.state,
      AttendanceOutboxState.synced,
    );
  });

  test(
    'an invalid session pauses without sending or deleting the queue',
    () async {
      final queued = await enqueue();
      var active = false;
      worker = AttendanceSyncWorker(
        outbox,
        photoStorage,
        api,
        clock: () => now,
        isSessionActive: () => active,
      );

      final paused = await worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );

      expect(paused.failure!.kind.name, 'authentication');
      expect(api.submissions, isEmpty);
      expect(
        (await stored(queued.clientEventId))!.state,
        AttendanceOutboxState.pending,
      );
      expect(await photoStorage.exists(queued.photoFilename), isTrue);

      active = true;
      final resumed = await worker.syncNow(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
      );
      expect(resumed.failure, isNull);
    },
  );

  test('a 401 pauses without losing the event', () async {
    final queued = await enqueue();
    api.handler = (_) => throw const AttendanceSyncApiException(
      statusCode: 401,
      code: 'UNAUTHENTICATED',
      message: 'expired',
    );

    final result = await worker.syncNow(
      ownerUserId: ownerUserId,
      employeeId: employeeId,
    );

    expect(result.failure!.kind.name, 'authentication');
    final persisted = await stored(queued.clientEventId);
    expect(persisted!.state, AttendanceOutboxState.pending);
    expect(persisted.nextAttemptAt, now);
    expect(await photoStorage.exists(queued.photoFilename), isTrue);
  });

  test('does not mark synced on an invalid response body', () async {
    final queued = await enqueue();
    api.handler = (_) => throw const AttendanceSyncApiException(
      code: 'SYNC_BAD_RESPONSE',
      message: 'invalid',
      isProtocol: true,
    );

    final result = await worker.syncNow(
      ownerUserId: ownerUserId,
      employeeId: employeeId,
    );

    expect(result.failure!.kind.name, 'retryable');
    expect(
      (await stored(queued.clientEventId))!.state,
      AttendanceOutboxState.pending,
    );
  });
}

AttendanceSyncApiException networkFailure() => const AttendanceSyncApiException(
  code: 'NETWORK_ERROR',
  message: 'offline',
  isNetwork: true,
);

AttendanceSyncResponse ackFor(SyncSubmission submission, {int id = 1}) {
  return AttendanceSyncResponse(
    statusCode: 201,
    event: AttendanceEvent(
      id: id,
      clientEventId: submission.clientEventId,
      eventType: submission.eventType.key,
      status: 'ON_TIME',
      serverReceivedAt: submission.eventAt,
      eventAt: submission.eventAt,
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
  int statusCode = 201;
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
    final submission = SyncSubmission(
      index: submissions.length,
      clientEventId: clientEventId,
      deviceUuid: deviceUuid,
      eventType: eventType,
      eventAt: eventAt,
      gps: gps,
      capturedAt: capturedAt,
      photoBytes: List<int>.of(photoBytes),
    );
    submissions.add(submission);
    final callback = handler;
    if (callback != null) return callback(submission);
    return ackFor(submission);
  }
}
