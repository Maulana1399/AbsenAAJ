import 'package:absen_aaj/features/attendance/data/attendance_sync_api.dart';
import 'package:absen_aaj/features/attendance/domain/attendance_models.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late ApiAttendanceSyncApi api;

  setUp(() {
    dio = MockDio();
    api = ApiAttendanceSyncApi(dio);
  });

  Map<String, dynamic> eventBody({
    int id = 1,
    String clientEventId = 'client-1',
    String eventType = 'CHECK_IN',
    String status = 'ON_TIME',
  }) {
    return {
      'data': {
        'id': id,
        'client_event_id': clientEventId,
        'event_type': eventType,
        'status': status,
        'event_at': '2026-10-06T08:30:00.000Z',
        'server_received_at': '2026-10-06T08:30:05.000Z',
      },
    };
  }

  Future<AttendanceSyncResponse> submit() => api.submit(
    clientEventId: 'client-1',
    deviceUuid: 'device-1',
    eventType: AttendanceEventType.checkIn,
    eventAt: DateTime(2026, 10, 6, 8, 30),
    gps: const GpsReading(
      latitude: -5.1477,
      longitude: 119.4326,
      accuracyMeters: 20,
    ),
    capturedAt: DateTime(2026, 10, 6, 8, 29),
    photoBytes: [1, 2, 3],
  );

  void respond(int status, Map<String, dynamic> body, {Headers? headers}) {
    when(() => dio.post(any(), data: any(named: 'data'))).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: status,
        data: body,
        headers: headers,
      ),
    );
  }

  test('accepts a 201 creation response', () async {
    respond(201, eventBody());

    final result = await submit();

    expect(result.statusCode, 201);
    expect(result.event.id, 1);
    expect(result.event.clientEventId, 'client-1');
    expect(result.event.eventType, 'CHECK_IN');
    expect(result.event.status, 'ON_TIME');
  });

  test('accepts a 200 replay response', () async {
    respond(200, eventBody(id: 9, status: 'LATE'));

    final result = await submit();

    expect(result.statusCode, 200);
    expect(result.event.id, 9);
    expect(result.event.status, 'LATE');
  });

  test('rejects a success status without a valid event body', () async {
    respond(200, {
      'data': {'id': 1},
    });

    await expectLater(
      submit(),
      throwsA(
        isA<AttendanceSyncApiException>().having(
          (e) => e.isProtocol,
          'isProtocol',
          isTrue,
        ),
      ),
    );
  });

  test('rejects an ack for a different client_event_id', () async {
    respond(201, eventBody(clientEventId: 'other-id'));

    await expectLater(
      submit(),
      throwsA(
        isA<AttendanceSyncApiException>().having(
          (e) => e.code,
          'code',
          'SYNC_BAD_RESPONSE',
        ),
      ),
    );
  });

  test('rejects an ack for a different event type', () async {
    respond(201, eventBody(eventType: 'CHECK_OUT'));

    await expectLater(
      submit(),
      throwsA(
        isA<AttendanceSyncApiException>().having(
          (e) => e.isProtocol,
          'isProtocol',
          isTrue,
        ),
      ),
    );
  });

  test('maps a backend error code, status and message', () async {
    when(() => dio.post(any(), data: any(named: 'data'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 422,
          data: {'code': 'OUTSIDE_GEOFENCE', 'message': 'outside'},
        ),
      ),
    );

    await expectLater(
      submit(),
      throwsA(
        isA<AttendanceSyncApiException>()
            .having((e) => e.statusCode, 'statusCode', 422)
            .having((e) => e.code, 'code', 'OUTSIDE_GEOFENCE')
            .having((e) => e.isNetwork, 'isNetwork', isFalse),
      ),
    );
  });

  test('classifies connection failures as network errors', () async {
    when(() => dio.post(any(), data: any(named: 'data'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        type: DioExceptionType.connectionError,
      ),
    );

    await expectLater(
      submit(),
      throwsA(
        isA<AttendanceSyncApiException>().having(
          (e) => e.isNetwork,
          'isNetwork',
          isTrue,
        ),
      ),
    );
  });

  test('parses Retry-After seconds on a 429 response', () async {
    when(() => dio.post(any(), data: any(named: 'data'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 429,
          data: {'code': 'RATE_LIMITED', 'message': 'slow down'},
          headers: Headers.fromMap({
            'retry-after': ['120'],
          }),
        ),
      ),
    );

    await expectLater(
      submit(),
      throwsA(
        isA<AttendanceSyncApiException>()
            .having((e) => e.statusCode, 'statusCode', 429)
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 120),
            ),
      ),
    );
  });
}
