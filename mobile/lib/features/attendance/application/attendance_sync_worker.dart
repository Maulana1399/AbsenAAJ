import 'dart:async';
import 'dart:io';

import '../data/attendance_sync_api.dart';
import '../data/local/attendance_outbox_exceptions.dart';
import '../data/local/attendance_outbox_repository.dart';
import '../data/local/attendance_photo_storage.dart';
import '../domain/attendance_models.dart';
import '../domain/attendance_outbox_event.dart';
import 'attendance_sync_policy.dart';

class AttendanceSyncRunResult {
  const AttendanceSyncRunResult({this.acknowledged = const [], this.failure});

  final List<AttendanceEvent> acknowledged;
  final AttendanceSyncFailure? failure;

  bool get isPaused => failure != null;

  AttendanceEvent? eventFor(String clientEventId) {
    for (final event in acknowledged) {
      if (event.clientEventId == clientEventId) return event;
    }
    return null;
  }
}

abstract interface class AttendanceSyncRunner {
  Future<AttendanceSyncRunResult> syncNow({
    required int ownerUserId,
    required int employeeId,
  });
}

class AttendanceSyncWorker implements AttendanceSyncRunner {
  AttendanceSyncWorker(
    this._outbox,
    this._photoStorage,
    this._api, {
    DateTime Function()? clock,
    bool Function()? isSessionActive,
    Duration? leaseDuration,
  }) : _clock = clock ?? DateTime.now,
       _isSessionActive = isSessionActive ?? (() => true),
       _leaseDuration = leaseDuration ?? const Duration(minutes: 5);

  final AttendanceOutboxRepository _outbox;
  final AttendancePhotoStorage _photoStorage;
  final AttendanceSyncApi _api;
  final DateTime Function() _clock;
  final bool Function() _isSessionActive;
  final Duration _leaseDuration;

  final Map<String, Future<void>> _tails = {};

  @override
  Future<AttendanceSyncRunResult> syncNow({
    required int ownerUserId,
    required int employeeId,
  }) {
    final key = '$ownerUserId:$employeeId';
    return _serialized(
      key,
      () => _run(ownerUserId: ownerUserId, employeeId: employeeId),
    );
  }

