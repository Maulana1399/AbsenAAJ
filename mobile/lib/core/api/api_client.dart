import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';
import '../auth/token_store.dart';
import '../config/app_config.dart';

/// Shared Dio instance used for all API calls.
///
/// Attaches the stored bearer token to every request and, on a 401, tells
/// the session controller to wipe the session so the user is returned to the
/// login screen.
final apiClientProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.apiConnectTimeout,
      receiveTimeout: AppConfig.apiReceiveTimeout,
      contentType: 'application/json',
      headers: const {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await ref.read(tokenStoreProvider).read();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          await ref.read(sessionControllerProvider.notifier).handleUnauthorized();
        }
        handler.next(error);
      },
    ),
  );

  return dio;
});