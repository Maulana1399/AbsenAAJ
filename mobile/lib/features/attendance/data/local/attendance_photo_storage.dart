import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'attendance_photo_naming.dart';
import 'attendance_photo_policy.dart';

abstract interface class AttendancePhotoStorage {
  Future<String> writeJpeg({
    required String clientEventId,
    required List<int> bytes,
  });

  Future<List<int>> read(String filename);

  Future<bool> exists(String filename);

  Future<void> delete(String filename);

  Future<File> resolve(String filename);

  Future<void> cleanupOrphans({
    required Set<String> referencedFilenames,
    Future<bool> Function(String filename)? isStillReferenced,
  });
}

class FileAttendancePhotoStorage implements AttendancePhotoStorage {
  FileAttendancePhotoStorage({
    required this._directoryProvider,
    this._staleAfter = const Duration(hours: 1),
  });

  final Future<Directory> Function() _directoryProvider;
  final Duration _staleAfter;
  final Random _random = Random.secure();

  @override
  Future<String> writeJpeg({
    required String clientEventId,
    required List<int> bytes,
  }) async {
    if (!isSafeClientEventId(clientEventId)) {
      throw ArgumentError.value(
        clientEventId,
        'clientEventId',
        'Must be a safe file-name-safe event id.',
      );
    }
    validateAttendancePhotoBytes(bytes);

    final directory = await _ensureDirectory();
    final suffix = _uniqueSuffix();
    final filename = '${clientEventId}_$suffix.jpg';
    final target = File(p.join(directory.path, filename));
    final temporary = File(p.join(directory.path, '.$filename.tmp'));

    try {
      if (await target.exists()) {
        throw FileSystemException('Photo filename collision.', target.path);
      }
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
      return filename;
    } catch (_) {
      await _deleteIfExists(temporary, swallowErrors: true);
      rethrow;
    }
  }

  @override
  Future<List<int>> read(String filename) async {
    final file = await resolve(filename);
    return file.readAsBytes();
  }

  @override
  Future<bool> exists(String filename) async {
    final file = await resolve(filename);
    return file.exists();
  }

  @override
  Future<void> delete(String filename) async {
    final file = await resolve(filename);
    await _deleteIfExists(file);
  }

  @override
  Future<File> resolve(String filename) async {
    _assertSafeFilename(filename);
    final directory = await _ensureDirectory();
    return File(p.join(directory.path, filename));
  }

  @override
  Future<void> cleanupOrphans({
    required Set<String> referencedFilenames,
    Future<bool> Function(String filename)? isStillReferenced,
  }) async {
    final directory = await _ensureDirectory();
    final now = DateTime.now();

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;

      final filename = p.basename(entity.path);
      if (referencedFilenames.contains(filename)) continue;
      if (isStillReferenced != null) {
        try {
          if (await isStillReferenced(filename)) continue;
        } catch (_) {
          continue;
        }
      }

      try {
        final stat = await entity.stat();
        if (now.difference(stat.modified) < _staleAfter) continue;
        await _deleteIfExists(entity, swallowErrors: true);
      } catch (_) {
        continue;
      }
    }
  }

  String _uniqueSuffix() {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final nonce = _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
    return '${micros}_$nonce';
  }

  Future<Directory> _ensureDirectory() async {
    final directory = await _directoryProvider();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  void _assertSafeFilename(String filename) {
    if (!isSafePhotoFilename(filename)) {
      throw ArgumentError.value(
        filename,
        'filename',
        'Must be a relative file name without path segments.',
      );
    }
  }

  Future<void> _deleteIfExists(File file, {bool swallowErrors = false}) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      if (!swallowErrors) rethrow;
    }
  }
}
