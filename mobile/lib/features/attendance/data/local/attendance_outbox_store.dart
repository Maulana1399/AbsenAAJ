import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/attendance_outbox_event.dart';
import 'attendance_outbox_database.dart';
import 'attendance_outbox_exceptions.dart';
import '../../domain/attendance_outbox_time.dart';
import 'attendance_photo_naming.dart';

class OutboxInsertResult {
  const OutboxInsertResult({required this.event, required this.created});

  final AttendanceOutboxEvent event;
  final bool created;
}

class OutboxPurgeResult {
  const OutboxPurgeResult({
    required this.deletedRows,
    required this.photoFilenames,
  });

  final int deletedRows;
  final Set<String> photoFilenames;
}

abstract interface class AttendanceOutboxStore {
  Future<OutboxInsertResult> insertPending(AttendanceOutboxEvent event);

  Future<AttendanceOutboxEvent?> findForOwner({
    required String clientEventId,
    required int ownerUserId,
  });

  Future<List<AttendanceOutboxEvent>> listForOwner(
    int ownerUserId, {
    Set<AttendanceOutboxState>? states,
  });

  Future<int> countForOwner(
    int ownerUserId, {
    Set<AttendanceOutboxState>? states,
  });

  Future<AttendanceOutboxEvent?> claimNextForEmployee({
    required int ownerUserId,
    required int employeeId,
    required DateTime now,
  });

  Future<int> recoverStaleClaims({
    required int ownerUserId,
    required DateTime staleBefore,
    required DateTime now,
    int? employeeId,
  });

  Future<AttendanceOutboxEvent> releaseForRetry({
    required String clientEventId,
    required int ownerUserId,
    required String errorCode,
    required String errorMessage,
    required DateTime nextAttemptAt,
    required DateTime now,
    int? employeeId,
  });

  Future<AttendanceOutboxEvent> markSynced({
    required String clientEventId,
    required int ownerUserId,
    required int serverEventId,
    required String serverStatus,
    required DateTime serverReceivedAt,
    required DateTime syncedAt,
    int? employeeId,
  });

  Future<AttendanceOutboxEvent> markRejected({
    required String clientEventId,
    required int ownerUserId,
    required String errorCode,
    required String errorMessage,
    required DateTime now,
    int? employeeId,
  });

  Future<OutboxPurgeResult> purgeAcknowledgedBefore({
    required int ownerUserId,
    required DateTime cutoff,
  });

  Future<Set<String>> referencedPhotoFilenames();

  Future<bool> isPhotoReferenced(String filename);

  Future<bool> hasQueuedPhotoReference(String filename);
}

class SqliteAttendanceOutboxStore implements AttendanceOutboxStore {
  SqliteAttendanceOutboxStore(this._database);

  final AttendanceOutboxDatabase _database;

  static const _table = AttendanceOutboxDatabase.tableName;

