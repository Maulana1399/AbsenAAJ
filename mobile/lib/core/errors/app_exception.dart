/// Application-level exception surfaced to the UI.
///
/// `code` is the API error code when available (e.g. `OUTSIDE_GEOFENCE`) or a
/// local identifier. `message` is always user friendly - never a stack trace
/// or internal server detail.
class AppException implements Exception {
  const AppException(this.message, {this.code = 'UNKNOWN', this.original});

  final String message;
  final String code;
  final Object? original;

  @override
  String toString() => 'AppException($code): $message';
}

/// Network/connectivity failures (timeout, cannot resolve host, ...).
class NetworkException extends AppException {
  const NetworkException()
      : super('Absensi gagal dikirim. Periksa koneksi internet dan coba lagi.',
            code: 'NETWORK_ERROR');
}

/// 401 - the token is no longer valid.
class SessionExpiredException extends AppException {
  const SessionExpiredException()
      : super('Sesi berakhir. Silakan login kembali.', code: 'UNAUTHENTICATED');
}

/// GPS is disabled / permission missing / denied forever.
enum LocationDenial { serviceDisabled, denied, permanentlyDenied }

class LocationException extends AppException {
  const LocationException(
    super.message,
    this.denial, {
    super.code,
    super.original,
  });

  final LocationDenial denial;
}

class CameraException extends AppException {
  const CameraException(
    super.message, {
    super.code = 'CAMERA_ERROR',
    super.original,
  });
}
