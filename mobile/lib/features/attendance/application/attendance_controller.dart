import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/storage/device_identity.dart';
import '../data/local/local_attendance_providers.dart';
import '../domain/attendance_models.dart';
import '../domain/attendance_outbox_event.dart';
import '../services/camera_service.dart';
import '../services/location_service.dart';
import 'attendance_sync_providers.dart';
import 'attendance_sync_worker.dart';

enum AttendancePhase { idle, submitting, success, queued, error }

class AttendanceSubmissionState {
  const AttendanceSubmissionState({
    this.phase = AttendancePhase.idle,
    this.event,
    this.queuedEvent,
    this.errorMessage,
    this.errorCode,
  });

  final AttendancePhase phase;
  final AttendanceEvent? event;
  final AttendanceOutboxEvent? queuedEvent;
  final String? errorMessage;
  final String? errorCode;

  bool get isSubmitting => phase == AttendancePhase.submitting;
  bool get isSuccess => phase == AttendancePhase.success;
  bool get isQueued => phase == AttendancePhase.queued;
  bool get isError => phase == AttendancePhase.error;

  AttendanceSubmissionState copyWith({
    AttendancePhase? phase,
    AttendanceEvent? event,
    AttendanceOutboxEvent? queuedEvent,
    String? errorMessage,
    String? errorCode,
    bool clearEvent = false,
  }) {
    return AttendanceSubmissionState(
      phase: phase ?? this.phase,
      event: clearEvent ? null : (event ?? this.event),
      queuedEvent: clearEvent ? null : (queuedEvent ?? this.queuedEvent),
      errorMessage: errorMessage ?? this.errorMessage,
      errorCode: errorCode ?? this.errorCode,
    );
  }
}

/// Orchestrates the check-in / check-out flow:
/// GPS -> selfie -> durable outbox enqueue -> sync worker -> server ack.
class AttendanceSubmissionController
    extends StateNotifier<AttendanceSubmissionState> {
  AttendanceSubmissionController(this._ref)
    : super(const AttendanceSubmissionState());

  final Ref _ref;

  static const localQueuedMessage =
      'Absensi tersimpan di perangkat, menunggu sinkronisasi.';

  Future<void> submitCheckIn() => _submit(AttendanceEventType.checkIn);

  Future<void> submitCheckOut() => _submit(AttendanceEventType.checkOut);

  void reset() => state = const AttendanceSubmissionState();

  Future<void> _submit(AttendanceEventType type) async {
    if (state.isSubmitting) return;

    state = state.copyWith(phase: AttendancePhase.submitting, clearEvent: true);

    try {
      final session = _ref.read(sessionControllerProvider);
      final user = session.user;
      final employee = user?.employee;
      if (!session.isAuthenticated || user == null || employee == null) {
        throw const AppException(
          'Akun belum terhubung dengan data karyawan.',
          code: 'EMPLOYEE_REQUIRED',
        );
      }

      final location = await _ref.read(locationServiceProvider).getLocation();

      final photo = await _ref.read(cameraServiceProvider).capture();
      if (photo == null) {
        // pengguna membatalkan selfie
        state = const AttendanceSubmissionState();
        return;
      }

      final deviceUuid = await _ref.read(deviceIdentityProvider).uuid();
      final clientEventId = const Uuid().v4();
      final eventAt = DateTime.now();

      final AttendanceOutboxEvent queued;
      try {
        queued = await _ref
            .read(attendanceOutboxWriterProvider)
            .enqueue(
              clientEventId: clientEventId,
              ownerUserId: user.id,
              employeeId: employee.id,
              deviceUuid: deviceUuid,
              eventType: type,
              eventAt: eventAt,
              capturedAt: photo.capturedAt,
              gps: location,
              photoBytes: photo.bytes,
            );
      } catch (_) {
        state = const AttendanceSubmissionState(
          phase: AttendancePhase.error,
          errorCode: 'LOCAL_STORAGE_ERROR',
          errorMessage:
              'Absensi gagal disimpan di perangkat. Silakan coba lagi.',
        );
        return;
      }

      // The event is durable before we attempt the network. Keep the UI in the
      // submitting state while the foreground sync runs.
      final AttendanceSyncRunResult result;
      try {
        result = await _ref
            .read(attendanceSyncRunnerProvider)
            .syncNow(ownerUserId: user.id, employeeId: employee.id);
      } catch (_) {
        // The queue is already durable; a network/sync crash must never look
        // like the attendance was not saved.
        state = AttendanceSubmissionState(
          phase: AttendancePhase.queued,
          queuedEvent: queued,
          errorCode: 'SYNC_PENDING',
          errorMessage: localQueuedMessage,
        );
        return;
      }

      final acknowledged = result.eventFor(clientEventId);
      if (acknowledged != null) {
        state = AttendanceSubmissionState(
          phase: AttendancePhase.success,
          event: acknowledged,
        );
        return;
      }

      final failure = result.failure;
      if (failure == null || !failure.isPermanent) {
        final message = failure == null || failure.isRetryable
            ? localQueuedMessage
            : '$localQueuedMessage ${failure.message}';
        state = AttendanceSubmissionState(
          phase: AttendancePhase.queued,
          queuedEvent: queued,
          errorCode: failure?.code ?? 'SYNC_PENDING',
          errorMessage: message,
        );
        return;
      }

      // The server definitively rejected this event. It is not silently
      // converted back into a pending queue item.
      state = AttendanceSubmissionState(
        phase: AttendancePhase.error,
        errorCode: failure.code,
        errorMessage: failure.message,
      );
    } on LocationException catch (error) {
      state = AttendanceSubmissionState(
        phase: AttendancePhase.error,
        errorMessage: error.message,
        errorCode: error.code,
      );
    } on CameraException catch (error) {
      state = AttendanceSubmissionState(
        phase: AttendancePhase.error,
        errorMessage: error.message,
        errorCode: error.code,
      );
    } on AppException catch (error) {
      state = AttendanceSubmissionState(
        phase: AttendancePhase.error,
        errorMessage: error.message,
        errorCode: error.code,
      );
    } catch (_) {
      state = const AttendanceSubmissionState(
        phase: AttendancePhase.error,
        errorMessage: 'Terjadi kesalahan. Silakan coba lagi.',
        errorCode: 'UNKNOWN',
      );
    }
  }
}

final attendanceSubmissionProvider =
    StateNotifierProvider<
      AttendanceSubmissionController,
      AttendanceSubmissionState
    >((ref) => AttendanceSubmissionController(ref));
