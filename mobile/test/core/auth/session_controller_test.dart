import 'package:absen_aaj/core/auth/auth_repository.dart';
import 'package:absen_aaj/core/auth/cached_user_store_provider.dart';
import 'package:absen_aaj/core/auth/session_controller.dart';
import 'package:absen_aaj/core/auth/token_store.dart';
import 'package:absen_aaj/core/errors/app_exception.dart';
import 'package:absen_aaj/core/models/user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fakes.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late ProviderContainer container;
  late FakeTokenStore tokenStore;
  late FakeCachedUserStore cachedUserStore;
  late MockAuthRepository authRepository;

  setUp(() {
    tokenStore = FakeTokenStore();
    cachedUserStore = FakeCachedUserStore();
    authRepository = MockAuthRepository();
    container = ProviderContainer(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokenStore),
        cachedUserStoreProvider.overrideWithValue(cachedUserStore),
        authRepositoryProvider.overrideWithValue(authRepository),
      ],
    );
  });

  tearDown(() => container.dispose());

  User makeUser() => const User(
        id: 1,
        name: 'Budi',
        email: 'budi@example.com',
        role: 'EMPLOYEE',
        isActive: true,
      );

  group('SessionController', () {
    test('login success saves token and authenticates', () async {
      when(() => authRepository.login('a', 'b')).thenAnswer(
        (_) async => AuthResult(token: 'tok-1', user: makeUser()),
      );

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.login('a', 'b');

      expect(container.read(sessionControllerProvider).isAuthenticated, isTrue);
      expect(container.read(sessionControllerProvider).user?.name, 'Budi');
      expect(tokenStore.token, 'tok-1');
      expect(tokenStore.writes, ['tok-1']);
      expect(cachedUserStore.user?.email, 'budi@example.com');
      expect(cachedUserStore.saves, 1);
    });

    test('login failure keeps the user unauthenticated and does not save token',
        () async {
      when(() => authRepository.login(any(), any())).thenThrow(
        const AppException('Email atau password salah.',
            code: 'INVALID_CREDENTIALS'),
      );

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.login('a', 'bad');

      final state = container.read(sessionControllerProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.message, 'Email atau password salah.');
      expect(tokenStore.token, isNull);
    });

    test('logout clears the token', () async {
      when(() => authRepository.login(any(), any())).thenAnswer(
          (_) async => AuthResult(token: 'tok-1', user: makeUser()));
      when(() => authRepository.logout()).thenAnswer((_) async {});

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.login('a', 'b');
      await controller.logout();

      expect(container.read(sessionControllerProvider).status,
          SessionStatus.unauthenticated);
      expect(tokenStore.token, isNull);
      expect(tokenStore.clears, 1);
      expect(cachedUserStore.user, isNull);
    });

    test('restore keeps valid session from stored token', () async {
      tokenStore.token = 'tok-1';
      when(() => authRepository.me()).thenAnswer((_) async => makeUser());

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.restore();

      expect(container.read(sessionControllerProvider).isAuthenticated, isTrue);
      expect(container.read(sessionControllerProvider).user?.email,
          'budi@example.com');
      expect(cachedUserStore.user?.email, 'budi@example.com');
    });

    test('restore offline uses the previously cached session', () async {
      tokenStore.token = 'tok-1';
      cachedUserStore.user = makeUser();
      when(() => authRepository.me())
          .thenThrow(const NetworkException());

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.restore();

      final state = container.read(sessionControllerProvider);
      expect(state.isAuthenticated, isTrue);
      expect(state.user?.email, 'budi@example.com');
      expect(tokenStore.token, 'tok-1');
      expect(tokenStore.clears, 0);
    });

    test('restore offline without a verified cached user does not log in',
        () async {
      tokenStore.token = 'tok-1';
      when(() => authRepository.me())
          .thenThrow(const NetworkException());

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.restore();

      final state = container.read(sessionControllerProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.status, SessionStatus.error);
      expect(state.message, contains('login saat koneksi tersedia'));
      expect(tokenStore.token, 'tok-1');
    });

    test('restore with an expired token clears token and cached user', () async {
      tokenStore.token = 'tok-1';
      cachedUserStore.user = makeUser();
      when(() => authRepository.me())
          .thenThrow(const SessionExpiredException());

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.restore();

      expect(container.read(sessionControllerProvider).isAuthenticated, isFalse);
      expect(tokenStore.token, isNull);
      expect(cachedUserStore.user, isNull);
    });

    test('new login offline fails without cached credentials', () async {
      when(() => authRepository.login(any(), any()))
          .thenThrow(const NetworkException());

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.login('a', 'b');

      final state = container.read(sessionControllerProvider);
      expect(state.isAuthenticated, isFalse);
      expect(state.message, contains('Login memerlukan koneksi internet'));
      expect(tokenStore.token, isNull);
    });

    test('restore without token goes to login screen', () async {
      final controller = container.read(sessionControllerProvider.notifier);
      await controller.restore();

      expect(container.read(sessionControllerProvider).status,
          SessionStatus.unauthenticated);
    });

    test('handleUnauthorized (401) clears the token', () async {
      tokenStore.token = 'tok-1';
      when(() => authRepository.login(any(), any())).thenAnswer(
          (_) async => AuthResult(token: 'tok-1', user: makeUser()));

      final controller = container.read(sessionControllerProvider.notifier);
      await controller.login('a', 'b');
      expect(container.read(sessionControllerProvider).isAuthenticated, isTrue);

      await controller.handleUnauthorized();

      final state = container.read(sessionControllerProvider);
      expect(state.status, SessionStatus.unauthenticated);
      expect(state.message, isNotNull);
      expect(tokenStore.token, isNull);
      expect(cachedUserStore.user, isNull);
    });
  });
}
