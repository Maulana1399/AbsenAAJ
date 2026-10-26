import 'dart:io';

import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_database.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_exceptions.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_repository.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_store.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_photo_storage.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_outbox_event.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'sqlite_test_support.dart';

void main() {
  late Directory temp;
  late Directory photoDirectory;
  late AttendanceOutboxDatabase database;
  late SqliteAttendanceOutboxStore store;
  late FileAttendancePhotoStorage photoStorage;
  late AttendanceOutboxRepository repository;

  setUpAll(configureSqliteForTests);

  setUp(() async {
    temp = await createTempDirectory();
    photoDirectory = Directory(p.join(temp.path, 'photos'));
    database = AttendanceOutboxDatabase(
      factory: databaseFactoryFfiNoIsolate,
      pathProvider: () async => databasePathIn(temp),
    );
    store = SqliteAttendanceOutboxStore(database);
    photoStorage = FileAttendancePhotoStorage(
      directoryProvider: () async => photoDirectory,
      staleAfter: const Duration(hours: 1),
    );
    repository = AttendanceOutboxRepository(
      store,
      photoStorage,
      clock: () => DateTime.utc(2026, 10, 6, 8, 30, 15),
    );
  });

  tearDown(() async {
    await database.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  Future<AttendanceOutboxEvent> enqueue({
    String clientEventId = 'event-1',
    int ownerUserId = 1,
    int employeeId = 10,
    String deviceUuid = 'device-1',
    AttendanceEventType eventType = AttendanceEventType.checkIn,
    DateTime? eventAt,
    DateTime? capturedAt,
    GpsReading gps = const GpsReading(
      latitude: -5.1477,
      longitude: 119.4326,
      accuracyMeters: 20,
    ),
    List<int>? photoBytes,
  }) {
    return repository.enqueue(
      clientEventId: clientEventId,
      ownerUserId: ownerUserId,
      employeeId: employeeId,
      deviceUuid: deviceUuid,
      eventType: eventType,
      eventAt: eventAt ?? DateTime.utc(2026, 10, 6, 8, 30),
      capturedAt: capturedAt ?? DateTime.utc(2026, 10, 6, 8, 29, 30),
      gps: gps,
      photoBytes: photoBytes ?? validJpegBytes,
    );
  }

  test('enqueue writes the photo and a durable pending event', () async {
    final queued = await enqueue(
      clientEventId: 'caller-supplied-id',
      gps: const GpsReading(
        latitude: -5.1477,
        longitude: 119.4326,
        accuracyMeters: 18.5,
      ),
    );

    expect(queued.clientEventId, 'caller-supplied-id');
    expect(queued.state, AttendanceOutboxState.pending);
    expect(queued.localSequence, 1);
    expect(queued.createdAt, DateTime.utc(2026, 10, 6, 8, 30, 15));
    expect(queued.updatedAt, queued.createdAt);
    expect(queued.photoFilename, isNot(contains('/')));
    expect(await photoStorage.read(queued.photoFilename), validJpegBytes);

    final persisted = await store.findForOwner(
      clientEventId: 'caller-supplied-id',
      ownerUserId: 1,
    );
    expect(persisted, isNotNull);
    expect(persisted!.ownerUserId, 1);
    expect(persisted.photoFilename, queued.photoFilename);
    expect(persisted.attemptCount, 0);
    expect(persisted.serverStatus, isNull);
  });

  test('re-enqueue with the same id returns the existing event', () async {
    final first = await enqueue(clientEventId: 'idempotent-id');
    final second = await enqueue(
      clientEventId: 'idempotent-id',
      eventAt: DateTime.utc(2026, 10, 6, 8, 31),
      capturedAt: DateTime.utc(2026, 10, 6, 8, 30),
      photoBytes: [2, 3, 4],
    );

    expect(second.clientEventId, first.clientEventId);
    expect(second.photoFilename, first.photoFilename);
    expect(second.eventAt, DateTime.utc(2026, 10, 6, 8, 30));
    expect(await store.countForOwner(1), 1);
    expect(await store.referencedPhotoFilenames(), {first.photoFilename});
    expect(await photoStorage.read(first.photoFilename), validJpegBytes);
  });

  test('does not reuse a client_event_id across different users', () async {
    await enqueue(clientEventId: 'owned-id');

    await expectLater(
      enqueue(
        clientEventId: 'owned-id',
        ownerUserId: 2,
        employeeId: 20,
        deviceUuid: 'device-2',
        photoBytes: validJpegBytes,
      ),
      throwsA(isA<AttendanceOutboxConflictException>()),
    );
    expect(await store.countForOwner(2), 0);
    expect(
      (await photoDirectory.list().toList()).whereType<File>(),
      hasLength(1),
    );
  });

  test('normalizes event and capture times to UTC', () async {
    final queued = await enqueue(
      clientEventId: 'utc-id',
      eventAt: DateTime.parse('2026-10-06T15:30:00+07:00'),
      capturedAt: DateTime.parse('2026-10-06T15:29:30+07:00'),
    );

    expect(queued.eventAt, DateTime.utc(2026, 10, 6, 8, 30));
    expect(queued.capturedAt, DateTime.utc(2026, 10, 6, 8, 29, 30));
    expect(queued.eventAt.isUtc, isTrue);
    expect(queued.capturedAt.isUtc, isTrue);
  });

  test('queued events survive a database reopen', () async {
    final queued = await enqueue(clientEventId: 'reopen-id');

    await database.close();
    database = AttendanceOutboxDatabase(
      factory: databaseFactoryFfiNoIsolate,
      pathProvider: () async => databasePathIn(temp),
    );
    store = SqliteAttendanceOutboxStore(database);

    final loaded = await store.findForOwner(
      clientEventId: 'reopen-id',
      ownerUserId: 1,
    );
    expect(loaded, isNotNull);
    expect(loaded!.photoFilename, queued.photoFilename);
    expect(await photoStorage.read(loaded.photoFilename), validJpegBytes);
  });

  test('cleanup keeps referenced photos and removes stale orphans', () async {
    final queued = await enqueue(clientEventId: 'referenced-id');

    final referenced = await photoStorage.resolve(queued.photoFilename);
    await referenced.setLastModified(
      DateTime.now().subtract(const Duration(hours: 2)),
    );

    final orphan = File(p.join(photoDirectory.path, 'orphan.jpg'));
    await orphan.writeAsBytes([2]);
    await orphan.setLastModified(
      DateTime.now().subtract(const Duration(hours: 2)),
    );

    final tempFile = File(p.join(photoDirectory.path, '.crashed.jpg.tmp'));
    await tempFile.writeAsBytes([3]);
    await tempFile.setLastModified(
      DateTime.now().subtract(const Duration(hours: 2)),
    );

    await repository.cleanupOrphans();

    expect(await referenced.exists(), isTrue);
    expect(await orphan.exists(), isFalse);
    expect(await tempFile.exists(), isFalse);
  });

  test(
    'purge deletes photos only after their last queue row is gone',
    () async {
      final shared = await photoStorage.writeJpeg(
        clientEventId: 'shared',
        bytes: validJpegBytes,
      );
      final unique = await photoStorage.writeJpeg(
        clientEventId: 'unique',
        bytes: validJpegBytes,
      );

      await store.insertPending(
        AttendanceOutboxEvent.pending(
          clientEventId: 'shared-synced',
          ownerUserId: 1,
          employeeId: 10,
          deviceUuid: 'device-1',
          eventType: AttendanceEventType.checkIn,
          eventAt: DateTime.utc(2026, 9, 30, 8),
          capturedAt: DateTime.utc(2026, 9, 30, 7, 59),
          latitude: -5.1477,
          longitude: 119.4326,
          accuracyMeters: 20,
          photoFilename: shared,
          createdAt: DateTime.utc(2026, 9, 30, 8),
        ),
      );
      await store.insertPending(
        AttendanceOutboxEvent.pending(
          clientEventId: 'shared-pending',
          ownerUserId: 1,
          employeeId: 10,
          deviceUuid: 'device-1',
          eventType: AttendanceEventType.checkOut,
          eventAt: DateTime.utc(2026, 9, 30, 17),
          capturedAt: DateTime.utc(2026, 9, 30, 16, 59),
          latitude: -5.1477,
          longitude: 119.4326,
          accuracyMeters: 20,
          photoFilename: shared,
          createdAt: DateTime.utc(2026, 9, 30, 17),
        ),
      );
      await store.insertPending(
        AttendanceOutboxEvent.pending(
          clientEventId: 'unique-synced',
          ownerUserId: 1,
          employeeId: 11,
          deviceUuid: 'device-1',
          eventType: AttendanceEventType.checkIn,
          eventAt: DateTime.utc(2026, 9, 30, 8),
          capturedAt: DateTime.utc(2026, 9, 30, 7, 59),
          latitude: -5.1477,
          longitude: 119.4326,
          accuracyMeters: 20,
          photoFilename: unique,
          createdAt: DateTime.utc(2026, 9, 30, 8),
        ),
      );

      final first = await store.claimNextForEmployee(
        ownerUserId: 1,
        employeeId: 10,
        now: DateTime.utc(2026, 9, 30, 9),
      );
      await store.markSynced(
        clientEventId: first!.clientEventId,
        ownerUserId: 1,
        serverEventId: 1,
        serverStatus: 'ON_TIME',
        serverReceivedAt: DateTime.utc(2026, 9, 30, 9),
        syncedAt: DateTime.utc(2026, 9, 30, 9),
      );

      final second = await store.claimNextForEmployee(
        ownerUserId: 1,
        employeeId: 11,
        now: DateTime.utc(2026, 9, 30, 9),
      );
      await store.markSynced(
        clientEventId: second!.clientEventId,
        ownerUserId: 1,
        serverEventId: 2,
        serverStatus: 'ON_TIME',
        serverReceivedAt: DateTime.utc(2026, 9, 30, 9),
        syncedAt: DateTime.utc(2026, 9, 30, 9),
      );

      final purged = await repository.purgeAcknowledgedBefore(
        ownerUserId: 1,
        cutoff: DateTime.utc(2026, 10, 1),
      );

      expect(purged.deletedRows, 2);
      expect(await photoStorage.exists(shared), isTrue);
      expect(await photoStorage.exists(unique), isFalse);
      expect(
        await store.findForOwner(
          clientEventId: 'shared-pending',
          ownerUserId: 1,
        ),
        isNotNull,
      );
    },
  );

  test(
    'rejects unsupported or oversized photos before writing a row',
    () async {
      await expectLater(
        enqueue(clientEventId: 'bad-format', photoBytes: [1, 2, 3, 4]),
        throwsArgumentError,
      );
      await expectLater(
        enqueue(
          clientEventId: 'too-large',
          photoBytes: [0xFF, 0xD8, 0xFF, ...List.filled(5120 * 1024, 0)],
        ),
        throwsArgumentError,
      );
      expect(await store.countForOwner(1), 0);
      expect(
        await photoDirectory.exists()
            ? await photoDirectory.list().toList()
            : [],
        isEmpty,
      );
    },
  );

  test('rejects non-finite GPS before writing a photo or row', () async {
    await expectLater(
      enqueue(
        clientEventId: 'bad-gps',
        gps: const GpsReading(
          latitude: double.nan,
          longitude: 119.4,
          accuracyMeters: 20,
        ),
      ),
      throwsArgumentError,
    );
    expect(await store.countForOwner(1), 0);
  });

  test(
    'deletes a newly written photo when the database insert fails',
    () async {
      final failingRepository = AttendanceOutboxRepository(
        _FailingStore(database),
        photoStorage,
      );

      await expectLater(
        () => failingRepository.enqueue(
          clientEventId: 'insert-fails',
          ownerUserId: 1,
          employeeId: 10,
          deviceUuid: 'device-1',
          eventType: AttendanceEventType.checkIn,
          eventAt: DateTime.utc(2026, 10, 6, 8, 30),
          capturedAt: DateTime.utc(2026, 10, 6, 8, 29, 30),
          gps: const GpsReading(
            latitude: -5.1477,
            longitude: 119.4326,
            accuracyMeters: 20,
          ),
          photoBytes: validJpegBytes,
        ),
        throwsA(isA<StateError>()),
      );

      if (await photoDirectory.exists()) {
        expect(await photoDirectory.list().toList(), isEmpty);
      }
    },
  );
}

class _FailingStore extends SqliteAttendanceOutboxStore {
  _FailingStore(super.database);

  @override
  Future<OutboxInsertResult> insertPending(AttendanceOutboxEvent event) async {
    throw StateError('database unavailable');
  }
}
