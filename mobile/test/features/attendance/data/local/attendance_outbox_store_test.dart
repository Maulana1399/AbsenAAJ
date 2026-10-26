import 'dart:io';

import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_database.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_exceptions.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_store.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_outbox_event.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'sqlite_test_support.dart';

void main() {
  late Directory temp;
  late AttendanceOutboxDatabase database;
  late SqliteAttendanceOutboxStore store;

  final now = DateTime.utc(2026, 10, 6, 9);

  setUpAll(configureSqliteForTests);

  setUp(() async {
    temp = await createTempDirectory();
    database = AttendanceOutboxDatabase(
      factory: databaseFactoryFfiNoIsolate,
      pathProvider: () async => databasePathIn(temp),
    );
    store = SqliteAttendanceOutboxStore(database);
  });

  tearDown(() async {
    await database.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<AttendanceOutboxEvent> insertEvent({
    String clientEventId = 'event-1',
    int ownerUserId = 1,
    int employeeId = 10,
    String deviceUuid = 'device-1',
    AttendanceEventType eventType = AttendanceEventType.checkIn,
    DateTime? eventAt,
    DateTime? capturedAt,
    double latitude = -5.1477,
    double longitude = 119.4326,
    double accuracyMeters = 20,
    String? photoFilename,
    DateTime? createdAt,
  }) async {
    final result = await store.insertPending(
      AttendanceOutboxEvent.pending(
        clientEventId: clientEventId,
        ownerUserId: ownerUserId,
        employeeId: employeeId,
        deviceUuid: deviceUuid,
        eventType: eventType,
        eventAt: eventAt ?? DateTime.utc(2026, 10, 6, 8, 30),
        capturedAt: capturedAt ?? DateTime.utc(2026, 10, 6, 8, 29, 30),
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: accuracyMeters,
        photoFilename: photoFilename ?? '$clientEventId.jpg',
        createdAt: createdAt ?? DateTime.utc(2026, 10, 6, 8, 31),
      ),
    );
    return result.event;
  }

  test(
    'insertPending canonicalizes the event and assigns FIFO sequence',
    () async {
      final inserted = await insertEvent(
        clientEventId: 'event-full',
        ownerUserId: 7,
        employeeId: 70,
        deviceUuid: 'device-7',
        eventType: AttendanceEventType.checkOut,
        eventAt: DateTime.utc(2026, 10, 6, 8, 30, 0, 123, 456),
        capturedAt: DateTime.utc(2026, 10, 6, 8, 29, 30),
        latitude: -5.1477,
        longitude: 119.4326,
        accuracyMeters: 20,
        photoFilename: 'event-full_123.jpg',
      );

      expect(inserted.localSequence, 1);
      expect(inserted.state, AttendanceOutboxState.pending);
      expect(inserted.attemptCount, 0);
      expect(inserted.eventAt, DateTime.utc(2026, 10, 6, 8, 30, 0, 123, 456));
      expect(inserted.capturedAt, DateTime.utc(2026, 10, 6, 8, 29, 30));
      expect(inserted.syncStartedAt, isNull);

      final loaded = await store.findForOwner(
        clientEventId: 'event-full',
        ownerUserId: 7,
      );
      expect(loaded, isNotNull);
      expect(loaded!.deviceUuid, 'device-7');
      expect(loaded.photoFilename, 'event-full_123.jpg');
      expect(loaded.eventType, AttendanceEventType.checkOut);
      expect(loaded.accuracyMeters, 20);
      expect(loaded.localSequence, 1);
    },
  );

  test('re-inserting the same id for the same owner is idempotent', () async {
    final first = await insertEvent(clientEventId: 'same-id');
    final second = await insertEvent(
      clientEventId: 'same-id',
      eventAt: DateTime.utc(2026, 10, 6, 10),
      photoFilename: 'other.jpg',
    );

    expect(second.clientEventId, first.clientEventId);
    expect(second.localSequence, first.localSequence);
    expect(second.eventAt, first.eventAt);
    expect(await store.countForOwner(1), 1);
    expect(await store.referencedPhotoFilenames(), {'same-id.jpg'});

    final next = await insertEvent(clientEventId: 'next-id');
    expect(next.localSequence, 2);
  });

  test('rejects a client_event_id that belongs to another owner', () async {
    await insertEvent(clientEventId: 'owned-id');

    await expectLater(
      insertEvent(clientEventId: 'owned-id', ownerUserId: 2),
      throwsA(isA<AttendanceOutboxConflictException>()),
    );
    expect(await store.countForOwner(2), 0);

    final next = await insertEvent(clientEventId: 'owner-2-id', ownerUserId: 2);
    expect(next.localSequence, 2);
  });

  test(
    'claims in local enqueue order, not event_at or created_at order',
    () async {
      await insertEvent(
        clientEventId: 'late-enqueued-first',
        eventAt: DateTime.utc(2026, 10, 6, 17),
        createdAt: DateTime.utc(2026, 10, 6, 17),
      );
      await insertEvent(
        clientEventId: 'early-enqueued-second',
        eventAt: DateTime.utc(2026, 10, 6, 8, 0, 0, 123),
        createdAt: DateTime.utc(2026, 10, 6, 8),
      );
      await insertEvent(
        clientEventId: 'microsecond-third',
        eventAt: DateTime.utc(2026, 10, 6, 8, 0, 0, 123, 456),
        createdAt: DateTime.utc(2026, 10, 6, 8),
      );

      final listed = await store.listForOwner(1);
      expect(listed.map((event) => event.clientEventId), [
        'late-enqueued-first',
        'early-enqueued-second',
        'microsecond-third',
      ]);

      final first = await store.claimNextForEmployee(
        ownerUserId: 1,
        employeeId: 10,
        now: now,
      );
      expect(first?.clientEventId, 'late-enqueued-first');

      await store.markSynced(
        clientEventId: first!.clientEventId,
        ownerUserId: 1,
        serverEventId: 1,
        serverStatus: 'ON_TIME',
        serverReceivedAt: now,
        syncedAt: now,
      );

      final second = await store.claimNextForEmployee(
        ownerUserId: 1,
        employeeId: 10,
        now: now,
      );
      expect(second?.clientEventId, 'early-enqueued-second');
    },
  );

  test('two concurrent claims produce exactly one winner', () async {
    await insertEvent(clientEventId: 'atomic-claim');

    final claims = await Future.wait([
      store.claimNextForEmployee(ownerUserId: 1, employeeId: 10, now: now),
      store.claimNextForEmployee(ownerUserId: 1, employeeId: 10, now: now),
    ]);

    expect(claims.whereType<AttendanceOutboxEvent>(), hasLength(1));
    final claimed = claims.whereType<AttendanceOutboxEvent>().single;
    expect(claimed.state, AttendanceOutboxState.syncing);
    expect(claimed.attemptCount, 1);
    expect(claimed.syncStartedAt, now);
    expect(
      await store.countForOwner(1, states: {AttendanceOutboxState.pending}),
      0,
    );
  });

  test(
    'skips a rejected event and claims the next pending one for the same employee',
    () async {
      await insertEvent(clientEventId: 'rejected-first');
      await insertEvent(clientEventId: 'pending-second');

      final first = await store.claimNextForEmployee(
        ownerUserId: 1,
        employeeId: 10,
        now: now,
      );
      await store.markRejected(
        clientEventId: first!.clientEventId,
        ownerUserId: 1,
        errorCode: 'OUTSIDE_GEOFENCE',
        errorMessage: 'Outside the geofence.',
        now: now,
      );

      final second = await store.claimNextForEmployee(
        ownerUserId: 1,
        employeeId: 10,
        now: now,
      );
      expect(second?.clientEventId, 'pending-second');
      expect(second?.state, AttendanceOutboxState.syncing);

      final loaded = await store.findForOwner(
        clientEventId: 'pending-second',
        ownerUserId: 1,
      );
      expect(loaded!.state, AttendanceOutboxState.syncing);
    },
  );

  test(
    'recovers an expired sync lease into a retryable pending event',
    () async {
      await insertEvent(clientEventId: 'stale-claim');
      final claimed = await store.claimNextForEmployee(
        ownerUserId: 1,
        employeeId: 10,
        now: now,
      );
      expect(claimed!.attemptCount, 1);

      expect(
        await store.recoverStaleClaims(
          ownerUserId: 1,
          staleBefore: now.subtract(const Duration(seconds: 1)),
          now: now,
        ),
        0,
      );
      expect(
        await store.recoverStaleClaims(
          ownerUserId: 1,
          staleBefore: now.add(const Duration(minutes: 5)),
          now: now.add(const Duration(minutes: 6)),
        ),
        1,
      );

      final recovered = await store.findForOwner(
        clientEventId: 'stale-claim',
        ownerUserId: 1,
      );
      expect(recovered!.state, AttendanceOutboxState.pending);
      expect(recovered.syncStartedAt, isNull);
      expect(recovered.attemptCount, 1);
      expect(recovered.lastErrorCode, 'SYNC_LEASE_EXPIRED');
      expect(recovered.nextAttemptAt, now.add(const Duration(minutes: 6)));

      final reclaimed = await store.claimNextForEmployee(
        ownerUserId: 1,
        employeeId: 10,
        now: now.add(const Duration(minutes: 7)),
      );
      expect(reclaimed!.attemptCount, 2);
    },
  );

  test('state transitions are owner and employee scoped', () async {
    await insertEvent(clientEventId: 'scoped-id');
    await store.claimNextForEmployee(ownerUserId: 1, employeeId: 10, now: now);

    await expectLater(
      store.markSynced(
        clientEventId: 'scoped-id',
        ownerUserId: 2,
        serverEventId: 1,
        serverStatus: 'ON_TIME',
        serverReceivedAt: now,
        syncedAt: now,
      ),
      throwsA(isA<AttendanceOutboxTransitionException>()),
    );
    await expectLater(
      store.markSynced(
        clientEventId: 'scoped-id',
        ownerUserId: 1,
        employeeId: 99,
        serverEventId: 1,
        serverStatus: 'ON_TIME',
        serverReceivedAt: now,
        syncedAt: now,
      ),
      throwsA(isA<AttendanceOutboxTransitionException>()),
    );

    final stillSyncing = await store.findForOwner(
      clientEventId: 'scoped-id',
      ownerUserId: 1,
    );
    expect(stillSyncing!.state, AttendanceOutboxState.syncing);

    final synced = await store.markSynced(
      clientEventId: 'scoped-id',
      ownerUserId: 1,
      employeeId: 10,
      serverEventId: 55,
      serverStatus: 'ON_TIME',
      serverReceivedAt: now,
      syncedAt: now.add(const Duration(seconds: 1)),
    );
    expect(synced.state, AttendanceOutboxState.synced);
    expect(synced.serverEventId, 55);
    expect(synced.serverStatus, 'ON_TIME');
    expect(synced.serverReceivedAt, now);
    expect(synced.syncedAt, now.add(const Duration(seconds: 1)));
    expect(synced.syncStartedAt, isNull);
    expect(synced.nextAttemptAt, isNull);
  });

  test(
    'claim, release, recover, and reject honor owner and employee scope',
    () async {
      await insertEvent(clientEventId: 'claim-scope');

      expect(
        await store.claimNextForEmployee(
          ownerUserId: 2,
          employeeId: 10,
          now: now,
        ),
        isNull,
      );
      expect(
        await store.claimNextForEmployee(
          ownerUserId: 1,
          employeeId: 20,
          now: now,
        ),
        isNull,
      );

      final claimed = await store.claimNextForEmployee(
        ownerUserId: 1,
        employeeId: 10,
        now: now,
      );
      expect(claimed!.clientEventId, 'claim-scope');

      expect(
        await store.recoverStaleClaims(
          ownerUserId: 2,
          staleBefore: now.add(const Duration(hours: 1)),
          now: now,
        ),
        0,
      );
      await expectLater(
        store.releaseForRetry(
          clientEventId: 'claim-scope',
          ownerUserId: 2,
          errorCode: 'NETWORK_ERROR',
          errorMessage: 'offline',
          nextAttemptAt: now,
          now: now,
        ),
        throwsA(isA<AttendanceOutboxTransitionException>()),
      );
      await expectLater(
        store.releaseForRetry(
          clientEventId: 'claim-scope',
          ownerUserId: 1,
          employeeId: 20,
          errorCode: 'NETWORK_ERROR',
          errorMessage: 'offline',
          nextAttemptAt: now,
          now: now,
        ),
        throwsA(isA<AttendanceOutboxTransitionException>()),
      );

      await store.releaseForRetry(
        clientEventId: 'claim-scope',
        ownerUserId: 1,
        employeeId: 10,
        errorCode: 'NETWORK_ERROR',
        errorMessage: 'offline',
        nextAttemptAt: now,
        now: now,
      );
      await store.claimNextForEmployee(
        ownerUserId: 1,
        employeeId: 10,
        now: now.add(const Duration(minutes: 1)),
      );

      await expectLater(
        store.markRejected(
          clientEventId: 'claim-scope',
          ownerUserId: 2,
          errorCode: 'OUTSIDE_GEOFENCE',
          errorMessage: 'outside',
          now: now,
        ),
        throwsA(isA<AttendanceOutboxTransitionException>()),
      );
      await expectLater(
        store.markRejected(
          clientEventId: 'claim-scope',
          ownerUserId: 1,
          employeeId: 20,
          errorCode: 'OUTSIDE_GEOFENCE',
          errorMessage: 'outside',
          now: now,
        ),
        throwsA(isA<AttendanceOutboxTransitionException>()),
      );

      final rejected = await store.markRejected(
        clientEventId: 'claim-scope',
        ownerUserId: 1,
        employeeId: 10,
        errorCode: 'OUTSIDE_GEOFENCE',
        errorMessage: 'outside',
        now: now,
      );
      expect(rejected.state, AttendanceOutboxState.rejected);
    },
  );

  test('rejects transitions from the wrong state', () async {
    await insertEvent(clientEventId: 'invalid-transition');

    await expectLater(
      store.markSynced(
        clientEventId: 'invalid-transition',
        ownerUserId: 1,
        serverEventId: 1,
        serverStatus: 'ON_TIME',
        serverReceivedAt: now,
        syncedAt: now,
      ),
      throwsA(isA<AttendanceOutboxTransitionException>()),
    );
    await expectLater(
      store.releaseForRetry(
        clientEventId: 'invalid-transition',
        ownerUserId: 1,
        errorCode: 'NETWORK_ERROR',
        errorMessage: 'offline',
        nextAttemptAt: now,
        now: now,
      ),
      throwsA(isA<AttendanceOutboxTransitionException>()),
    );
    await expectLater(
      store.markRejected(
        clientEventId: 'invalid-transition',
        ownerUserId: 1,
        errorCode: 'OUTSIDE_GEOFENCE',
        errorMessage: 'outside',
        now: now,
      ),
      throwsA(isA<AttendanceOutboxTransitionException>()),
    );

    await store.claimNextForEmployee(ownerUserId: 1, employeeId: 10, now: now);
    await store.markSynced(
      clientEventId: 'invalid-transition',
      ownerUserId: 1,
      serverEventId: 1,
      serverStatus: 'ON_TIME',
      serverReceivedAt: now,
      syncedAt: now,
    );
    await expectLater(
      store.releaseForRetry(
        clientEventId: 'invalid-transition',
        ownerUserId: 1,
        errorCode: 'NETWORK_ERROR',
        errorMessage: 'offline',
        nextAttemptAt: now,
        now: now,
      ),
      throwsA(isA<AttendanceOutboxTransitionException>()),
    );
    await expectLater(
      store.markRejected(
        clientEventId: 'invalid-transition',
        ownerUserId: 1,
        errorCode: 'OUTSIDE_GEOFENCE',
        errorMessage: 'outside',
        now: now,
      ),
      throwsA(isA<AttendanceOutboxTransitionException>()),
    );
  });

  test('releaseForRetry increments attempt_count exactly once', () async {
    await insertEvent(clientEventId: 'retry-id');
    await store.claimNextForEmployee(ownerUserId: 1, employeeId: 10, now: now);

    Future<bool> tryRelease() async {
      try {
        await store.releaseForRetry(
          clientEventId: 'retry-id',
          ownerUserId: 1,
          errorCode: 'NETWORK_ERROR',
          errorMessage: 'offline',
          nextAttemptAt: now.add(const Duration(minutes: 1)),
          now: now,
        );
        return true;
      } on AttendanceOutboxTransitionException {
        return false;
      }
    }

    final results = await Future.wait([tryRelease(), tryRelease()]);
    expect(results.where((result) => result), hasLength(1));

    final released = await store.findForOwner(
      clientEventId: 'retry-id',
      ownerUserId: 1,
    );
    expect(released!.state, AttendanceOutboxState.pending);
    expect(released.attemptCount, 2);
    expect(released.syncStartedAt, isNull);
    expect(released.nextAttemptAt, now.add(const Duration(minutes: 1)));

    final reclaimed = await store.claimNextForEmployee(
      ownerUserId: 1,
      employeeId: 10,
      now: now.add(const Duration(minutes: 2)),
    );
    expect(reclaimed!.attemptCount, 3);
  });

  test('purges only acknowledged events for the requested owner', () async {
    await insertEvent(
      clientEventId: 'old-synced',
      photoFilename: 'old-synced.jpg',
      createdAt: DateTime.utc(2026, 9, 30),
    );
    final oldSynced = await store.claimNextForEmployee(
      ownerUserId: 1,
      employeeId: 10,
      now: now,
    );
    await store.markSynced(
      clientEventId: oldSynced!.clientEventId,
      ownerUserId: 1,
      serverEventId: 501,
      serverStatus: 'ON_TIME',
      serverReceivedAt: DateTime.utc(2026, 9, 30, 8),
      syncedAt: DateTime.utc(2026, 9, 30, 9),
    );

    await insertEvent(clientEventId: 'rejected-row');
    final rejected = await store.claimNextForEmployee(
      ownerUserId: 1,
      employeeId: 10,
      now: now,
    );
    await store.markRejected(
      clientEventId: rejected!.clientEventId,
      ownerUserId: 1,
      errorCode: 'OUTSIDE_GEOFENCE',
      errorMessage: 'outside',
      now: now,
    );

    await insertEvent(clientEventId: 'still-pending');
    await insertEvent(clientEventId: 'other-owner-synced', ownerUserId: 2);
    final otherClaim = await store.claimNextForEmployee(
      ownerUserId: 2,
      employeeId: 10,
      now: now,
    );
    await store.markSynced(
      clientEventId: otherClaim!.clientEventId,
      ownerUserId: 2,
      serverEventId: 777,
      serverStatus: 'ON_TIME',
      serverReceivedAt: DateTime.utc(2026, 9, 30, 8),
      syncedAt: DateTime.utc(2026, 9, 30, 9),
    );

    final purged = await store.purgeAcknowledgedBefore(
      ownerUserId: 1,
      cutoff: DateTime.utc(2026, 10, 1),
    );
    expect(purged.deletedRows, 1);
    expect(purged.photoFilenames, {'old-synced.jpg'});

    final remaining = await store.listForOwner(1);
    expect(remaining.map((event) => event.clientEventId), [
      'rejected-row',
      'still-pending',
    ]);
    expect(await store.countForOwner(2), 1);
    final emptyPurge = await store.purgeAcknowledgedBefore(
      ownerUserId: 1,
      cutoff: DateTime.utc(2026, 9, 30, 8, 59),
    );
    expect(emptyPurge.deletedRows, 0);
  });

  test('tracks referenced photo filenames', () async {
    await insertEvent(clientEventId: 'photo-a', photoFilename: 'shared.jpg');
    await insertEvent(clientEventId: 'photo-b', photoFilename: 'shared.jpg');

    expect(await store.referencedPhotoFilenames(), {'shared.jpg'});
    expect(await store.isPhotoReferenced('shared.jpg'), isTrue);
    expect(await store.isPhotoReferenced('missing.jpg'), isFalse);
  });

  test('rejects unsafe ids, filenames, and non-finite coordinates', () async {
    await expectLater(
      insertEvent(clientEventId: '../bad'),
      throwsArgumentError,
    );
    await expectLater(
      insertEvent(clientEventId: 'bad-photo', photoFilename: '../escape.jpg'),
      throwsArgumentError,
    );
    await expectLater(
      insertEvent(clientEventId: 'tmp-photo', photoFilename: 'photo.jpg.tmp'),
      throwsArgumentError,
    );
    await expectLater(
      insertEvent(clientEventId: 'nested-photo', photoFilename: 'nested/a.jpg'),
      throwsArgumentError,
    );
    await expectLater(
      insertEvent(clientEventId: 'nan-lat', latitude: double.nan),
      throwsArgumentError,
    );
    await expectLater(
      insertEvent(clientEventId: 'inf-lon', longitude: double.infinity),
      throwsArgumentError,
    );
    await expectLater(
      insertEvent(clientEventId: 'nan-acc', accuracyMeters: double.nan),
      throwsArgumentError,
    );
    expect(await store.countForOwner(1), 0);
  });

  test('persists local sequence across a database reopen', () async {
    await insertEvent(clientEventId: 'before-reopen-1');
    await insertEvent(clientEventId: 'before-reopen-2');

    await database.close();
    database = AttendanceOutboxDatabase(
      factory: databaseFactoryFfiNoIsolate,
      pathProvider: () async => databasePathIn(temp),
    );
    store = SqliteAttendanceOutboxStore(database);

    final listed = await store.listForOwner(1);
    expect(listed.map((event) => event.localSequence), [1, 2]);

    final next = await insertEvent(clientEventId: 'after-reopen');
    expect(next.localSequence, 3);
  });
}
