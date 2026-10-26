import 'dart:io';

import 'package:dio/dio.dart';

import '../domain/attendance_models.dart';
import '../domain/attendance_payload.dart';

class AttendanceSyncResponse {
  const AttendanceSyncResponse({required this.statusCode, required this.event});

  final int statusCode;
  final AttendanceEvent event;
}

class AttendanceSyncApiException implements Exception {
  const AttendanceSyncApiException({
    required this.message,
    this.statusCode,
    this.code,
    this.retryAfter,
    this.isNetwork = false,
    this.isProtocol = false,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final Duration? retryAfter;
  final bool isNetwork;
  final bool isProtocol;

  @override
  String toString() =>
      'AttendanceSyncApiException($code, HTTP $statusCode): $message';
}

abstract interface class AttendanceSyncApi {
  Future<AttendanceSyncResponse> submit({
    required String clientEventId,
    required String deviceUuid,
    required AttendanceEventType eventType,
    required DateTime eventAt,
    required GpsReading gps,
    required DateTime capturedAt,
    required List<int> photoBytes,
  });
}

class ApiAttendanceSyncApi implements AttendanceSyncApi {
  ApiAttendanceSyncApi(this._dio);

  final Dio _dio;

  @override
  Future<AttendanceSyncResponse> submit({
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
      final status = response.statusCode;
      if (status != 200 && status != 201) {
        final data = response.data;
        throw AttendanceSyncApiException(
          statusCode: status,
          code: data is Map ? data['code'] as String? : null,
          message: data is Map
              ? data['message'] as String? ??
                    'Server menolak absensi (HTTP ${status ?? '?'}).'
              : 'Server menolak absensi (HTTP ${status ?? '?'}).',
          retryAfter: _parseRetryAfter(response.headers),
        );
      }

      final payload = response.data;
      final raw = payload is Map ? payload['data'] : null;
      if (raw is! Map) {
        throw const AttendanceSyncApiException(
          code: 'SYNC_BAD_RESPONSE',
          message: 'Respons absensi tidak berisi data event.',
          isProtocol: true,
        );
      }

      final event = AttendanceEvent.fromJson(Map<String, dynamic>.from(raw));
      if (event.id <= 0 ||
          event.clientEventId != clientEventId ||
          event.eventType != eventType.key ||
          event.status.trim().isEmpty) {
        throw const AttendanceSyncApiException(
          code: 'SYNC_BAD_RESPONSE',
          message: 'Respons absensi tidak valid.',
          isProtocol: true,
        );
      }

      return AttendanceSyncResponse(statusCode: status!, event: event);
    } on DioException catch (error) {
      throw _fromDio(error);
    } on AttendanceSyncApiException {
      rethrow;
    } catch (_) {
      throw const AttendanceSyncApiException(
        code: 'SYNC_BAD_RESPONSE',
        message: 'Respons absensi tidak dapat dibaca.',
        isProtocol: true,
      );
    }
  }

  AttendanceSyncApiException _fromDio(DioException error) {
    final response = error.response;
    final status = response?.statusCode;
    final data = response?.data;
    final code = data is Map ? data['code'] as String? : null;
    final serverMessage = data is Map ? data['message'] as String? : null;

    final network =
        response == null &&
        (error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.sendTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.badCertificate ||
            error.type == DioExceptionType.unknown);

    return AttendanceSyncApiException(
      statusCode: status,
      code: code ?? (network ? 'NETWORK_ERROR' : null),
      message: network
          ? 'Tidak dapat terhubung ke server. Absensi akan dicoba lagi.'
          : serverMessage ?? 'Server menolak absensi (HTTP ${status ?? '?'}).',
      retryAfter: _parseRetryAfter(response?.headers),
      isNetwork: network,
    );
  }

  Duration? _parseRetryAfter(Headers? headers) {
    final raw = headers?.value('retry-after');
    if (raw == null || raw.trim().isEmpty) return null;

    final seconds = int.tryParse(raw.trim());
    if (seconds != null) {
      return Duration(seconds: seconds < 0 ? 0 : seconds);
    }

    try {
      final at = HttpDate.parse(raw);
      final delay = at.difference(DateTime.now());
      return delay.isNegative ? Duration.zero : delay;
    } catch (_) {
      return null;
    }
  }
}
