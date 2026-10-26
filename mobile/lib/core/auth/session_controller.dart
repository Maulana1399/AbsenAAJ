import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../errors/app_exception.dart';
import '../models/user.dart';
import 'auth_repository.dart';
import 'cached_user_store_provider.dart';
import 'token_store.dart';

enum SessionStatus { initial, loading, authenticated, unauthenticated, error }

class SessionState {
  const SessionState({
    this.status = SessionStatus.initial,
    this.user,
    this.message,
  });

  final SessionStatus status;
  final User? user;
  final String? message;

  bool get isAuthenticated => status == SessionStatus.authenticated;
}

/// Owns the login session. The token lives in secure storage; the state here
/// only reflects whether we are authenticated and who the user is.
class SessionController extends StateNotifier<SessionState> {
  SessionController(this._ref) : super(const SessionState());

  final Ref _ref;

  Future<void> restore() async {
    final token = await _ref.read(tokenStoreProvider).read();
    if (token == null || token.isEmpty) {
      state = const SessionState(status: SessionStatus.unauthenticated);
      return;
    }

    state = const SessionState(status: SessionStatus.loading);
    try {
      final user = await _ref.read(authRepositoryProvider).me();
      await _saveCachedUser(user);
      state = SessionState(status: SessionStatus.authenticated, user: user);
    } on SessionExpiredException {
      await _clearLocalSession();
      state = const SessionState(
        status: SessionStatus.unauthenticated,
        message: 'Sesi berakhir. Silakan login kembali.',
      );
    } on NetworkException {
      // Keep the token: the server is unreachable, not the session invalid.
      // A previously verified profile lets the app open offline.
      final cachedUser = await _readCachedUser();
      if (cachedUser != null) {
        state = SessionState(
          status: SessionStatus.authenticated,
          user: cachedUser,
        );
        return;
      }
      state = const SessionState(
        status: SessionStatus.error,
        message:
            'Tidak dapat memuat sesi tersimpan. Silakan login saat koneksi tersedia.',
      );
    } on AppException catch (error) {
      await _clearLocalSession();
      state = SessionState(status: SessionStatus.unauthenticated, message: error.message);
    }
  }

  Future<void> login(String email, String password) async {
    state = const SessionState(status: SessionStatus.loading);
    try {
      final result = await _ref.read(authRepositoryProvider).login(email, password);
      await _ref.read(tokenStoreProvider).write(result.token);
      await _saveCachedUser(result.user);
      state = SessionState(status: SessionStatus.authenticated, user: result.user);
    } on AppException catch (error) {
      final message = error is NetworkException
          ? 'Tidak dapat terhubung ke server. Login memerlukan koneksi internet.'
          : error.message;
      state = SessionState(status: SessionStatus.unauthenticated, message: message);
    }
  }

  Future<void> logout() async {
    await _ref.read(authRepositoryProvider).logout();
    await _clearLocalSession();
    state = const SessionState(status: SessionStatus.unauthenticated);
  }

  Future<void> handleUnauthorized() async {
    await _clearLocalSession();
    state = const SessionState(
      status: SessionStatus.unauthenticated,
      message: 'Sesi berakhir. Silakan login kembali.',
    );
  }

  Future<void> forceLogout({String message = 'Terjadi masalah. Silakan login kembali.'}) async {
    await _ref.read(authRepositoryProvider).logout();
    await _clearLocalSession();
    state = SessionState(status: SessionStatus.unauthenticated, message: message);
  }

  Future<void> _saveCachedUser(User user) async {
    try {
      await _ref.read(cachedUserStoreProvider).save(user);
    } catch (_) {
      // Caching is best-effort; a storage failure must not block login.
    }
  }

  Future<User?> _readCachedUser() async {
    try {
      return await _ref.read(cachedUserStoreProvider).read();
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearLocalSession() async {
    await _ref.read(tokenStoreProvider).clear();
    try {
      await _ref.read(cachedUserStoreProvider).clear();
    } catch (_) {
      // Best-effort: the token is already gone.
    }
  }
}

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(ref),
);