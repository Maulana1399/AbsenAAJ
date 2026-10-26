enum AttendanceEventType {
  checkIn('CHECK_IN'),
  checkOut('CHECK_OUT');

  const AttendanceEventType(this.key);
  final String key;

  static AttendanceEventType fromKey(String key) =>
      AttendanceEventType.values.firstWhere((e) => e.key == key);
}

/// Raw GPS reading produced by the platform location API.
class GpsReading {
  const GpsReading({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;

  Map<String, dynamic> toFields() => {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'accuracy_meters': accuracyMeters.toStringAsFixed(2),
      };
}

/// Result of taking a selfie in the app (bytes + capture time).
class SelfieResult {
  const SelfieResult({required this.bytes, required this.capturedAt});

  final List<int> bytes;
  final DateTime capturedAt;
}

class AttendancePhoto {
  const AttendancePhoto({
    required this.id,
    required this.mimeType,
    required this.fileSize,
    required this.sha256,
    this.capturedAt,
  });

  final int id;
  final String mimeType;
  final int fileSize;
  final String sha256;
  final DateTime? capturedAt;

  factory AttendancePhoto.fromJson(Map<String, dynamic> json) => AttendancePhoto(
        id: json['id'] as int,
        mimeType: json['mime_type'] as String? ?? '',
        fileSize: json['file_size'] as int? ?? 0,
        sha256: json['sha256'] as String? ?? '',
        capturedAt: DateTime.tryParse(json['captured_at'] as String? ?? ''),
      );
}

/// Attendance event as returned by the server. The server is the source of
/// truth for status, timing, distance, and location validity.
class AttendanceEvent {
  const AttendanceEvent({
    required this.id,
    required this.clientEventId,
    required this.eventType,
    required this.status,
    this.employeeId,
    this.deviceId,
    this.eventAt,
    this.serverReceivedAt,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.distanceMeters,
    this.locationValid,
    this.photo,
  });

  final int id;
  final String clientEventId;
  final String eventType;
  final String status;
  final int? employeeId;
  final int? deviceId;
  final DateTime? eventAt;
  final DateTime? serverReceivedAt;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final double? distanceMeters;
  final bool? locationValid;
  final AttendancePhoto? photo;

  bool get isCheckIn => eventType == AttendanceEventType.checkIn.key;

  factory AttendanceEvent.fromJson(Map<String, dynamic> json) => AttendanceEvent(
        id: json['id'] as int,
        clientEventId: json['client_event_id'] as String? ?? '',
        eventType: json['event_type'] as String? ?? '',
        status: json['status'] as String? ?? '',
        employeeId: json['employee_id'] as int?,
        deviceId: json['device_id'] as int?,
        eventAt: DateTime.tryParse(json['event_at'] as String? ?? ''),
        serverReceivedAt: DateTime.tryParse(json['server_received_at'] as String? ?? ''),
        latitude: _asDouble(json['latitude']),
        longitude: _asDouble(json['longitude']),
        accuracyMeters: _asDouble(json['accuracy_meters']),
        distanceMeters: _asDouble(json['distance_meters']),
        locationValid: json['location_valid'] as bool?,
        photo: json['photo'] == null
            ? null
            : AttendancePhoto.fromJson(json['photo'] as Map<String, dynamic>),
      );
}

/// Result of the device registration endpoint.
class DeviceInfo {
  const DeviceInfo({
    required this.id,
    required this.deviceUuid,
    required this.status,
  });

  final int id;
  final String deviceUuid;
  final String status;

  factory DeviceInfo.fromJson(Map<String, dynamic> json) => DeviceInfo(
        id: json['id'] as int,
        deviceUuid: json['device_uuid'] as String? ?? '',
        status: json['status'] as String? ?? '',
      );
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}