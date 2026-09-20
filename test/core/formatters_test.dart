import 'package:flutter_test/flutter_test.dart';
import 'package:puter_cloud_storage/core/format/file_kinds.dart';
import 'package:puter_cloud_storage/core/format/formatters.dart';

void main() {
  group('ByteFormat', () {
    test('keeps bytes as bytes', () {
      expect(ByteFormat.format(0), '0 B');
      expect(ByteFormat.format(512), '512 B');
    });

    test('keeps one decimal below ten and drops it above', () {
      // "1.4 GB" keeps its precision; "147 MB" does not gain a digit that means
      // nothing.
      expect(ByteFormat.format(1536), '1.5 KB');
      expect(ByteFormat.format(15 * 1024 * 1024), '15 MB');
      expect(ByteFormat.format(147 * 1024 * 1024), '147 MB');
    });

    test('uses binary units, matching what a storage tool reports', () {
      // 100 MiB — Puter's documented free quota — must not read as "104.9 MB",
      // which would look like a discrepancy rather than a rounding choice.
      expect(ByteFormat.format(100 * 1024 * 1024), '100 MB');
    });

    test('climbs to terabytes', () {
      expect(ByteFormat.format(3 * 1024 * 1024 * 1024 * 1024), '3.0 TB');
    });

    test('a negative size is not rendered as a number', () {
      expect(ByteFormat.format(-1), '—');
    });

    test('rate annotates per second', () {
      expect(ByteFormat.rate(1024 * 1024), '1.0 MB/s');
      expect(ByteFormat.rate(0), '—');
    });

    test('duration reads naturally at every scale', () {
      expect(ByteFormat.duration(const Duration(milliseconds: 500)),
          'less than a second');
      expect(ByteFormat.duration(const Duration(seconds: 45)), '45s');
      expect(ByteFormat.duration(const Duration(minutes: 2)), '2m');
      expect(ByteFormat.duration(const Duration(seconds: 150)), '2m 30s');
      expect(ByteFormat.duration(const Duration(hours: 3)), '3h');
      expect(ByteFormat.duration(const Duration(minutes: 185)), '3h 5m');
    });
  });

  group('DateFormatting', () {
    final DateTime now = DateTime(2026, 9, 21, 12);

    test('recent times read relatively', () {
      expect(
        DateFormatting.relative(now.subtract(const Duration(seconds: 20)),
            now: now),
        'Just now',
      );
      expect(
        DateFormatting.relative(now.subtract(const Duration(minutes: 5)),
            now: now),
        '5 min ago',
      );
      expect(
        DateFormatting.relative(now.subtract(const Duration(hours: 1)),
            now: now),
        '1 hour ago',
      );
      expect(
        DateFormatting.relative(now.subtract(const Duration(days: 1)),
            now: now),
        'Yesterday',
      );
    });

    test('past a week it becomes a date', () {
      // "43 days ago" is harder to place than a date, so the date is what the
      // user gets.
      final old = now.subtract(const Duration(days: 43));
      expect(DateFormatting.relative(old, now: now), '9 Aug, 12:00');
    });

    test('drops the year inside the current year and keeps it outside', () {
      expect(DateFormatting.absolute(DateTime(2026, 3, 4, 9, 30), now: now),
          '4 Mar, 09:30');
      expect(DateFormatting.absolute(DateTime(2024, 3, 4), now: now),
          '4 Mar 2024');
    });

    test('an unknown timestamp says so rather than inventing one', () {
      expect(DateFormatting.relative(null), 'Unknown');
      expect(DateFormatting.absolute(null), 'Unknown');
    });

    test('a future timestamp falls back to a date instead of a negative', () {
      final future = now.add(const Duration(hours: 3));
      expect(DateFormatting.relative(future, now: now), '21 Sep, 15:00');
    });
  });

  group('FileKinds', () {
    test('maps the common extensions', () {
      expect(FileKinds.of('photo.JPG'), FileCategory.image);
      expect(FileKinds.of('clip.mp4'), FileCategory.video);
      expect(FileKinds.of('song.mp3'), FileCategory.audio);
      expect(FileKinds.of('report.pdf'), FileCategory.pdf);
      expect(FileKinds.of('sheet.xlsx'), FileCategory.spreadsheet);
      expect(FileKinds.of('bundle.zip'), FileCategory.archive);
      expect(FileKinds.of('main.dart'), FileCategory.code);
      expect(FileKinds.of('notes.txt'), FileCategory.text);
    });

    test('a folder is its own category regardless of its name', () {
      expect(
        FileKinds.of('holiday.jpg', isDirectory: true),
        FileCategory.folder,
      );
    });

    test('an unknown or absent extension is not guessed at', () {
      expect(FileKinds.of('README'), FileCategory.unknown);
      expect(FileKinds.of('archive.'), FileCategory.unknown);
      expect(FileKinds.of('.hidden'), FileCategory.unknown);
      expect(FileKinds.of('data.xyz'), FileCategory.unknown);
    });

    test('only raster formats claim to be thumbnailable', () {
      // Claiming otherwise produces a broken-image placeholder, because the app
      // ships no SVG or HEIC decoder.
      expect(FileKinds.isThumbnailable('a.png'), isTrue);
      expect(FileKinds.isThumbnailable('a.jpeg'), isTrue);
      expect(FileKinds.isThumbnailable('a.svg'), isFalse);
      expect(FileKinds.isThumbnailable('a.heic'), isFalse);
      expect(FileKinds.isThumbnailable('a.txt'), isFalse);
    });

    test('every category has an icon', () {
      for (final FileCategory category in FileCategory.values) {
        expect(FileKinds.iconFor(category), isNotNull);
      }
    });
  });
}
