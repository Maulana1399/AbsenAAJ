const attendancePhotoMaxBytes = 5120 * 1024;

enum AttendancePhotoFormat { jpeg, png, webp }

AttendancePhotoFormat detectAttendancePhotoFormat(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return AttendancePhotoFormat.jpeg;
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A) {
    return AttendancePhotoFormat.png;
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return AttendancePhotoFormat.webp;
  }
  throw ArgumentError.value(bytes, 'bytes', 'Unsupported photo format.');
}

void validateAttendancePhotoBytes(List<int> bytes) {
  if (bytes.isEmpty) {
    throw ArgumentError.value(bytes, 'bytes', 'Photo bytes are empty.');
  }
  if (bytes.length > attendancePhotoMaxBytes) {
    throw ArgumentError.value(
      bytes.length,
      'bytes',
      'Photo exceeds the $attendancePhotoMaxBytes byte limit.',
    );
  }
  detectAttendancePhotoFormat(bytes);
}
