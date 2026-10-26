/// Maps backend API error codes to friendly Indonesian messages.
///
/// The backend returns `{ "message": ..., "code": "OUTSIDE_GEOFENCE", ... }`.
/// We never render the raw JSON or server message directly; instead every
/// known code is translated here.
library;

String apiErrorCodeToMessage(String code) => switch (code) {
      'BRANCH_NOT_CONFIGURED' => 'Cabang belum dikonfigurasi untuk anda. Hubungi HR.',
      'BRANCH_LOCATION_NOT_CONFIGURED' =>
        'Cabang belum memiliki konfigurasi lokasi. Hubungi HR.',
      'LOCATION_LOW_ACCURACY' =>
        'Akurasi GPS terlalu rendah. Pindah ke tempat yang lebih terbuka lalu coba lagi.',
      'OUTSIDE_GEOFENCE' =>
        'Anda berada di luar area absensi cabang. Silakan berada di area yang ditentukan kemudian coba kembali.',
      'CHECK_IN_REQUIRED' => 'Anda harus check-in terlebih dahulu sebelum check-out.',
      'ALREADY_CHECKED_IN' => 'Anda sudah melakukan check-in.',
      'ALREADY_CHECKED_OUT' => 'Anda sudah melakukan check-out.',
      'DEVICE_REVOKED' => 'Device ini telah dinonaktifkan. Hubungi HR.',
      'DEVICE_ALREADY_REGISTERED' =>
        'Device ini sudah terdaftar untuk karyawan lain.',
      'DEVICE_NOT_FOUND' =>
        'Device belum terdaftar. Silakan hubungi administrator.',
      'EMPLOYEE_REQUIRED' => 'Akun anda belum terhubung ke data karyawan. Hubungi HR.',
      'INVALID_CREDENTIALS' => 'Email atau password salah.',
      'ACCOUNT_INACTIVE' => 'Akun anda tidak aktif. Hubungi HR.',
      'VALIDATION_ERROR' => 'Data yang dikirim tidak valid. Silakan periksa kembali.',
      'ATTENDANCE_EVENT_CONFLICT' => 'Terjadi kesalahan. Silakan coba lagi.',
      'UNAUTHENTICATED' => 'Sesi berakhir. Silakan login kembali.',
      _ => 'Terjadi kesalahan. Silakan coba lagi.',
    };