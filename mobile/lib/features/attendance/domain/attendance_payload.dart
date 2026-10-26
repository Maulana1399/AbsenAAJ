import 'package:dio/dio.dart';

import 'attendance_models.dart';

/// Builds the non-file fields of the attendance request.
///
/// Important: the client never sends authoritative values that the server
/// must compute - no `distance_meters`, no `location_valid`, no `status`,
/// no `employee_id`.
Map<String, dynamic> buildEventFields({
  required String clientEventId,
  required String deviceUuid,
  required AttendanceEventType eventType,
  required DateTime eventAt,
  required GpsReading gps,
  required DateTime capturedAt,
}) {
  return {
    'client_event_id': clientEventId,
    'device_uuid': deviceUuid,
    'event_type': eventType.key,
    'event_at': eventAt.toUtc().toIso8601String(),
    'latitude': gps.latitude.toString(),
    'longitude': gps.longitude.toString(),
    'accuracy_meters': gps.accuracyMeters.toStringAsFixed(2),
    'captured_at': capturedAt.toUtc().toIso8601String(),
  };
}

/// Builds the full multipart body including the selfie upload.
FormData buildEventFormData({
  required String clientEventId,
  required String deviceUuid,
  required AttendanceEventType eventType,
  required DateTime eventAt,
  required GpsReading gps,
  required DateTime capturedAt,
  required List<int> photoBytes,
}) {
  final fields = buildEventFields(
    clientEventId: clientEventId,
    deviceUuid: deviceUuid,
    eventType: eventType,
    eventAt: eventAt,
    gps: gps,
    capturedAt: capturedAt,
  );

  return FormData.fromMap({
    ...fields,
    'photo': MultipartFile.fromBytes(photoBytes, filename: 'selfie.jpg'),
  });
}