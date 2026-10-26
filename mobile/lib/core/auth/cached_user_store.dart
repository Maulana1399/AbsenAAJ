import 'dart:convert';

import '../models/user.dart';

abstract interface class SecureValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

abstract interface class CachedUserStore {
  Future<void> save(User user);

  Future<User?> read();

  Future<void> clear();
}

class SecureCachedUserStore implements CachedUserStore {
  SecureCachedUserStore(this._values);

  static const storageKey = 'aaj_cached_user_v1';

  final SecureValueStore _values;

  @override
  Future<void> save(User user) async {
    await _values.write(storageKey, jsonEncode(user.toJson()));
  }

  @override
  Future<User?> read() async {
    final raw = await _values.read(storageKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await clear();
        return null;
      }
      return User.fromJson(decoded);
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> clear() => _values.delete(storageKey);
}
