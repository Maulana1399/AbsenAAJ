import 'package:absen_aaj/core/auth/session_controller.dart';
import 'package:absen_aaj/core/auth/token_store.dart';
import 'package:absen_aaj/core/errors/app_exception.dart';
import 'package:absen_aaj/core/storage/device_identity.dart';
import 'package:absen_aaj/features/attendance/application/device_registration_controller.dart';
import 'package:absen_aaj/features/attendance/data/attendance_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  late ProviderContainer container;
  late FakeDeviceIdentity identity;
  late RecordingAttendanceRepository repository;
  late FakeTokenStore tokenStore;

  setUp(() {
    identity = FakeDeviceIdentity();
    repository = RecordingAttendanceRepository();
    tokenStore = FakeTokenStore();

    container = ProviderContainer(overrides: [
      deviceIdentityProvider.overrideWithValue(identity),
      attendanceRepositoryProvider.overrideWithValue(repository),
      tokenStoreProvider.overrideWithValue(tokenStore),
    ]);
  });

  tearDown(() => container.dispose());

  group('DeviceRegistrationController', () {
    test('registers device once and marks it registered', () async {
      final controller = container.read(deviceRegistrationProvider.notifier);
      await controller.ensureRegistered();

      expect(container.read(deviceRegistrationProvider).isRegistered, isTrue);
      expect(identity.marked, isTrue);
      expect(repository.registeredDevices, ['device-uuid-123']);
    });

    test('does not register again when already registered locally', () async {
      identity.registered = true;

      final controller = container.read(deviceRegistrationProvider.notifier);
      await controller.ensureRegistered();

      expect(repository.registeredDevices, isEmpty);
      expect(container.read(deviceRegistrationProvider).isRegistered, isTrue);
    });

    test('DEVICE_ALREADY_REGISTERED forces logout with a message', () async {
      repository.registerError = const AppException(
        'Device ini sudah terdaftar untuk karyawan lain.',
        code: 'DEVICE_ALREADY_REGISTERED',
      );

      final controller = container.read(deviceRegistrationProvider.notifier);
      await controller.ensureRegistered();

      final session = container.read(sessionControllerProvider);
      expect(session.status, SessionStatus.unauthenticated);
    });
  });
}