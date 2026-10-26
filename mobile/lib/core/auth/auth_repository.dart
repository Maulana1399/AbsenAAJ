import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/dio_failure.dart';
import '../errors/app_exception.dart';
import '../models/user.dart';

class AuthResult {
  const AuthResult({required this.token, required this.user});

  final String token;
  final User user;
}

abstract interface class AuthRepository {
  Future<AuthResult> login(String email, String password);
  Future<User> me();
  Future<void> logout();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._dio);

  final Dio _dio;

  @override
  Future<AuthResult> login(String email, String password) async {
    try {
      final response = await _dio.post(
        '/api/v1/auth/login',
        data: {'email': email, 'password': password},
      );
      final data = (response.data as Map<String, dynamic>)['data'];
      if (data is! Map<String, dynamic>) {
        throw const AppException('Respons login tidak dikenali.',
            code: 'BAD_RESPONSE');
      }
      final token = data['token'] as String? ?? '';
      final user = data['user'] as Map<String, dynamic>?;
      if (token.isEmpty || user == null) {
        throw const AppException('Respons login tidak dikenali.',
            code: 'BAD_RESPONSE');
      }
      return AuthResult(token: token, user: User.fromJson(user));
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  @override
  Future<User> me() async {
    try {
      final response = await _dio.get('/api/v1/me');
      final data = (response.data as Map<String, dynamic>)['data'];
      if (data is! Map<String, dynamic>) {
        throw const AppException('Respons profil tidak dikenali.',
            code: 'BAD_RESPONSE');
      }
      return User.fromJson(data);
    } on DioException catch (error) {
      throw mapDioException(error);
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _dio.post('/api/v1/auth/logout');
    } on DioException {
      // Local session is cleared regardless of the server result.
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ApiAuthRepository(ref.watch(apiClientProvider)),
);