  @override
  Future<OutboxInsertResult> insertPending(AttendanceOutboxEvent event) async {
    _validatePending(event);
    final db = await _database.database;

    try {
      return await db.transaction((txn) async {
        final existing = await _findAnyOwner(txn, event.clientEventId);
        if (existing != null) {
          if (existing.ownerUserId != event.ownerUserId) {
            throw AttendanceOutboxConflictException(event.clientEventId);
          }
          return OutboxInsertResult(event: existing, created: false);
        }

        final localSequence = await _nextLocalSequence(txn);
        await txn.insert(
          _table,
          _pendingRow(event, localSequence),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
        final inserted = await _findAnyOwner(txn, event.clientEventId);
        if (inserted == null) {
          throw StateError('Inserted outbox row could not be read back.');
        }
        return OutboxInsertResult(event: inserted, created: true);
      });
    } on DatabaseException {
      final raced = await _findAnyOwner(
        await _database.database,
        event.clientEventId,
      );
      if (raced == null) rethrow;
      if (raced.ownerUserId != event.ownerUserId) {
        throw AttendanceOutboxConflictException(event.clientEventId);
      }
      return OutboxInsertResult(event: raced, created: false);
    }
  }

  @override
  Future<AttendanceOutboxEvent?> findForOwner({
    required String clientEventId,
    required int ownerUserId,
  }) async {
    final db = await _database.database;
    return _findForOwner(db, clientEventId, ownerUserId);
  }

  @override
  Future<List<AttendanceOutboxEvent>> listForOwner(
    int ownerUserId, {
    Set<AttendanceOutboxState>? states,
  }) async {
    final db = await _database.database;
    final where = <String>['owner_user_id = ?'];
    final args = <Object?>[ownerUserId];

    if (states != null) {
      if (states.isEmpty) return const [];
      final placeholders = List.filled(states.length, '?').join(', ');
      where.add('state IN ($placeholders)');
      args.addAll(states.map((state) => state.name));
    }

    final rows = await db.query(
      _table,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'local_sequence ASC',
    );
    return rows.map(AttendanceOutboxEvent.fromDatabase).toList(growable: false);
  }

  @override
  Future<int> countForOwner(
    int ownerUserId, {
    Set<AttendanceOutboxState>? states,
  }) async {
    final db = await _database.database;
    final where = <String>['owner_user_id = ?'];
    final args = <Object?>[ownerUserId];

    if (states != null) {
      if (states.isEmpty) return 0;
      final placeholders = List.filled(states.length, '?').join(', ');
      where.add('state IN ($placeholders)');
      args.addAll(states.map((state) => state.name));
    }

    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $_table '
      'WHERE ${where.join(' AND ')}',
      args,
    );
    return (rows.first['count'] as num).toInt();
  }

  @override
  Future<AttendanceOutboxEvent?> claimNextForEmployee({
    required int ownerUserId,
    required int employeeId,
    required DateTime now,
  }) async {
    final db = await _database.database;
    final claimedAt = formatOutboxTimestamp(now);

    return db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        where:
            'owner_user_id = ? AND employee_id = ? '
            "AND state IN ('pending', 'syncing', 'rejected')",
        whereArgs: [ownerUserId, employeeId],
        orderBy: 'local_sequence ASC',
        limit: 1,
      );
      if (rows.isEmpty) return null;

      final earliest = AttendanceOutboxEvent.fromDatabase(rows.first);

      if (earliest.state == AttendanceOutboxState.syncing) {
        return null;
      }

      if (earliest.state == AttendanceOutboxState.rejected) {
        final pendingRows = await txn.query(
          _table,
          where:
              'owner_user_id = ? AND employee_id = ? '
              "AND state = 'pending'",
          whereArgs: [ownerUserId, employeeId],
          orderBy: 'local_sequence ASC',
          limit: 1,
        );
        if (pendingRows.isEmpty) return null;

        final candidate = AttendanceOutboxEvent.fromDatabase(pendingRows.first);
        final candidateNextAttemptAt = candidate.nextAttemptAt;
        if (candidateNextAttemptAt != null &&
            candidateNextAttemptAt.isAfter(now.toUtc())) {
          return null;
        }

        final updated = await txn.rawUpdate(
          'UPDATE $_table SET '
          'state = ?, attempt_count = attempt_count + 1, '
          'sync_started_at = ?, updated_at = ? '
          'WHERE client_event_id = ? AND owner_user_id = ? '
          'AND employee_id = ? AND state = ? AND attempt_count = ?',
          [
            AttendanceOutboxState.syncing.name,
            claimedAt,
            claimedAt,
            candidate.clientEventId,
            ownerUserId,
            employeeId,
            AttendanceOutboxState.pending.name,
            candidate.attemptCount,
          ],
        );
        if (updated != 1) return null;

        return _findAnyOwner(txn, candidate.clientEventId);
      }

      final nextAttemptAt = earliest.nextAttemptAt;
      if (nextAttemptAt != null && nextAttemptAt.isAfter(now.toUtc())) {
        return null;
      }

      final updated = await txn.rawUpdate(
        'UPDATE $_table SET '
        'state = ?, attempt_count = attempt_count + 1, '
        'sync_started_at = ?, updated_at = ? '
        'WHERE client_event_id = ? AND owner_user_id = ? '
        'AND employee_id = ? AND state = ? AND attempt_count = ?',
        [
          AttendanceOutboxState.syncing.name,
          claimedAt,
          claimedAt,
          earliest.clientEventId,
          ownerUserId,
          employeeId,
          AttendanceOutboxState.pending.name,
          earliest.attemptCount,
        ],
      );
      if (updated != 1) return null;

