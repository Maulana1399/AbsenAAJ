import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/navigation/app_navigator.dart';
import '../domain/attendance_models.dart';
import '../presentation/selfie_capture_page.dart';

/// Abstraksi kamera selfie agar mudah diuji.
abstract interface class CameraService {
  Future<SelfieResult?> capture();
}

class InAppCameraService implements CameraService {
  @override
  Future<SelfieResult?> capture() async {
    final permission = await Permission.camera.request();
    if (!permission.isGranted) {
      throw const CameraException(
        'Akses kamera diperlukan untuk mengambil foto selfie.',
        code: 'CAMERA_PERMISSION_DENIED',
      );
    }

    final navigator = appNavigatorKey.currentState;
    if (navigator == null) {
      throw const CameraException('Kamera tidak tersedia.');
    }

    final List<int>? bytes = await navigator.push<List<int>>(
      MaterialPageRoute(builder: (_) => const SelfieCapturePage()),
    );

    if (bytes == null) {
      return null; // dibatalkan pengguna
    }

    return SelfieResult(bytes: bytes, capturedAt: DateTime.now());
  }
}

final cameraServiceProvider = Provider<CameraService>(
  (ref) => InAppCameraService(),
);
