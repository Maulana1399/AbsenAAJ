import 'package:absen_aaj/core/auth/auth_repository.dart';
import 'package:absen_aaj/core/errors/app_exception.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDio extends Mock implements Dio {}

void main() {
  late MockDio dio;
  late ApiAuthRepository repository;

  setUp(() {
    dio = MockDio();
    repository = ApiAuthRepository(dio);
  });

  test('login success returns token and user', () async {
    when(() => dio.post('/api/v1/auth/login', data: any(named: 'data')))
        .thenAnswer((_) async => Response(
              requestOptions: RequestOptions(path: '/x'),
              statusCode: 200,
              data: {
                'data': {
                  'id': 1,
                  'name': 'Budi',
                  'email': 'budi@example.com',
                  'role': 'EMPLOYEE',
                  'is_active': true,
                  'token': 'token-abc',
                  'user': {
                    'id': 1,
                    'name': 'Budi',
                    'email': 'budi@example.com',
                    'role': 'EMPLOYEE',
                    'is_active': true,
                  },
                },
              },
            ));

    final result = await repository.login('budi@example.com', 'password');

    expect(result.token, 'token-abc');
    expect(result.user.name, 'Budi');
    expect(result.user.email, 'budi@example.com');
  });

  test('login failure maps INVALID_CREDENTIALS to AppException', () {
    when(() => dio.post(any(), data: any(named: 'data'))).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(
          requestOptions: RequestOptions(path: '/x'),
          statusCode: 401,
          data: {'message': 'Email atau password salah.', 'code': 'INVALID_CREDENTIALS'},
        ),
      ),
    );

    expect(
      () => repository.login('a@b.c', 'wrong'),
      throwsA(isA<AppException>().having((e) => e.message, 'message', contains('Email atau password salah'))),
    );
  });

  test('me returns the authenticated user', () async {
    when(() => dio.get('/api/v1/me')).thenAnswer(
      (_) async => Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 200,
        data: {
          'data': {'id': 2, 'name': 'Siti', 'email': 'siti@example.com', 'role': 'EMPLOYEE', 'is_active': true},
        },
      ),
    );

    final user = await repository.me();

    expect(user.id, 2);
    expect(user.name, 'Siti');
  });
}