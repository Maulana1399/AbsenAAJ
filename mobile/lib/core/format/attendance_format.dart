String formatTime(DateTime? value) {
  if (value == null) return '-';
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

String formatDate(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String formatDistance(double? meters) {
  if (meters == null) return '-';
  final rounded = meters.round();
  return '$rounded m';
}

/// Display label for a server-provided attendance status.
/// This only presents what the server already decided - it never computes it.
String attendanceStatusLabel(String status) => switch (status) {
      'ON_TIME' => 'Tepat Waktu',
      'LATE' => 'Terlambat',
      'NORMAL' => 'Normal',
      'EARLY_CHECKOUT' => 'Pulang Cepat',
      'MISSING_CHECKOUT' => 'Tidak Check-out',
      'PENDING_SYNC' => 'Menunggu Sinkronisasi',
      'REJECTED' => 'Ditolak',
      _ => status,
    };