import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Stable, persisted Android device identifier.
///
/// Generated once on first run and stored in secure storage, so it does not
/// change between app launches. Used as `device_uuid` for device registration
/// and attendance requests.
abstract interface class DeviceIdentity {
  Future<String> uuid();
  Future<bool> isRegistered();
  Future<void> markRegistered();
  Future<void> resetRegistration();
}

class SecureDeviceIdentity implements DeviceIdentity {
  SecureDeviceIdentity(this._storage);

  static const _uuidKey = 'aaj_device_uuid';
  static const _registeredKey = 'aaj_device_registered_v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String> uuid() async {
    final existing = await _storage.read(key: _uuidKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final generated = const Uuid().v4();
    await _storage.write(key: _uuidKey, value: generated);
    return generated;
  }

  @override
  Future<bool> isRegistered() async {
    return await _storage.read(key: _registeredKey) == '1';
  }

  @override
  Future<void> markRegistered() async {
    await _storage.write(key: _registeredKey, value: '1');
  }

  @override
  Future<void> resetRegistration() async {
    await _storage.delete(key: _registeredKey);
  }
}

final deviceIdentityProvider = Provider<DeviceIdentity>(
  (ref) => SecureDeviceIdentity(const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  )),
);