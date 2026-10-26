import 'package:path/path.dart' as p;

final _safeClientEventId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$');
final _safePhotoFilename = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

bool isSafeClientEventId(String value) => _safeClientEventId.hasMatch(value);

bool isSafePhotoFilename(String value) {
  if (!_safePhotoFilename.hasMatch(value)) return false;
  if (p.basename(value) != value) return false;
  if (value.contains('..')) return false;
  if (value.toLowerCase().endsWith('.tmp')) return false;
  return true;
}
