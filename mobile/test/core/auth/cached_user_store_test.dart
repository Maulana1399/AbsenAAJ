import 'dart:convert';

import 'package:absen_aaj/core/auth/cached_user_store.dart';
import 'package:absen_aaj/core/models/user.dart';
import 'package:test/test.dart';

void main() {
  late _InMemorySecureValues values;
  late SecureCachedUserStore store;

  setUp(() {
    values = _InMemorySecureValues();
    store = SecureCachedUserStore(values);
  });

  const user = User(
    id: 7,
    name: 'Budi',
    email: 'budi@example.com',
    role: 'EMPLOYEE',
    isActive: true,
    employee: EmployeeBrief(
      id: 70,
      employeeNumber: 'AAJ-070',
      name: 'Budi',
      status: 'ACTIVE',
    ),
  );

  test('saves and restores the last user profile', () async {
    await store.save(user);

    final restored = await store.read();

    expect(restored, isNotNull);
    expect(restored!.id, 7);
    expect(restored.name, 'Budi');
    expect(restored.email, 'budi@example.com');
    expect(restored.employee?.id, 70);
    expect(restored.employee?.employeeNumber, 'AAJ-070');
  });

  test('survives a new store instance using the same secure backing', () async {
    await store.save(user);

    final reopened = SecureCachedUserStore(values);

    expect((await reopened.read())?.email, 'budi@example.com');
  });

  test('replaces the previous profile without storing secrets', () async {
    await store.save(user);
    await store.save(
      const User(
        id: 8,
        name: 'Siti',
        email: 'siti@example.com',
        role: 'EMPLOYEE',
        isActive: true,
      ),
    );

    expect((await store.read())?.id, 8);

    final raw = values.data[SecureCachedUserStore.storageKey];
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;

    expect(decoded.containsKey('password'), isFalse);
    expect(decoded.containsKey('token'), isFalse);
    expect(decoded.containsKey('access_token'), isFalse);
    expect(decoded['email'], 'siti@example.com');
  });

  test('returns null and clears a corrupt cached profile', () async {
    values.data[SecureCachedUserStore.storageKey] = '{not-json';

    expect(await store.read(), isNull);
    expect(values.data, isNot(contains(SecureCachedUserStore.storageKey)));
  });

  test('clear removes the cached profile', () async {
    await store.save(user);
    await store.clear();

    expect(await store.read(), isNull);
  });
}

class _InMemorySecureValues implements SecureValueStore {
  final data = <String, String>{};

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }
}
