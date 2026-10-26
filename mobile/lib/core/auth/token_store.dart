import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../errors/app_exception.dart';

/// Secure wrapper around the access token.
///
/// The token is never stored in plain SharedPreferences and never logged.
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore(this._storage);

  static const _tokenKey = 'aaj_access_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    try {
      return await _storage.read(key: _tokenKey);
    } catch (_) {
      throw const AppException(
        'Gagal membaca penyimpanan aman.',
        code: 'SECURE_STORAGE_READ',
      );
    }
  }

  @override
  Future<void> write(String token) async {
    try {
      await _storage.write(key: _tokenKey, value: token);
    } catch (_) {
      throw const AppException(
        'Gagal menyimpan sesi.',
        code: 'SECURE_STORAGE_WRITE',
      );
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      // Best-effort: a failing delete should not block logout.
    }
  }
}

final tokenStoreProvider = Provider<TokenStore>(
  (ref) => SecureTokenStore(const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  )),
);