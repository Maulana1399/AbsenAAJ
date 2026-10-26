import '../../domain/attendance_models.dart';
import '../../domain/attendance_outbox_event.dart';
import 'attendance_outbox_store.dart';
import 'attendance_photo_naming.dart';
import 'attendance_photo_storage.dart';

abstract interface class AttendanceOutboxWriter {
  Future<AttendanceOutboxEvent> enqueue({
    required String clientEventId,
    required int ownerUserId,
    required int employeeId,
    required String deviceUuid,
    required AttendanceEventType eventType,
    required DateTime eventAt,
    required DateTime capturedAt,
    required GpsReading gps,
    required List<int> photoBytes,
  });
}

class AttendanceOutboxRepository implements AttendanceOutboxWriter {
  AttendanceOutboxRepository(
    this._store,
    this._photoStorage, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AttendanceOutboxStore _store;
  final AttendancePhotoStorage _photoStorage;
  final DateTime Function() _clock;

  @override
  Future<AttendanceOutboxEvent> enqueue({
    required String clientEventId,
    required int ownerUserId,
    required int employeeId,
    required String deviceUuid,
    required AttendanceEventType eventType,
    required DateTime eventAt,
    required DateTime capturedAt,
    required GpsReading gps,
    required List<int> photoBytes,
  }) async {
    _validateEnqueue(
      clientEventId: clientEventId,
      ownerUserId: ownerUserId,
      employeeId: employeeId,
      deviceUuid: deviceUuid,
      gps: gps,
    );

    final existing = await _store.findForOwner(
      clientEventId: clientEventId,
      ownerUserId: ownerUserId,
    );
    if (existing != null) return existing;

    final photoFilename = await _photoStorage.writeJpeg(
      clientEventId: clientEventId,
      bytes: photoBytes,
    );

    final now = _clock().toUtc();
    final event = AttendanceOutboxEvent.pending(
      clientEventId: clientEventId,
      ownerUserId: ownerUserId,
      employeeId: employeeId,
      deviceUuid: deviceUuid,
      eventType: eventType,
      eventAt: eventAt.toUtc(),
      capturedAt: capturedAt.toUtc(),
      latitude: gps.latitude,
      longitude: gps.longitude,
      accuracyMeters: gps.accuracyMeters,
      photoFilename: photoFilename,
      createdAt: now,
    );

    try {
      final result = await _store.insertPending(event);
      if (!result.created) {
        await _deletePhotoIfUnreferenced(photoFilename);
      }
      return result.event;
    } catch (error, stackTrace) {
      await _deletePhotoIfUnreferenced(photoFilename);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<AttendanceOutboxEvent?> findForOwner({
    required String clientEventId,
    required int ownerUserId,
  }) {
    return _store.findForOwner(
      clientEventId: clientEventId,
      ownerUserId: ownerUserId,
    );
  }

  Future<void> deletePhotoIfUnreferenced(String filename) {
    return _deletePhotoIfUnreferenced(filename);
  }

  Future<void> deletePhotoAfterAck(String filename) async {
    try {
      if (await _store.hasQueuedPhotoReference(filename)) return;
      await _photoStorage.delete(filename);
    } catch (_) {
      return;
    }
  }

  Future<AttendanceOutboxEvent?> claimNextForEmployee({
    required int ownerUserId,
    required int employeeId,
    required DateTime now,
  }) {
    return _store.claimNextForEmployee(
      ownerUserId: ownerUserId,
      employeeId: employeeId,
      now: now,
    );
  }

  Future<int> recoverStaleClaims({
    required int ownerUserId,
    required DateTime staleBefore,
    required DateTime now,
    int? employeeId,
  }) {
    return _store.recoverStaleClaims(
      ownerUserId: ownerUserId,
      staleBefore: staleBefore,
      now: now,
      employeeId: employeeId,
    );
  }

  Future<AttendanceOutboxEvent> releaseForRetry({
    required String clientEventId,
    required int ownerUserId,
    required String errorCode,
    required String errorMessage,
    required DateTime nextAttemptAt,
    required DateTime now,
    int? employeeId,
  }) {
    return _store.releaseForRetry(
      clientEventId: clientEventId,
      ownerUserId: ownerUserId,
      errorCode: errorCode,
      errorMessage: errorMessage,
      nextAttemptAt: nextAttemptAt,
      now: now,
      employeeId: employeeId,
    );
  }

  Future<AttendanceOutboxEvent> markSynced({
    required String clientEventId,
    required int ownerUserId,
    required int serverEventId,
    required String serverStatus,
    required DateTime serverReceivedAt,
    required DateTime syncedAt,
    int? employeeId,
  }) {
    return _store.markSynced(
      clientEventId: clientEventId,
      ownerUserId: ownerUserId,
      serverEventId: serverEventId,
      serverStatus: serverStatus,
      serverReceivedAt: serverReceivedAt,
      syncedAt: syncedAt,
      employeeId: employeeId,
    );
  }

  Future<AttendanceOutboxEvent> markRejected({
    required String clientEventId,
    required int ownerUserId,
    required String errorCode,
    required String errorMessage,
    required DateTime now,
    int? employeeId,
  }) {
    return _store.markRejected(
      clientEventId: clientEventId,
      ownerUserId: ownerUserId,
      errorCode: errorCode,
      errorMessage: errorMessage,
      now: now,
      employeeId: employeeId,
    );
  }

  Future<OutboxPurgeResult> purgeAcknowledgedBefore({
    required int ownerUserId,
    required DateTime cutoff,
  }) async {
    final purged = await _store.purgeAcknowledgedBefore(
      ownerUserId: ownerUserId,
      cutoff: cutoff,
    );

    for (final filename in purged.photoFilenames) {
      await _deletePhotoIfUnreferenced(filename);
    }
    return purged;
  }

  Future<void> cleanupOrphans() async {
    final referenced = await _store.referencedPhotoFilenames();
    await _photoStorage.cleanupOrphans(
      referencedFilenames: referenced,
      isStillReferenced: _store.isPhotoReferenced,
    );
  }

  Future<void> _deletePhotoIfUnreferenced(String filename) async {
    try {
      if (await _store.isPhotoReferenced(filename)) return;
      await _photoStorage.delete(filename);
    } catch (_) {
      return;
    }
  }

  void _validateEnqueue({
    required String clientEventId,
    required int ownerUserId,
    required int employeeId,
    required String deviceUuid,
    required GpsReading gps,
  }) {
    if (!isSafeClientEventId(clientEventId)) {
      throw ArgumentError.value(
        clientEventId,
        'clientEventId',
        'Must be a safe event id of 1 to 100 characters.',
      );
    }
    if (ownerUserId <= 0) {
      throw ArgumentError.value(ownerUserId, 'ownerUserId');
    }
    if (employeeId <= 0) {
      throw ArgumentError.value(employeeId, 'employeeId');
    }
    if (deviceUuid.trim().isEmpty || deviceUuid.length > 100) {
      throw ArgumentError.value(deviceUuid, 'deviceUuid');
    }
    if (!gps.latitude.isFinite || gps.latitude < -90 || gps.latitude > 90) {
      throw ArgumentError.value(gps.latitude, 'latitude');
    }
    if (!gps.longitude.isFinite ||
        gps.longitude < -180 ||
        gps.longitude > 180) {
      throw ArgumentError.value(gps.longitude, 'longitude');
    }
    if (!gps.accuracyMeters.isFinite || gps.accuracyMeters < 0) {
      throw ArgumentError.value(gps.accuracyMeters, 'accuracyMeters');
    }
  }
}
