import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/storage/device_identity.dart';
import '../data/attendance_repository.dart';

enum DeviceRegistrationPhase { idle, registering, registered, failed }

class DeviceRegistrationState {
  const DeviceRegistrationState({
    this.phase = DeviceRegistrationPhase.idle,
    this.deviceUuid,
    this.message,
  });

  final DeviceRegistrationPhase phase;
  final String? deviceUuid;
  final String? message;

  bool get isRegistered => phase == DeviceRegistrationPhase.registered;
}

/// Ensures the current device is registered on the backend.
///
/// Registration is idempotent: registering the same device again simply
/// refreshes `last_seen_at`. When the backend considers the device unusable
/// (owned by another employee / revoked) the user is logged out with a clear
/// message instead of retrying endlessly.
class DeviceRegistrationController
    extends StateNotifier<DeviceRegistrationState> {
  DeviceRegistrationController(this._ref)
      : super(const DeviceRegistrationState());

  final Ref _ref;

  Future<void> ensureRegistered() async {
    final identity = _ref.read(deviceIdentityProvider);

    if (await identity.isRegistered()) {
      state = DeviceRegistrationState(
        phase: DeviceRegistrationPhase.registered,
        deviceUuid: await identity.uuid(),
      );
      return;
    }

    final uuid = await identity.uuid();
    state = DeviceRegistrationState(
      phase: DeviceRegistrationPhase.registering,
      deviceUuid: uuid,
    );

    try {
      await _ref.read(attendanceRepositoryProvider).registerDevice(
            deviceUuid: uuid,
          );
      await identity.markRegistered();
      state = DeviceRegistrationState(
        phase: DeviceRegistrationPhase.registered,
        deviceUuid: uuid,
      );
    } on AppException catch (error) {
      if (error.code == 'DEVICE_ALREADY_REGISTERED' ||
          error.code == 'DEVICE_REVOKED') {
        await _ref
            .read(sessionControllerProvider.notifier)
            .forceLogout(message: error.message);
        return;
      }
      state = DeviceRegistrationState(
        phase: DeviceRegistrationPhase.failed,
        deviceUuid: uuid,
        message: error.message,
      );
    }
  }
}

final deviceRegistrationProvider = StateNotifierProvider<
    DeviceRegistrationController, DeviceRegistrationState>(
  (ref) => DeviceRegistrationController(ref),
);