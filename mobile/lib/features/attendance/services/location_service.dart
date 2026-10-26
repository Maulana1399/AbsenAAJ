import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/errors/app_exception.dart';
import '../domain/attendance_models.dart';

/// Abstraksi pengambilan lokasi agar mudah diuji.
abstract interface class LocationService {
  Future<GpsReading> getLocation();
}

class GeolocatorLocationService implements LocationService {
  @override
  Future<GpsReading> getLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw const LocationException(
        'GPS belum aktif. Silakan aktifkan lokasi kemudian coba lagi.',
        LocationDenial.serviceDisabled,
        code: 'LOCATION_SERVICE_DISABLED',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const LocationException(
        'Aplikasi membutuhkan akses lokasi untuk melakukan absensi.',
        LocationDenial.denied,
        code: 'LOCATION_PERMISSION_DENIED',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Akses lokasi ditolak secara permanen. '
        'Silakan buka pengaturan dan izinkan akses lokasi.',
        LocationDenial.permanentlyDenied,
        code: 'LOCATION_PERMISSION_FOREVER',
      );
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
      ),
    );

    return GpsReading(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
    );
  }
}

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);
