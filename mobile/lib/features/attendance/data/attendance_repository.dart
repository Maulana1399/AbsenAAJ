import '../../../core/api/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_failure.dart';
import '../../../core/errors/app_exception.dart';
import '../domain/attendance_models.dart';
import '../domain/attendance_payload.dart';

abstract interface class AttendanceRepository {
  Future<AttendanceEvent> submitEvent({
    required String clientEventId,
    required String deviceUuid,
    required AttendanceEventType eventType,
    required DateTime eventAt,
    required GpsReading gps,
    required DateTime capturedAt,
    required List<int> photoBytes,
  });

  Future<DeviceInfo> registerDevice({
    required String deviceUuid,
    String? manufacturer,
    String? model,
    String? appVersion,
  });

  Future<List<AttendanceEvent>> history({DateTime? from, DateTime? to});
}

class ApiAttendanceRepository implements AttendanceRepository {
  ApiAttendanceRepository(this._dio);

  final Dio _dio;

  @override
  Future<AttendanceEvent> submitEvent({
    required String clientEventId,
    required String deviceUuid,
    required AttendanceEventType eventType,
    required DateTime eventAt,
    required GpsReading gps,
    required DateTime capturedAt,
    required List<int> photoBytes,
  }) async {
    try {
      final formData = buildEventFormData(
        clientEventId: clientEventId,
        deviceUuid: deviceUuid,
        eventType: eventType,
        eventAt: eventAt,
        gps: gps,
        capturedAt: capturedAt,
        photoBytes: photoBytes,
      );

      final response = await _dio.post(
        '/api/v1/attendance/events',
        data: formData,
      );

      return _eventFromResponse(response);
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  @override
  Future<DeviceInfo> registerDevice({
    required String deviceUuid,
    String? manufacturer,
    String? model,
    String? appVersion,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/devices/register',
        data: {
          'device_uuid': deviceUuid,
          'platform': 'android',
          if (manufacturer != null) 'manufacturer': manufacturer,
          if (model != null) 'model': model,
          if (appVersion != null) 'app_version': appVersion,
        },
      );

      final device = (response.data as Map<String, dynamic>)['data']?['device'];
      if (device is Map<String, dynamic>) {
        return DeviceInfo.fromJson(device);
      }
      throw const AppException(
        'Respons pendaftaran device tidak dikenali.',
        code: 'BAD_RESPONSE',
      );
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  @override
  Future<List<AttendanceEvent>> history({DateTime? from, DateTime? to}) async {
    try {
      final query = <String, dynamic>{};
      if (from != null) query['from'] = _dateParam(from);
      if (to != null) query['to'] = _dateParam(to);

      final response = await _dio.get(
        '/api/v1/attendance',
        queryParameters: query.isEmpty ? null : query,
      );

      final list = (response.data as Map<String, dynamic>)['data'];
      if (list is! List) return const [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(AttendanceEvent.fromJson)
          .toList();
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  AttendanceEvent _eventFromResponse(Response<dynamic> response) {
    final event = (response.data as Map<String, dynamic>)['data'];
    if (event is Map<String, dynamic>) {
      return AttendanceEvent.fromJson(event);
    }
    throw const AppException(
      'Respons absensi tidak dikenali.',
      code: 'BAD_RESPONSE',
    );
  }

  String _dateParam(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
  (ref) => ApiAttendanceRepository(ref.watch(apiClientProvider)),
);
