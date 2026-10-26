import 'dart:io';

import 'package:absen_aaj/features/attendance/data/local/attendance_photo_storage.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'sqlite_test_support.dart';

void main() {
  late Directory temp;
  late FileAttendancePhotoStorage storage;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('absen_aaj_photos_test_');
    storage = FileAttendancePhotoStorage(
      directoryProvider: () async => temp,
      staleAfter: const Duration(hours: 1),
    );
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test(
    'writes a private file and returns only its relative filename',
    () async {
      final filename = await storage.writeJpeg(
        clientEventId: 'event-1',
        bytes: validJpegBytes,
      );

      expect(filename, isNot(contains('/')));
      expect(filename, isNot(contains(r'\')));
      expect(filename, endsWith('.jpg'));
      expect(await storage.exists(filename), isTrue);
      expect(await storage.read(filename), validJpegBytes);

      final files = await temp.list().toList();
      expect(files.whereType<File>(), hasLength(1));
      expect(files.single.path.endsWith('.tmp'), isFalse);
    },
  );

  test('two writes for the same event never reuse a filename', () async {
    final first = await storage.writeJpeg(
      clientEventId: 'same-event',
      bytes: validJpegBytes,
    );
    final second = await storage.writeJpeg(
      clientEventId: 'same-event',
      bytes: validJpegBytes,
    );

    expect(first, isNot(second));
    expect(await storage.exists(first), isTrue);
    expect(await storage.exists(second), isTrue);
  });

  test('rejects unsafe client event ids and unsafe filenames', () async {
    expect(
      () =>
          storage.writeJpeg(clientEventId: '../escape', bytes: validJpegBytes),
      throwsArgumentError,
    );
    expect(() => storage.resolve('../escape.jpg'), throwsArgumentError);
    expect(() => storage.resolve('nested/file.jpg'), throwsArgumentError);
    expect(() => storage.resolve('photo.jpg.tmp'), throwsArgumentError);
  });

  test('rejects empty, unsupported, and oversized bytes', () {
    expect(
      () => storage.writeJpeg(clientEventId: 'event-empty', bytes: const []),
      throwsArgumentError,
    );
    expect(
      () => storage.writeJpeg(clientEventId: 'event-bad', bytes: [1, 2, 3]),
      throwsArgumentError,
    );
    expect(
      () => storage.writeJpeg(
        clientEventId: 'event-large',
        bytes: [0xFF, 0xD8, 0xFF, ...List.filled(5120 * 1024, 0)],
      ),
      throwsArgumentError,
    );
  });

  test(
    'cleanup keeps files that became referenced after the snapshot',
    () async {
      final old = DateTime.now().subtract(const Duration(hours: 2));
      final raced = File(p.join(temp.path, 'raced.jpg'));
      await raced.writeAsBytes([1]);
      await raced.setLastModified(old);

      await storage.cleanupOrphans(
        referencedFilenames: const {},
        isStillReferenced: (filename) async => filename == 'raced.jpg',
      );

      expect(await raced.exists(), isTrue);
    },
  );

  test('removes only stale unreferenced and temporary files', () async {
    final old = DateTime.now().subtract(const Duration(hours: 2));

    final referenced = File(p.join(temp.path, 'referenced.jpg'));
    await referenced.writeAsBytes([1]);
    await referenced.setLastModified(old);

    final orphan = File(p.join(temp.path, 'orphan.jpg'));
    await orphan.writeAsBytes([2]);
    await orphan.setLastModified(old);

    final staleTemp = File(p.join(temp.path, '.stale.jpg.tmp'));
    await staleTemp.writeAsBytes([3]);
    await staleTemp.setLastModified(old);

    final freshOrphan = File(p.join(temp.path, 'fresh.jpg'));
    await freshOrphan.writeAsBytes([4]);

    final freshTemp = File(p.join(temp.path, '.fresh.jpg.tmp'));
    await freshTemp.writeAsBytes([5]);

    await storage.cleanupOrphans(referencedFilenames: {'referenced.jpg'});

    expect(await referenced.exists(), isTrue);
    expect(await orphan.exists(), isFalse);
    expect(await staleTemp.exists(), isFalse);
    expect(await freshOrphan.exists(), isTrue);
    expect(await freshTemp.exists(), isTrue);
  });
}
