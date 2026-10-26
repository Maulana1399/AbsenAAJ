import 'package:absen_aaj/features/attendance/data/local/attendance_photo_policy.dart';
import 'package:test/test.dart';

const _png = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
];
const _webp = <int>[
  0x52,
  0x49,
  0x46,
  0x46,
  0x04,
  0x00,
  0x00,
  0x00,
  0x57,
  0x45,
  0x42,
  0x50,
];
const _jpeg = <int>[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0xFF, 0xD9];

void main() {
  test('detects the photo formats accepted by the backend', () {
    expect(detectAttendancePhotoFormat(_jpeg), AttendancePhotoFormat.jpeg);
    expect(detectAttendancePhotoFormat(_png), AttendancePhotoFormat.png);
    expect(detectAttendancePhotoFormat(_webp), AttendancePhotoFormat.webp);
  });

  test('rejects empty, unsupported, and oversized photos', () {
    expect(() => validateAttendancePhotoBytes(const []), throwsArgumentError);
    expect(
      () => validateAttendancePhotoBytes(const [1, 2, 3, 4]),
      throwsArgumentError,
    );
    expect(
      () => validateAttendancePhotoBytes([
        ..._jpeg,
        ...List.filled(attendancePhotoMaxBytes, 0),
      ]),
      throwsArgumentError,
    );
  });

  test('accepts a photo exactly at the backend size limit', () {
    final bytes = [
      ..._jpeg,
      ...List.filled(attendancePhotoMaxBytes - _jpeg.length, 0),
    ];
    expect(bytes.length, attendancePhotoMaxBytes);
    expect(() => validateAttendancePhotoBytes(bytes), returnsNormally);
  });
}
