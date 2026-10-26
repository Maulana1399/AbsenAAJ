import 'package:absen_aaj/core/errors/app_exception.dart';
import 'package:absen_aaj/features/attendance/data/attendance_repository.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late ApiAttendanceRepository repository;

  setUp(() {
    dio = MockDio();
    repository = ApiAttendanceRepository(dio);
  });

  DioException apiError(int status, Map<String, dynamic> body) {
    return DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: status,
          data: body),
    );
  }

  test(
      'submitEvent posts multipart with photo, GPS and no authoritative fields',
      () async {
    when(() => dio.post(any(), data: any(named: 'data')))
        .thenAnswer((invocation) async {
      final formData = invocation.namedArguments[#data] as FormData;
      // Assert on the actual outgoing payload.
      final fieldMap = {for (final f in formData.fields) f.key: f.value};
      expect(fieldMap['event_type'], 'CHECK_IN');
      expect(fieldMap['client_event_id'], isNotEmpty);
      expect(fieldMap.containsKey('latitude'), isTrue);
      expect(fieldMap.containsKey('accuracy_meters'), isTrue);
      expect(fieldMap.containsKey('distance_meters'), isFalse);
      expect(fieldMap.containsKey('location_valid'), isFalse);
      expect(formData.files.any((f) => f.key == 'photo'), isTrue);

      return Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 201,
        data: {
          'data': {
            'id': 1,
            'client_event_id': fieldMap['client_event_id'],
            'event_type': 'CHECK_IN',
            'status': 'ON_TIME',
            'event_at': '2026-10-06T08:30:00.000Z',
            'server_received_at': '2026-10-06T08:30:05.000Z',
            'latitude': '-5.1477',
            'longitude': '119.4326',
            'accuracy_meters': '20.00',
            'distance_meters': '0.00',
            'location_valid': true,
            'photo': {
              'id': 1,
              'mime_type': 'image/jpeg',
              'file_size': 10,
              'sha256': 'ab' * 32,
            },
          },
        },
      );
    });

    final event = await repository.submitEvent(
      clientEventId: 'uuid-1',
      deviceUuid: 'device-1',
      eventType: AttendanceEventType.checkIn,
      eventAt: DateTime(2026, 10, 6, 8, 30),
      gps: const GpsReading(
          latitude: -5.1477, longitude: 119.4326, accuracyMeters: 20),
      capturedAt: DateTime(2026, 10, 6, 8, 29),
      photoBytes: [1, 2, 3],
    );

    expect(event.status, 'ON_TIME');
    expect(event.locationValid, isTrue);
    verify(() =>
            dio.post('/api/v1/attendance/events', data: any(named: 'data')))
        .called(1);
  });

  test('submitEvent maps OUTSIDE_GEOFENCE error to AppException', () async {
    when(() => dio.post(any(), data: any(named: 'data')))
        .thenThrow(apiError(422, {'code': 'OUTSIDE_GEOFENCE', 'message': 'x'}));

    expect(
      () => repository.submitEvent(
        clientEventId: 'uuid-1',
        deviceUuid: 'device-1',
        eventType: AttendanceEventType.checkIn,
        eventAt: DateTime(2026, 10, 6, 8, 30),
        gps: const GpsReading(
            latitude: -5.1477, longitude: 119.4326, accuracyMeters: 20),
        capturedAt: DateTime(2026, 10, 6, 8, 29),
        photoBytes: [1, 2, 3],
      ),
      throwsA(isA<AppException>()
          .having((e) => e.code, 'code', 'OUTSIDE_GEOFENCE')),
    );
  });

  test('submitEvent maps network error to NetworkException', () async {
    when(() => dio.post(any(), data: any(named: 'data'))).thenThrow(
      DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError),
    );

    expect(
      () => repository.submitEvent(
        clientEventId: 'u',
        deviceUuid: 'd',
        eventType: AttendanceEventType.checkIn,
        eventAt: DateTime(2026, 10, 6, 8, 30),
        gps: const GpsReading(latitude: 1, longitude: 1, accuracyMeters: 10),
        capturedAt: DateTime(2026, 10, 6, 8, 29),
        photoBytes: [1],
      ),
      throwsA(isA<NetworkException>()),
    );
  });
}
