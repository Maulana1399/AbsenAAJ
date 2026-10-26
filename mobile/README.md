# Absen AAJ — Employee Mobile App (Flutter)

Aplikasi Android untuk karyawan (online MVP). Terhubung ke API Laravel di
`/api/v1` (lihat backend `Absen AAJ` pada repo yang sama).

Fiturnya:

- Login / logout (token disimpan di Secure Storage)
- Restore sesi via `GET /api/v1/me`
- Registrasi device otomatis (`POST /api/v1/devices/register`)
- Beranda dengan status hari ini (dari server)
- Check-in / check-out dengan **selfie + GPS**
  - Preview selfie → retake → use
  - Geofence & akurasi divalidasi **server**, client hanya mengirim data mentah
- Riwayat absensi (hanya milik sendiri) dengan filter tanggal
- 401 otomatis → kembali ke login

## Prasyarat

- Flutter >= 3.44 (Dart SDK 3.12+)
- Android SDK (compileSdk diset otomatis oleh Flutter)

## Menjalankan

```bash
cd mobile
flutter pub get
flutter build apk --debug
```

APK hasil build:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## Konfigurasi API base URL

Base URL tidak di-hardcode. Atur saat run/build dengan `--dart-define`:

```bash
# Android emulator (host = 10.0.2.2)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# Physical device di LAN yang sama dengan server Laravel
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
flutter build apk --debug --dart-define=API_BASE_URL=http://192.168.1.20:8000
```

Catatan penting:

- **Jangan** gunakan `http://127.0.0.1:8000` untuk physical device karena itu
  menunjuk ke HP itu sendiri, bukan server.
- Untuk physical device, backend harus dapat diakses dari IP LAN komputer
  server (misal `php artisan serve --host=0.0.0.0 --port=8000`).
- Development memakai `http://` (manifest mengizinkan cleartext untuk dev).
  Untuk produksi gunakan `https://` dan matikan `usesCleartextTraffic`.

Default bila tanpa `--dart-define`: `http://10.0.2.2:8000` (emulator).

## Arsitektur

```text
lib/
├── main.dart                 # App root + navigator key
├── core/
│   ├── api/                  # Dio client, interceptor token + 401
│   ├── auth/                 # TokenStore, AuthRepository, SessionController, AuthGate
│   ├── config/               # AppConfig (API_BASE_URL, timeout)
│   ├── errors/               # AppException + mapping error API -> pesan
│   ├── models/               # User/Employee brief
│   ├── navigation/           # App-wide navigator key
│   ├── storage/              # DeviceIdentity (uuid stabil di secure storage)
│   └── format/               # helper format tanggal/jarak/status
└── features/
    ├── auth/                 # Login page
    ├── home/                 # Beranda + status hari ini + tombol absensi
    ├── attendance/           # repository, GPS, kamera selfie, controller submit
    │   └── data/local/       # Fondasi SQLite outbox + penyimpanan foto privat
    └── history/              # Riwayat + filter
```

State management: **Riverpod** (`StateNotifier`/`Provider`). Semua dependensi
external (Dio, geolocator, camera, secure storage) diakses lewat provider agar
mudah di-*override* di test.

## Tests

```bash
flutter analyze
flutter test
```

Test mencakup: auth (success/fail/token/401→logout), payload check-in/check-out
(tanpa `distance_meters`/`location_valid`, UUID berbeda per event, multipart
photo, GPS fields), mapping error (`OUTSIDE_GEOFENCE`, `LOCATION_LOW_ACCURACY`,
`ALREADY_CHECKED_IN`, `ALREADY_CHECKED_OUT`, `DEVICE_REVOKED`), dan perilaku
state (submit sedang berlangsung men-disable tombol).

## Security notes

- Token disimpan di Secure Storage (EncryptedSharedPreferences), tidak di log.
- `employee_id`, `status`, `distance_meters`, `location_valid` tidak pernah
  dikirim/keputusan tidak dibuat client.
- Foto hanya dikirim saat submit; tidak disimpan ke public directory atau SQLite.
- Fondasi offline (Tahap 1) menyimpan foto di direktori privat aplikasi dan
  antrean di SQLite. Belum terhubung ke alur submit. Lihat
  `docs/offline-local-storage.md`.
- Backup Android mengecualikan database antrean dan direktori foto selfie.