      return _findAnyOwner(txn, earliest.clientEventId);
    });
  }

  @override
  Future<int> recoverStaleClaims({
    required int ownerUserId,
    required DateTime staleBefore,
    required DateTime now,
    int? employeeId,
  }) async {
    final db = await _database.database;
    final threshold = formatOutboxTimestamp(staleBefore);
    final nowValue = formatOutboxTimestamp(now);

    return db.transaction((txn) async {
      final where = <String>[
        'owner_user_id = ?',
        'state = ?',
        'sync_started_at IS NOT NULL',
        'sync_started_at <= ?',
      ];
      final args = <Object?>[
        ownerUserId,
        AttendanceOutboxState.syncing.name,
        threshold,
      ];
      if (employeeId != null) {
        where.add('employee_id = ?');
        args.add(employeeId);
      }

      final rows = await txn.query(
        _table,
        columns: ['client_event_id'],
        where: where.join(' AND '),
        whereArgs: args,
      );

      var recovered = 0;
      for (final row in rows) {
        final updated = await txn.rawUpdate(
          'UPDATE $_table SET '
          'state = ?, sync_started_at = NULL, next_attempt_at = ?, '
          'last_error_code = ?, last_error_message = ?, updated_at = ? '
          'WHERE client_event_id = ? AND owner_user_id = ? AND state = ?',
          [
            AttendanceOutboxState.pending.name,
            nowValue,
            'SYNC_LEASE_EXPIRED',
            'Sinkronisasi tidak selesai sebelum batas waktu.',
            nowValue,
            row['client_event_id'],
            ownerUserId,
            AttendanceOutboxState.syncing.name,
          ],
        );
        recovered += updated;
      }
      return recovered;
    });
  }

  @override
  Future<AttendanceOutboxEvent> releaseForRetry({
    required String clientEventId,
    required int ownerUserId,
    required String errorCode,
    required String errorMessage,
    required DateTime nextAttemptAt,
    required DateTime now,
    int? employeeId,
  }) async {
    final db = await _database.database;
    final nowValue = formatOutboxTimestamp(now);

    return db.transaction((txn) async {
      final where = <String>[
        'client_event_id = ?',
        'owner_user_id = ?',
        'state = ?',
      ];
      final args = <Object?>[
        clientEventId,
        ownerUserId,
        AttendanceOutboxState.syncing.name,
      ];
      if (employeeId != null) {
        where.add('employee_id = ?');
        args.add(employeeId);
      }

      final updated = await txn.rawUpdate(
        'UPDATE $_table SET '
        'state = ?, attempt_count = attempt_count + 1, '
        'sync_started_at = NULL, next_attempt_at = ?, '
        'last_error_code = ?, last_error_message = ?, updated_at = ? '
        'WHERE ${where.join(' AND ')}',
        [
          AttendanceOutboxState.pending.name,
          formatOutboxTimestamp(nextAttemptAt),
          errorCode,
          errorMessage,
          nowValue,
          ...args,
        ],
      );
      if (updated != 1) {
        throw AttendanceOutboxTransitionException(
          clientEventId,
          operation: 'releaseForRetry',
        );
      }

      final event = await _findForOwner(txn, clientEventId, ownerUserId);
      return event!;
    });
  }

  @override
  Future<AttendanceOutboxEvent> markSynced({
    required String clientEventId,
    required int ownerUserId,
    required int serverEventId,
    required String serverStatus,
    required DateTime serverReceivedAt,
    required DateTime syncedAt,
    int? employeeId,
  }) async {
    if (serverEventId <= 0) {
      throw ArgumentError.value(serverEventId, 'serverEventId');
    }
    if (serverStatus.trim().isEmpty) {
      throw ArgumentError.value(serverStatus, 'serverStatus');
    }

    final db = await _database.database;

    return db.transaction((txn) async {
      final where = <String>[
        'client_event_id = ?',
        'owner_user_id = ?',
        'state = ?',
      ];
      final args = <Object?>[
        clientEventId,
        ownerUserId,
        AttendanceOutboxState.syncing.name,
      ];
      if (employeeId != null) {
        where.add('employee_id = ?');
        args.add(employeeId);
      }

      final updated = await txn.rawUpdate(
        'UPDATE $_table SET '
        'state = ?, sync_started_at = NULL, next_attempt_at = NULL, '
        'last_error_code = NULL, last_error_message = NULL, '
        'server_event_id = ?, server_status = ?, server_received_at = ?, '
        'synced_at = ?, updated_at = ? '
        'WHERE ${where.join(' AND ')}',
        [
          AttendanceOutboxState.synced.name,
          serverEventId,
          serverStatus,
          formatOutboxTimestamp(serverReceivedAt),
          formatOutboxTimestamp(syncedAt),
          formatOutboxTimestamp(syncedAt),
          ...args,
        ],
      );
      if (updated != 1) {
        throw AttendanceOutboxTransitionException(
          clientEventId,
          operation: 'markSynced',
        );
      }

      final event = await _findForOwner(txn, clientEventId, ownerUserId);
      return event!;
    });
  }

  @override
  Future<AttendanceOutboxEvent> markRejected({
    required String clientEventId,
    required int ownerUserId,
    required String errorCode,
    required String errorMessage,
    required DateTime now,
    int? employeeId,
  }) async {
    final db = await _database.database;

    return db.transaction((txn) async {
      final where = <String>[
        'client_event_id = ?',
        'owner_user_id = ?',
        'state = ?',
      ];
      final args = <Object?>[
        clientEventId,
        ownerUserId,
        AttendanceOutboxState.syncing.name,
      ];
      if (employeeId != null) {
        where.add('employee_id = ?');
        args.add(employeeId);
      }

      final updated = await txn.rawUpdate(
        'UPDATE $_table SET '
        'state = ?, sync_started_at = NULL, next_attempt_at = NULL, '
        'last_error_code = ?, last_error_message = ?, updated_at = ? '
        'WHERE ${where.join(' AND ')}',
        [
          AttendanceOutboxState.rejected.name,
          errorCode,
          errorMessage,
          formatOutboxTimestamp(now),
          ...args,
        ],
      );
      if (updated != 1) {
        throw AttendanceOutboxTransitionException(
          clientEventId,
          operation: 'markRejected',
        );
      }

      final event = await _findForOwner(txn, clientEventId, ownerUserId);
      return event!;
    });
  }

  @override
  Future<OutboxPurgeResult> purgeAcknowledgedBefore({
    required int ownerUserId,
    required DateTime cutoff,
  }) async {
    final db = await _database.database;
    final cutoffValue = formatOutboxTimestamp(cutoff);

    return db.transaction((txn) async {
      final rows = await txn.query(
        _table,
        columns: ['photo_filename'],
        distinct: true,
        where:
            'owner_user_id = ? AND state = ? '
            'AND synced_at IS NOT NULL AND synced_at <= ?',
        whereArgs: [
          ownerUserId,
          AttendanceOutboxState.synced.name,
          cutoffValue,
        ],
      );
      final filenames = rows
          .map((row) => row['photo_filename'] as String)
          .toSet();

      final deleted = await txn.delete(
        _table,
        where:
            'owner_user_id = ? AND state = ? '
            'AND synced_at IS NOT NULL AND synced_at <= ?',
        whereArgs: [
          ownerUserId,
          AttendanceOutboxState.synced.name,
          cutoffValue,
        ],
      );

      return OutboxPurgeResult(deletedRows: deleted, photoFilenames: filenames);
    });
  }

  @override
  Future<Set<String>> referencedPhotoFilenames() async {
    final db = await _database.database;
    final rows = await db.query(
      _table,
      columns: ['photo_filename'],
      distinct: true,
    );
    return rows.map((row) => row['photo_filename'] as String).toSet();
  }

  @override
  Future<bool> isPhotoReferenced(String filename) async {
    final db = await _database.database;
    final rows = await db.query(
      _table,
      columns: ['client_event_id'],
      where: 'photo_filename = ?',
      whereArgs: [filename],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<bool> hasQueuedPhotoReference(String filename) async {
    final db = await _database.database;
    final rows = await db.query(
      _table,
      columns: ['client_event_id'],
      where: 'photo_filename = ? AND state IN (?, ?)',
      whereArgs: [
        filename,
        AttendanceOutboxState.pending.name,
        AttendanceOutboxState.syncing.name,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<AttendanceOutboxEvent?> _findAnyOwner(
    DatabaseExecutor executor,
    String clientEventId,
  ) async {
    final rows = await executor.query(
      _table,
      where: 'client_event_id = ?',
      whereArgs: [clientEventId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AttendanceOutboxEvent.fromDatabase(rows.first);
  }

  Future<AttendanceOutboxEvent?> _findForOwner(
    DatabaseExecutor executor,
    String clientEventId,
    int ownerUserId,
  ) async {
    final rows = await executor.query(
      _table,
      where: 'client_event_id = ? AND owner_user_id = ?',
      whereArgs: [clientEventId, ownerUserId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AttendanceOutboxEvent.fromDatabase(rows.first);
  }

  Future<int> _nextLocalSequence(Transaction txn) async {
    final updated = await txn.rawUpdate(
      'UPDATE ${AttendanceOutboxDatabase.sequenceTableName} '
      'SET next_value = next_value + 1 WHERE id = 1',
    );
    if (updated != 1) {
      throw StateError('Outbox local sequence is not initialized.');
    }
    final rows = await txn.query(
      AttendanceOutboxDatabase.sequenceTableName,
      columns: ['next_value'],
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Outbox local sequence is not initialized.');
    }
    return (rows.first['next_value'] as int) - 1;
  }

  Map<String, Object?> _pendingRow(
    AttendanceOutboxEvent event,
    int localSequence,
  ) {
    final row = event.toDatabase();
    row['local_sequence'] = localSequence;
    row['state'] = AttendanceOutboxState.pending.name;
    row['attempt_count'] = 0;
    row['sync_started_at'] = null;
    return row;
  }

  void _validatePending(AttendanceOutboxEvent event) {
    if (event.state != AttendanceOutboxState.pending) {
      throw ArgumentError.value(event.state, 'state', 'Must be pending.');
    }
    if (event.attemptCount != 0) {
      throw ArgumentError.value(event.attemptCount, 'attemptCount');
    }
    if (event.syncStartedAt != null ||
        event.serverEventId != null ||
        event.serverStatus != null ||
        event.serverReceivedAt != null ||
        event.syncedAt != null ||
        event.lastErrorCode != null ||
        event.lastErrorMessage != null) {
      throw ArgumentError('A pending event must not carry server state.');
    }
    if (!isSafeClientEventId(event.clientEventId)) {
      throw ArgumentError.value(
        event.clientEventId,
        'clientEventId',
        'Must be a safe event id of 1 to 100 characters.',
      );
    }
    if (event.ownerUserId <= 0) {
      throw ArgumentError.value(event.ownerUserId, 'ownerUserId');
    }
    if (event.employeeId <= 0) {
      throw ArgumentError.value(event.employeeId, 'employeeId');
    }
    if (event.deviceUuid.trim().isEmpty || event.deviceUuid.length > 100) {
      throw ArgumentError.value(event.deviceUuid, 'deviceUuid');
    }
    if (!isSafePhotoFilename(event.photoFilename)) {
      throw ArgumentError.value(
        event.photoFilename,
        'photoFilename',
        'Must be a relative file name without path segments.',
      );
    }
    if (!event.latitude.isFinite ||
        event.latitude < -90 ||
        event.latitude > 90) {
      throw ArgumentError.value(event.latitude, 'latitude');
    }
    if (!event.longitude.isFinite ||
        event.longitude < -180 ||
        event.longitude > 180) {
      throw ArgumentError.value(event.longitude, 'longitude');
    }
    if (!event.accuracyMeters.isFinite || event.accuracyMeters < 0) {
      throw ArgumentError.value(event.accuracyMeters, 'accuracyMeters');
    }
  }
}
