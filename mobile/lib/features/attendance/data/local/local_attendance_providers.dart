import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'attendance_local_reader.dart';
import 'attendance_outbox_database.dart';
import 'attendance_outbox_repository.dart';
import 'attendance_outbox_store.dart';
import 'attendance_photo_storage.dart';

final attendanceOutboxDatabaseProvider = Provider<AttendanceOutboxDatabase>((
  ref,
) {
  final database = AttendanceOutboxDatabase(
    factory: databaseFactory,
    pathProvider: () async => p.join(
      await getDatabasesPath(),
      AttendanceOutboxDatabase.databaseFileName,
    ),
  );
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final attendanceOutboxStoreProvider = Provider<AttendanceOutboxStore>(
  (ref) =>
      SqliteAttendanceOutboxStore(ref.watch(attendanceOutboxDatabaseProvider)),
);

final attendancePhotoStorageProvider = Provider<AttendancePhotoStorage>(
  (ref) => FileAttendancePhotoStorage(
    directoryProvider: () async {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'attendance_outbox'));
    },
  ),
);

final attendanceOutboxRepositoryProvider = Provider<AttendanceOutboxRepository>(
  (ref) => AttendanceOutboxRepository(
    ref.watch(attendanceOutboxStoreProvider),
    ref.watch(attendancePhotoStorageProvider),
  ),
);

final attendanceOutboxWriterProvider = Provider<AttendanceOutboxWriter>(
  (ref) => ref.watch(attendanceOutboxRepositoryProvider),
);

final attendanceLocalReaderProvider = Provider<LocalAttendanceReader>(
  (ref) => OutboxLocalAttendanceReader(ref.watch(attendanceOutboxStoreProvider)),
);
