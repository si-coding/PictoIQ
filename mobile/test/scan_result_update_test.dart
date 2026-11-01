import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/shot_ranking.dart';
import 'package:pictoiq_mobile/similarity_grouping.dart';

FolderScanPhoto _photo(String name, {double sharpness = 100, String? sha}) =>
    FolderScanPhoto(
      uri: 'content://test/$name',
      name: name,
      relativePath: name,
      size: 1000,
      modifiedAt: 1700000000000,
      sha256: sha,
      visualHash: 0,
      qualityScore: 0,
      qualityNotes: const [],
      previewBytes: null,
      features: ShotFeatures(
        signals: ImageSignals(
          sharpness: sharpness,
          meanLuma: 120,
          highlightClip: 0,
          shadowClip: 0,
        ),
        megapixels: 12,
      ),
    );

const _evidence = SimilarityEvidence(
  confidence: SimilarityConfidence.high,
  maxDistance: 2,
  spanMs: 3000,
  captureSource: CaptureSource.exif,
  size: 3,
);

FolderScanResult _result(List<FolderDuplicateGroup> groups, {bool best = false}) =>
    FolderScanResult(
      folderUri: 'content://test',
      folderName: 'test',
      imagesScanned: 10,
      duplicateGroups: groups,
      bestShotsScan: best,
      dateRange: FolderDateRange.currentFolder,
    );

void main() {
  test('removing nothing returns the same result', () {
    final result = _result([]);
    expect(identical(result.withoutPhotos({}), result), isTrue);
  });

  test('exact groups shrink and disappear when fewer than two remain', () {
    final group = FolderDuplicateGroup(
      id: 'sha',
      photos: [_photo('a', sha: 'x'), _photo('b', sha: 'x'), _photo('c', sha: 'x')],
    );
    final result = _result([group]);

    final one = result.withoutPhotos({'content://test/c'});
    expect(one.duplicateGroups.single.photos.map((p) => p.name), ['a', 'b']);
    expect(one.imagesScanned, 9);

    final two = result.withoutPhotos({'content://test/b', 'content://test/c'});
    expect(two.duplicateGroups, isEmpty);
    expect(two.imagesScanned, 8);
  });

  test('similar groups are re-ranked from the photos that remain', () {
    final group = rankedGroup([
      _photo('a', sharpness: 100),
      _photo('b', sharpness: 90),
      _photo('c', sharpness: 40),
    ], _evidence);
    expect(group.ranking!.best.id, 'content://test/a');

    final after = _result([group], best: true).withoutPhotos({
      'content://test/a',
    });
    final updated = after.duplicateGroups.single;
    expect(updated.id, group.id);
    expect(updated.photos.length, 2);
    expect(updated.ranking!.shots.length, 2);
    expect(updated.ranking!.best.id, 'content://test/b');
    expect(updated.evidence, same(_evidence));
  });

  test('untouched groups are kept as they are', () {
    final group = rankedGroup([_photo('a'), _photo('b')], _evidence);
    final result = _result([group], best: true).withoutPhotos({'content://other'});
    expect(identical(result.duplicateGroups.single, group), isTrue);
  });

  test('a photo can be taken out of its group without deleting anything', () {
    final group = rankedGroup([
      _photo('a', sharpness: 100),
      _photo('b', sharpness: 90),
      _photo('c', sharpness: 80),
    ], _evidence);
    final result = _result([group], best: true);

    final after = result.withoutFromGroup(group.id, 'content://test/b');
    expect(after.duplicateGroups.single.photos.map((p) => p.name), ['a', 'c']);
    expect(after.duplicateGroups.single.ranking!.shots.length, 2);
    expect(after.imagesScanned, result.imagesScanned);

    final alone = after.withoutFromGroup(group.id, 'content://test/c');
    expect(alone.duplicateGroups, isEmpty);
    expect(alone.imagesScanned, result.imagesScanned);

    final other = result.withoutFromGroup('another-group', 'content://test/a');
    expect(other.duplicateGroups.single.photos.length, 3);
  });

  test('a whole group can be set aside without deleting anything', () {
    final first = rankedGroup([_photo('a'), _photo('b')], _evidence);
    final second = rankedGroup([_photo('c'), _photo('d')], _evidence);
    final result = _result([first, second], best: true);

    final after = result.withoutGroup(first.id);
    expect(after.duplicateGroups.map((g) => g.id), [second.id]);
    expect(after.imagesScanned, result.imagesScanned);
    expect(result.duplicateGroups, hasLength(2));
  });

  test('describes the date range in words', () {
    FolderScanResult scan(
      FolderDateRange range, [
      DateTime? from,
      DateTime? to,
    ]) => FolderScanResult(
      folderUri: 'content://test',
      folderName: 'test',
      imagesScanned: 1,
      duplicateGroups: const [],
      bestShotsScan: true,
      dateRange: range,
      rangeStart: from,
      rangeEnd: to,
    );

    expect(scan(FolderDateRange.currentFolder).rangeDescription, 'All dates');
    expect(
      scan(
        FolderDateRange.custom,
        DateTime(2026, 10, 3),
        DateTime(2026, 10, 20),
      ).rangeDescription,
      '3 Oct 2026 – 20 Oct 2026',
    );
    expect(
      scan(
        FolderDateRange.week,
        DateTime(2026, 10, 25),
        DateTime(2026, 11, 1),
      ).rangeDescription,
      'Last 7 days (25 Oct 2026 – 1 Nov 2026)',
    );
    expect(scan(FolderDateRange.today).rangeDescription, 'Today');
  });
}
