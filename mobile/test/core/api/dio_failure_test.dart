import 'package:absen_aaj/core/api/dio_failure.dart';
import 'package:absen_aaj/core/errors/app_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

void main() {
  group('mapDioException', () {
    test('connection timeout maps to NetworkException', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionTimeout,
      );

      final result = mapDioException(error);

      expect(result, isA<NetworkException>());
      expect(result.message, contains('Periksa koneksi internet'));
    });

    test('OUTSIDE_GEOFENCE code maps to friendly message', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 422,
          data: {'code': 'OUTSIDE_GEOFENCE', 'message': 'Lokasi di luar.'},
        ),
      );

      final result = mapDioException(error);

      expect(result.code, 'OUTSIDE_GEOFENCE');
      expect(result.message, contains('di luar area absensi cabang'));
    });

    test('LOCATION_LOW_ACCURACY maps correctly', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 422,
          data: {'code': 'LOCATION_LOW_ACCURACY'},
        ),
      );

      expect(mapDioException(error).message, contains('Akurasi GPS terlalu rendah'));
    });

    test('ALREADY_CHECKED_IN maps correctly', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 422,
          data: {'code': 'ALREADY_CHECKED_IN'},
        ),
      );

      expect(mapDioException(error).message, contains('sudah melakukan check-in'));
    });

    test('ALREADY_CHECKED_OUT maps correctly', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 422,
          data: {'code': 'ALREADY_CHECKED_OUT'},
        ),
      );

      expect(mapDioException(error).message, contains('sudah melakukan check-out'));
    });

    test('DEVICE_REVOKED maps correctly', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 403,
          data: {'code': 'DEVICE_REVOKED'},
        ),
      );

      expect(mapDioException(error).message, contains('telah dinonaktifkan'));
    });

    test('401 maps to SessionExpiredException', () {
      final error = DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 401,
          data: {'message': 'Unauthenticated.', 'code': 'UNAUTHENTICATED'},
        ),
      );

      expect(mapDioException(error), isA<SessionExpiredException>());
    });
  });
}