import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart'
    show FolderDateRange, ScanCancelled;
import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart';

VideoItem _video(
  String id, {
  int seconds = 10,
  int width = 1920,
  int height = 1080,
  int day = 1,
}) => VideoItem(
  id: id,
  title: '$id.mp4',
  durationSeconds: seconds,
  width: width,
  height: height,
  createdAt: DateTime(2026, 10, day),
);

/// Pretends to read files: [contents] maps a video id to (size, hash).
Future<({int size, String sha256})?> Function(VideoItem) _reader(
  Map<String, (int, String)?> contents,
) => (video) async {
  final entry = contents[video.id];
  return entry == null ? null : (size: entry.$1, sha256: entry.$2);
};

void main() {
  group('candidateSets', () {
    test('only videos with the same length and picture size', () {
      final sets = candidateSets([
        _video('a'),
        _video('b'),
        _video('c', seconds: 11),
        _video('d', width: 1280, height: 720),
      ]);
      expect(sets, hasLength(1));
      expect([for (final v in sets.single) v.id], ['a', 'b']);
    });

    test('a library with no matching pairs has no candidates', () {
      expect(candidateSets([_video('a'), _video('b', seconds: 3)]), isEmpty);
    });
  });

  group('groupIdenticalVideos', () {
    test('groups videos with the same size and hash', () async {
      final groups = await groupIdenticalVideos(
        candidateSets([_video('a', day: 3), _video('b', day: 1), _video('c')]),
        _reader({'a': (100, 'x'), 'b': (100, 'x'), 'c': (100, 'y')}),
      );
      expect(groups, hasLength(1));
      expect([for (final v in groups.single.items) v.id], ['b', 'a']);
      expect(groups.single.original.id, 'b');
      expect([for (final v in groups.single.copies) v.id], ['a']);
    });

    test('same hash but different size is not a duplicate', () async {
      final groups = await groupIdenticalVideos(
        candidateSets([_video('a'), _video('b')]),
        _reader({'a': (100, 'x'), 'b': (101, 'x')}),
      );
      expect(groups, isEmpty);
    });

    test('unreadable videos are counted and left out', () async {
      var unreadable = 0;
      final groups = await groupIdenticalVideos(
        candidateSets([_video('a'), _video('b'), _video('c')]),
        _reader({'a': (100, 'x'), 'b': (100, 'x'), 'c': null}),
        onUnreadable: () => unreadable += 1,
      );
      expect(groups, hasLength(1));
      expect(groups.single.items, hasLength(2));
      expect(unreadable, 1);
    });

    test('reports progress for every video read', () async {
      final seen = <int>[];
      await groupIdenticalVideos(
        candidateSets([_video('a'), _video('b')]),
        _reader({'a': (1, 'x'), 'b': (1, 'x')}),
        onProgress: seen.add,
      );
      expect(seen, [1, 2]);
    });

    test('can be cancelled', () async {
      expect(
        groupIdenticalVideos(
          candidateSets([_video('a'), _video('b')]),
          _reader({'a': (1, 'x'), 'b': (1, 'x')}),
          shouldCancel: () => true,
        ),
        throwsA(isA<ScanCancelled>()),
      );
    });

    test('the set that frees the most space comes first', () async {
      final groups = await groupIdenticalVideos(
        candidateSets([
          _video('a'),
          _video('b'),
          _video('c', seconds: 20),
          _video('d', seconds: 20),
        ]),
        _reader({
          'a': (10, 'x'),
          'b': (10, 'x'),
          'c': (500, 'y'),
          'd': (500, 'y'),
        }),
      );
      expect(groups.first.original.size, 500);
    });
  });

  group('VideoDuplicateGroup', () {
    test('without drops removed videos and dissolves a set of one', () {
      final group = VideoDuplicateGroup(
        id: 'g',
        items: [_video('a'), _video('b', day: 2), _video('c', day: 3)],
      );
      expect(group.without({'c'})!.items, hasLength(2));
      expect(group.without({'b', 'c'}), isNull);
      expect(group.without({}), same(group));
    });

    test('bytesFreedKeeping adds up the other videos', () {
      final a = _video('a').withContent(size: 10, sha256: 'x');
      final b = _video('b', day: 2).withContent(size: 10, sha256: 'x');
      final group = VideoDuplicateGroup(id: 'g', items: [a, b]);
      expect(group.bytesFreedKeeping(a), 10);
    });
  });

  group('dateWindow', () {
    final now = DateTime(2026, 11, 5, 15);

    test('today starts at midnight', () {
      final window = VideoDuplicateScanner.dateWindow(
        FolderDateRange.today,
        now: now,
      );
      expect(window.lower, DateTime(2026, 11, 5));
      expect(window.upper, isNull);
    });

    test('7 days looks back a week', () {
      final window = VideoDuplicateScanner.dateWindow(
        FolderDateRange.week,
        now: now,
      );
      expect(window.lower, DateTime(2026, 10, 29, 15));
    });

    test('custom includes the last day', () {
      final window = VideoDuplicateScanner.dateWindow(
        FolderDateRange.custom,
        from: DateTime(2026, 10, 1, 9),
        to: DateTime(2026, 10, 31, 9),
        now: now,
      );
      expect(window.lower, DateTime(2026, 10, 1));
      expect(window.upper, DateTime(2026, 11, 1));
    });

    test('all dates has no limits', () {
      final window = VideoDuplicateScanner.dateWindow(
        FolderDateRange.currentFolder,
        now: now,
      );
      expect(window.lower, isNull);
      expect(window.upper, isNull);
    });
  });
}