  Future<AttendanceSyncRunResult> _run({
    required int ownerUserId,
    required int employeeId,
  }) async {
    final acknowledged = <AttendanceEvent>[];
    final startedAt = _clock().toUtc();

    await _outbox.recoverStaleClaims(
      ownerUserId: ownerUserId,
      employeeId: employeeId,
      staleBefore: startedAt.subtract(_leaseDuration),
      now: startedAt,
    );

    while (true) {
      if (!_isSessionActive()) {
        return AttendanceSyncRunResult(
          acknowledged: acknowledged,
          failure: const AttendanceSyncFailure(
            kind: AttendanceSyncFailureKind.authentication,
            code: 'UNAUTHENTICATED',
            message: 'Sesi berakhir. Silakan login kembali.',
          ),
        );
      }

      final event = await _outbox.claimNextForEmployee(
        ownerUserId: ownerUserId,
        employeeId: employeeId,
        now: _clock(),
      );
      if (event == null) break;

      if (!_isSessionActive()) {
        await _release(
          event,
          const AttendanceSyncFailure(
            kind: AttendanceSyncFailureKind.authentication,
            code: 'UNAUTHENTICATED',
            message: 'Sesi berakhir. Silakan login kembali.',
          ),
          ownerUserId,
          employeeId,
        );
        return AttendanceSyncRunResult(
          acknowledged: acknowledged,
          failure: const AttendanceSyncFailure(
            kind: AttendanceSyncFailureKind.authentication,
            code: 'UNAUTHENTICATED',
            message: 'Sesi berakhir. Silakan login kembali.',
          ),
        );
      }

      try {
        if (!await _photoStorage.exists(event.photoFilename)) {
          const failure = AttendanceSyncFailure(
            kind: AttendanceSyncFailureKind.permanentRejection,
            code: 'PHOTO_LOCAL_MISSING',
            message: 'Foto absensi tidak ditemukan di perangkat.',
          );
          await _applyFailure(event, failure, ownerUserId, employeeId);
          return AttendanceSyncRunResult(
            acknowledged: acknowledged,
            failure: failure,
          );
        }

        final photoBytes = await _photoStorage.read(event.photoFilename);
        final response = await _api.submit(
          clientEventId: event.clientEventId,
          deviceUuid: event.deviceUuid,
          eventType: event.eventType,
          eventAt: event.eventAt,
          gps: GpsReading(
            latitude: event.latitude,
            longitude: event.longitude,
            accuracyMeters: event.accuracyMeters,
          ),
          capturedAt: event.capturedAt,
          photoBytes: photoBytes,
        );

        final serverEvent = response.event;
        final syncedAt = _clock();
        await _outbox.markSynced(
          clientEventId: event.clientEventId,
          ownerUserId: ownerUserId,
          employeeId: employeeId,
          serverEventId: serverEvent.id,
          serverStatus: serverEvent.status,
          serverReceivedAt: serverEvent.serverReceivedAt ?? syncedAt,
          syncedAt: syncedAt,
        );
        acknowledged.add(serverEvent);
        await _outbox.deletePhotoAfterAck(event.photoFilename);
      } on AttendanceSyncApiException catch (error) {
        final failure = classifyAttendanceSyncFailure(error);
        await _applyFailure(event, failure, ownerUserId, employeeId);
        return AttendanceSyncRunResult(
          acknowledged: acknowledged,
          failure: failure,
        );
      } on FileSystemException {
        const failure = AttendanceSyncFailure(
          kind: AttendanceSyncFailureKind.retryable,
          code: 'PHOTO_READ_ERROR',
          message: 'Foto absensi gagal dibaca. Akan dicoba lagi.',
        );
        await _applyFailure(event, failure, ownerUserId, employeeId);
        return AttendanceSyncRunResult(
          acknowledged: acknowledged,
          failure: failure,
        );
      } on AttendanceOutboxTransitionException {
        return AttendanceSyncRunResult(
          acknowledged: acknowledged,
          failure: const AttendanceSyncFailure(
            kind: AttendanceSyncFailureKind.retryable,
            code: 'SYNC_STATE_CHANGED',
            message: 'Status antrean berubah. Sinkronisasi akan dicoba lagi.',
          ),
        );
      } catch (_) {
        const failure = AttendanceSyncFailure(
          kind: AttendanceSyncFailureKind.retryable,
          code: 'SYNC_UNKNOWN_ERROR',
          message: 'Absensi belum dapat dikirim. Akan dicoba lagi.',
        );
        await _applyFailure(event, failure, ownerUserId, employeeId);
        return AttendanceSyncRunResult(
          acknowledged: acknowledged,
          failure: failure,
        );
      }
    }

    return AttendanceSyncRunResult(acknowledged: acknowledged);
  }

  Future<void> _applyFailure(
    AttendanceOutboxEvent event,
    AttendanceSyncFailure failure,
    int ownerUserId,
    int employeeId,
  ) {
    if (failure.isPermanent) {
      final now = _clock();
      return _outbox.markRejected(
        clientEventId: event.clientEventId,
        ownerUserId: ownerUserId,
        employeeId: employeeId,
        errorCode: failure.code,
        errorMessage: failure.message,
        now: now,
      );
    }
    return _release(event, failure, ownerUserId, employeeId);
  }

  Future<void> _release(
    AttendanceOutboxEvent event,
    AttendanceSyncFailure failure,
    int ownerUserId,
    int employeeId,
  ) {
    final now = _clock().toUtc();
    final delay = failure.isAuthentication
        ? Duration.zero
        : attendanceSyncRetryDelay(
            event.attemptCount,
            retryAfter: failure.retryAfter,
          );
    return _outbox.releaseForRetry(
      clientEventId: event.clientEventId,
      ownerUserId: ownerUserId,
      employeeId: employeeId,
      errorCode: failure.code,
      errorMessage: failure.message,
      nextAttemptAt: now.add(delay),
      now: now,
    );
  }

  Future<T> _serialized<T>(String key, Future<T> Function() action) {
    final previous = _tails[key] ?? Future<void>.value();
    final completer = Completer<void>();
    final gate = completer.future;
    _tails[key] = gate;

    return previous.catchError((_) {}).then((_) => action()).whenComplete(() {
      completer.complete();
      if (identical(_tails[key], gate)) {
        _tails.remove(key);
      }
    });
  }
}
