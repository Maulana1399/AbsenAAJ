import 'dart:io';

import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_database.dart';
import 'package:absen_aaj/features/attendance/data/local/attendance_outbox_store.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_outbox_event.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

import 'sqlite_test_support.dart';

void main() {
  late Directory temp;
  late AttendanceOutboxDatabase database;

  setUpAll(configureSqliteForTests);

  setUp(() async {
    temp = await createTempDirectory();
    database = AttendanceOutboxDatabase(
      factory: databaseFactoryFfiNoIsolate,
      pathProvider: () async => databasePathIn(temp),
    );
  });

  tearDown(() async {
    await database.close();
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('creates the outbox schema at version 2', () async {
    final db = await database.database;

    final version = await db.rawQuery('PRAGMA user_version');
    expect(version.first['user_version'], 2);

    final columns = await db.rawQuery(
      'PRAGMA table_info(${AttendanceOutboxDatabase.tableName})',
    );
    final names = columns.map((column) => column['name'] as String).toSet();

    expect(
      names,
      containsAll({
        'client_event_id',
        'owner_user_id',
        'employee_id',
        'device_uuid',
        'event_type',
        'event_at',
        'captured_at',
        'latitude',
        'longitude',
        'accuracy_meters',
        'photo_filename',
        'local_sequence',
        'state',
        'attempt_count',
        'next_attempt_at',
        'sync_started_at',
        'last_error_code',
        'last_error_message',
        'server_event_id',
        'server_status',
        'server_received_at',
        'created_at',
        'updated_at',
        'synced_at',
      }),
    );

    final primaryKey = columns
        .where((column) => (column['pk'] as int) > 0)
        .map((column) => column['name'])
        .toList();
    expect(primaryKey, ['client_event_id']);

    final sequence = await db.query(AttendanceOutboxDatabase.sequenceTableName);
    expect(sequence, hasLength(1));
    expect(sequence.single['next_value'], 1);
  });

  test('check constraint rejects an unknown outbox state', () async {
    final db = await database.database;

    expect(
      () => db.insert(AttendanceOutboxDatabase.tableName, {
        'client_event_id': 'bad-state',
        'owner_user_id': 1,
        'employee_id': 1,
        'device_uuid': 'device-1',
        'event_type': 'CHECK_IN',
        'event_at': '2026-10-06T00:00:00.000000Z',
        'captured_at': '2026-10-06T00:00:00.000000Z',
        'latitude': 1.0,
        'longitude': 1.0,
        'accuracy_meters': 10.0,
        'photo_filename': 'bad-state.jpg',
        'local_sequence': 1,
        'state': 'unknown',
        'created_at': '2026-10-06T00:00:00.000000Z',
        'updated_at': '2026-10-06T00:00:00.000000Z',
      }),
      throwsA(isA<DatabaseException>()),
    );
  });

  test('migrates version 1 rows without losing data or ordering', () async {
    final path = databasePathIn(temp);
    final old = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) => createVersionOneOutboxSchema(db),
      ),
    );

    await old.insert('attendance_outbox', {
      'client_event_id': 'old-1',
      'owner_user_id': 1,
      'employee_id': 10,
      'device_uuid': 'device-1',
      'event_type': 'CHECK_IN',
      'event_at': '2026-10-06T08:00:00.1Z',
      'captured_at': '2026-10-06T07:59:30Z',
      'latitude': -5.1477,
      'longitude': 119.4326,
      'accuracy_meters': 12.5,
      'photo_filename': 'old-1.jpg',
      'state': 'synced',
      'attempt_count': 2,
      'last_error_code': 'NETWORK_ERROR',
      'last_error_message': 'retry',
      'server_event_id': 501,
      'server_status': 'ON_TIME',
      'server_received_at': '2026-10-06T08:00:02Z',
      'created_at': '2026-10-06T08:00:01Z',
      'updated_at': '2026-10-06T08:00:03Z',
      'synced_at': '2026-10-06T08:00:03Z',
    });
    await old.insert('attendance_outbox', {
      'client_event_id': 'old-2',
      'owner_user_id': 1,
      'employee_id': 10,
      'device_uuid': 'device-1',
      'event_type': 'CHECK_OUT',
      'event_at': '2026-10-06T08:00:00.123456Z',
      'captured_at': '2026-10-06T07:59:30Z',
      'latitude': -5.1477,
      'longitude': 119.4326,
      'accuracy_meters': 12.5,
      'photo_filename': 'old-2.jpg',
      'state': 'pending',
      'attempt_count': 0,
      'created_at': '2026-10-06T08:00:01Z',
      'updated_at': '2026-10-06T08:00:01Z',
    });
    await old.insert('attendance_outbox', {
      'client_event_id': 'old-3',
      'owner_user_id': 2,
      'employee_id': 20,
      'device_uuid': 'device-2',
      'event_type': 'CHECK_IN',
      'event_at': '2026-10-05T08:00:00Z',
      'captured_at': '2026-10-05T07:59:30Z',
      'latitude': -5.1,
      'longitude': 119.4,
      'accuracy_meters': 20.0,
      'photo_filename': 'old-3.jpg',
      'state': 'rejected',
      'attempt_count': 1,
      'last_error_code': 'OUTSIDE_GEOFENCE',
      'last_error_message': 'outside',
      'created_at': '2026-10-05T08:00:01Z',
      'updated_at': '2026-10-05T08:00:02Z',
    });
    await old.close();

    final db = await database.database;
    expect((await db.rawQuery('PRAGMA user_version')).first['user_version'], 2);

    final rows = await db.query(
      AttendanceOutboxDatabase.tableName,
      orderBy: 'local_sequence ASC',
    );
    expect(rows.map((row) => row['client_event_id']), [
      'old-1',
      'old-2',
      'old-3',
    ]);
    expect(rows.map((row) => row['local_sequence']), [1, 2, 3]);
    expect(rows[0]['event_at'], '2026-10-06T08:00:00.100000Z');
    expect(rows[1]['event_at'], '2026-10-06T08:00:00.123456Z');
    expect(rows[0]['server_event_id'], 501);
    expect(rows[0]['server_status'], 'ON_TIME');
    expect(rows[0]['synced_at'], '2026-10-06T08:00:03.000000Z');
    expect(rows[0]['last_error_code'], 'NETWORK_ERROR');
    expect(rows[2]['last_error_code'], 'OUTSIDE_GEOFENCE');

    final sequence = await db.query(AttendanceOutboxDatabase.sequenceTableName);
    expect(sequence.single['next_value'], 4);

    final store = SqliteAttendanceOutboxStore(database);
    final inserted = await store.insertPending(
      AttendanceOutboxEvent.pending(
        clientEventId: 'after-migration',
        ownerUserId: 1,
        employeeId: 10,
        deviceUuid: 'device-1',
        eventType: AttendanceEventType.checkIn,
        eventAt: DateTime.utc(2026, 10, 6, 9),
        capturedAt: DateTime.utc(2026, 10, 6, 8, 59, 30),
        latitude: -5.1477,
        longitude: 119.4326,
        accuracyMeters: 15,
        photoFilename: 'after-migration.jpg',
        createdAt: DateTime.utc(2026, 10, 6, 9, 0, 1),
      ),
    );
    expect(inserted.event.localSequence, 4);
  });
}
