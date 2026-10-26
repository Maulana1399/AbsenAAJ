import '../../../core/errors/error_mapper.dart';
import '../data/attendance_sync_api.dart';

enum AttendanceSyncFailureKind {
  retryable,
  authentication,
  permanentRejection,
  userActionRequired,
}

class AttendanceSyncFailure {
  const AttendanceSyncFailure({
    required this.kind,
    required this.code,
    required this.message,
    this.statusCode,
    this.retryAfter,
  });

  final AttendanceSyncFailureKind kind;
  final String code;
  final String message;
  final int? statusCode;
  final Duration? retryAfter;

  bool get isAuthentication => kind == AttendanceSyncFailureKind.authentication;

  bool get isPermanent => kind == AttendanceSyncFailureKind.permanentRejection;

  bool get isRetryable => kind == AttendanceSyncFailureKind.retryable;

  bool get isUserActionRequired =>
      kind == AttendanceSyncFailureKind.userActionRequired;
}

const _genericMessage = 'Terjadi kesalahan. Silakan coba lagi.';

AttendanceSyncFailure classifyAttendanceSyncFailure(
  AttendanceSyncApiException error,
) {
  final code = error.code ?? 'SYNC_ERROR';
  final kind = _classifyKind(error);
  return AttendanceSyncFailure(
    kind: kind,
    code: code,
    message: _failureMessage(error),
    statusCode: error.statusCode,
    retryAfter: error.retryAfter,
  );
}

AttendanceSyncFailureKind _classifyKind(AttendanceSyncApiException error) {
  final code = error.code;
  final status = error.statusCode;

  if (code == 'DEVICE_NOT_FOUND' || code == 'EMPLOYEE_REQUIRED') {
    return AttendanceSyncFailureKind.userActionRequired;
  }
  if (error.isNetwork) {
    return AttendanceSyncFailureKind.retryable;
  }
  if (status == 401) {
    return AttendanceSyncFailureKind.authentication;
  }
  if (status == 408 || status == 429) {
    return AttendanceSyncFailureKind.retryable;
  }
  if (status != null && status >= 500) {
    return AttendanceSyncFailureKind.retryable;
  }
  if (error.isProtocol) {
    return AttendanceSyncFailureKind.retryable;
  }
  if (code == 'DEVICE_REVOKED' ||
      code == 'ATTENDANCE_EVENT_CONFLICT' ||
      code == 'ALREADY_CHECKED_IN' ||
      code == 'ALREADY_CHECKED_OUT' ||
      code == 'CHECK_IN_REQUIRED' ||
      code == 'OUTSIDE_GEOFENCE' ||
      code == 'LOCATION_LOW_ACCURACY' ||
      code == 'BRANCH_NOT_CONFIGURED' ||
      code == 'BRANCH_LOCATION_NOT_CONFIGURED' ||
      code == 'VALIDATION_ERROR') {
    return AttendanceSyncFailureKind.permanentRejection;
  }
  if (status != null && status >= 400 && status < 500) {
    // Unknown client errors are not permanent rejections; the user may need
    // to take an action (re-login, contact admin) before retrying.
    return AttendanceSyncFailureKind.userActionRequired;
  }
  if (status == null) {
    return AttendanceSyncFailureKind.retryable;
  }
  return AttendanceSyncFailureKind.userActionRequired;
}

String _failureMessage(AttendanceSyncApiException error) {
  final code = error.code;
  if (code != null) {
    final mapped = apiErrorCodeToMessage(code);
    if (mapped != _genericMessage) return mapped;
  }
  if (error.isNetwork) {
    return 'Tidak dapat terhubung ke server. Absensi akan dicoba lagi.';
  }
  if (error.statusCode == 401) {
    return 'Sesi berakhir. Silakan login kembali.';
  }
  if (error.message.trim().isNotEmpty) return error.message;
  return 'Absensi belum dapat dikirim. Akan dicoba lagi.';
}

const attendanceSyncBaseDelay = Duration(seconds: 30);
const attendanceSyncMaxDelay = Duration(minutes: 30);
const attendanceSyncMaxRetryAfter = Duration(hours: 12);

Duration attendanceSyncRetryDelay(int attemptCount, {Duration? retryAfter}) {
  if (retryAfter != null && retryAfter > Duration.zero) {
    return retryAfter > attendanceSyncMaxRetryAfter
        ? attendanceSyncMaxRetryAfter
        : retryAfter;
  }

  final exponent = (attemptCount <= 1 ? 0 : attemptCount - 1)
      .clamp(0, 10)
      .toInt();
  final delay = attendanceSyncBaseDelay * (1 << exponent);
  return delay > attendanceSyncMaxDelay ? attendanceSyncMaxDelay : delay;
}
