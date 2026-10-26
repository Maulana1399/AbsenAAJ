import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const validJpegBytes = <int>[
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  0x4A,
  0x46,
  0x49,
  0x46,
  0x00,
  0x01,
  0xFF,
  0xD9,
];

void configureSqliteForTests() {
  sqfliteFfiInit();
  final library = Platform.environment['SQLITE3_LIBRARY'];
  if (library != null && library.isNotEmpty) {
    open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open(library));
  }
}

Future<Directory> createTempDirectory() =>
    Directory.systemTemp.createTemp('absen_aaj_outbox_test_');

String databasePathIn(Directory directory) =>
    p.join(directory.path, 'attendance_outbox.db');

Future<void> createVersionOneOutboxSchema(Database db) async {
  await db.execute('''
    CREATE TABLE attendance_outbox (
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
      state TEXT NOT NULL DEFAULT 'pending'
        CHECK (state IN ('pending', 'syncing', 'synced', 'rejected')),
      attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
      next_attempt_at TEXT,
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
  await db.execute('''
    CREATE INDEX idx_attendance_outbox_owner_state_event
    ON attendance_outbox (owner_user_id, state, event_at, created_at)
  ''');
  await db.execute('''
    CREATE INDEX idx_attendance_outbox_employee_state
    ON attendance_outbox (employee_id, state, event_at, created_at)
  ''');
  await db.execute('''
    CREATE INDEX idx_attendance_outbox_next_attempt
    ON attendance_outbox (state, next_attempt_at)
  ''');
}
