import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/attendance_outbox_time.dart';

class AttendanceOutboxDatabase {
  AttendanceOutboxDatabase({
    required this._factory,
    required this._pathProvider,
  });

  static const databaseFileName = 'attendance_outbox.db';
  static const tableName = 'attendance_outbox';
  static const sequenceTableName = 'attendance_outbox_sequence';
  static const schemaVersion = 2;

  final DatabaseFactory _factory;
  final Future<String> Function() _pathProvider;

  Future<Database>? _openFuture;

  Future<Database> get database => _openFuture ??= _open();

  Future<Database> _open() async {
    final path = await _pathProvider();
    try {
      return await _factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
          onDowngrade: _onDowngrade,
        ),
      );
    } catch (_) {
      _openFuture = null;
      rethrow;
    }
  }

  Future<void> close() async {
    final open = _openFuture;
    _openFuture = null;
    if (open == null) return;
    final db = await open;
    await db.close();
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createV2Table(db, tableName);
    await _createIndexes(db);
    await _createSequenceTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    var version = oldVersion;
    if (version < 2) {
      await _migrateV1ToV2(db);
      version = 2;
    }
    if (version != newVersion) {
      throw StateError(
        'Unsupported outbox schema upgrade from $oldVersion to $newVersion.',
      );
    }
  }

  Future<void> _onDowngrade(Database db, int oldVersion, int newVersion) {
    throw StateError(
      'Outbox schema downgrade from $oldVersion to $newVersion is not supported.',
    );
  }

  Future<void> _migrateV1ToV2(Database db) async {
    await db.execute(
      'DROP INDEX IF EXISTS idx_attendance_outbox_owner_state_event',
    );
    await db.execute(
      'DROP INDEX IF EXISTS idx_attendance_outbox_employee_state',
    );
    await db.execute('DROP INDEX IF EXISTS idx_attendance_outbox_next_attempt');
    await db.execute('ALTER TABLE $tableName RENAME TO attendance_outbox_v1');
    await _createV2Table(db, tableName);

    final rows = await db.query('attendance_outbox_v1', orderBy: 'rowid ASC');
    var localSequence = 1;
    for (final row in rows) {
      await db.insert(
        tableName,
        _v2RowFromV1(row, localSequence),
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      localSequence++;
    }

    await db.execute('DROP TABLE attendance_outbox_v1');
    await _createIndexes(db);
    await _createSequenceTable(db, nextValue: localSequence);
  }

  Map<String, Object?> _v2RowFromV1(
    Map<String, Object?> row,
    int localSequence,
  ) {
    return {
      'client_event_id': row['client_event_id'],
      'owner_user_id': row['owner_user_id'],
      'employee_id': row['employee_id'],
      'device_uuid': row['device_uuid'],
      'event_type': row['event_type'],
      'event_at': _normalizeTimestamp(row['event_at']),
      'captured_at': _normalizeTimestamp(row['captured_at']),
      'latitude': row['latitude'],
      'longitude': row['longitude'],
      'accuracy_meters': row['accuracy_meters'],
      'photo_filename': row['photo_filename'],
      'local_sequence': localSequence,
      'state': row['state'],
      'attempt_count': row['attempt_count'],
      'next_attempt_at': _normalizeNullableTimestamp(row['next_attempt_at']),
      'sync_started_at': null,
      'last_error_code': row['last_error_code'],
      'last_error_message': row['last_error_message'],
      'server_event_id': row['server_event_id'],
      'server_status': row['server_status'],
      'server_received_at': _normalizeNullableTimestamp(
        row['server_received_at'],
      ),
      'created_at': _normalizeTimestamp(row['created_at']),
      'updated_at': _normalizeTimestamp(row['updated_at']),
      'synced_at': _normalizeNullableTimestamp(row['synced_at']),
    };
  }

  String _normalizeTimestamp(Object? value) {
    return formatOutboxTimestamp(DateTime.parse(value as String));
  }

  String? _normalizeNullableTimestamp(Object? value) {
    if (value == null) return null;
    return _normalizeTimestamp(value);
  }

  Future<void> _createV2Table(Database db, String name) async {
    await db.execute('''
      CREATE TABLE $name (
        client_event_id TEXT PRIMARY KEY NOT NULL
          CHECK (length(client_event_id) BETWEEN 1 AND 100),
        owner_user_id INTEGER NOT NULL CHECK (owner_user_id > 0),
        employee_id INTEGER NOT NULL CHECK (employee_id > 0),
        device_uuid TEXT NOT NULL CHECK (length(device_uuid) > 0),
        event_type TEXT NOT NULL CHECK (event_type IN ('CHECK_IN', 'CHECK_OUT')),
        event_at TEXT NOT NULL,
        captured_at TEXT NOT NULL,
        latitude REAL NOT NULL CHECK (latitude BETWEEN -90 AND 90),
        longitude REAL NOT NULL CHECK (longitude BETWEEN -180 AND 180),
        accuracy_meters REAL NOT NULL CHECK (accuracy_meters >= 0),
        photo_filename TEXT NOT NULL CHECK (length(photo_filename) > 0),
        local_sequence INTEGER NOT NULL UNIQUE CHECK (local_sequence > 0),
        state TEXT NOT NULL DEFAULT 'pending'
          CHECK (state IN ('pending', 'syncing', 'synced', 'rejected')),
        attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
        next_attempt_at TEXT,
        sync_started_at TEXT,
        last_error_code TEXT,
        last_error_message TEXT,
        server_event_id INTEGER,
        server_status TEXT,
        server_received_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT
      )
    ''');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX idx_attendance_outbox_owner_state_event
      ON $tableName (owner_user_id, state, local_sequence)
    ''');

    await db.execute('''
      CREATE INDEX idx_attendance_outbox_employee_state
      ON $tableName (employee_id, state, local_sequence)
    ''');

    await db.execute('''
      CREATE INDEX idx_attendance_outbox_next_attempt
      ON $tableName (state, next_attempt_at, local_sequence)
    ''');
  }

  Future<void> _createSequenceTable(Database db, {int nextValue = 1}) async {
    await db.execute('''
      CREATE TABLE $sequenceTableName (
        id INTEGER PRIMARY KEY NOT NULL CHECK (id = 1),
        next_value INTEGER NOT NULL CHECK (next_value > 0)
      )
    ''');
    await db.insert(sequenceTableName, {'id': 1, 'next_value': nextValue});
  }
}
