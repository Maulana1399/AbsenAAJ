import 'package:dio/dio.dart';

import '../errors/app_exception.dart';
import '../errors/error_mapper.dart';

/// Converts any [DioException] into an [AppException] with a friendly message.
///
/// The backend error shape is `{ "message": ..., "code": "SOME_CODE", ... }`.
/// Client code is never used as a source of truth for attendance decisions,
/// it only selects a translated message.
AppException mapDioException(DioException error) {
  if (error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.connectionError) {
    return const NetworkException();
  }

  final response = error.response;
  if (response == null) {
    return const NetworkException();
  }

  final status = response.statusCode ?? 0;
  final data = response.data;

  final String? code = (data is Map) ? (data['code'] as String?) : null;
  final String? serverMessage =
      (data is Map) ? (data['message'] as String?) : null;

  if (status == 401 &&
      code != 'INVALID_CREDENTIALS' &&
      code != 'ACCOUNT_INACTIVE') {
    return const SessionExpiredException();
  }

  final String message =
      code != null && code.isNotEmpty ? apiErrorCodeToMessage(code) : '';
  if (message.isNotEmpty) {
    return AppException(message, code: code ?? 'API_ERROR', original: error);
  }

  if (status >= 500) {
    return const AppException(
      'Terjadi kesalahan pada server. Silakan coba lagi.',
      code: 'SERVER_ERROR',
    );
  }

  return AppException(
    serverMessage ?? 'Terjadi kesalahan. Silakan coba lagi.',
    code: code ?? 'HTTP_$status',
    original: error,
  );
}
