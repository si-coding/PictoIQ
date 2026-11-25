import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/shared/grouping_explain.dart';
import 'package:pictoiq_mobile/shared/shot_ranking.dart';
import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

FolderScanPhoto _photo({ShotFeatures? features, bool document = false}) =>
    FolderScanPhoto(
      uri: 'a',
      name: 'a.jpg',
      relativePath: 'a.jpg',
      size: 1,
      modifiedAt: 1,
      sha256: null,
      visualHash: 0,
      qualityScore: 0,
      qualityNotes: const [],
      previewBytes: null,
      isDocument: document,
      features: features,
    );

ShotFeatures _features({double sharpness = 120, FaceSignals? faces}) =>
    ShotFeatures(
      signals: ImageSignals(
        sharpness: sharpness,
        meanLuma: 120,
        highlightClip: 0,
        shadowClip: 0,
      ),
      megapixels: 12,
      faces: faces,
    );

void main() {
  test('exact duplicates explain identical contents', () {
    final reasons = explainUngrouped(
      photo: _photo(),
      tool: UngroupedTool.exactDuplicates,
      documentMode: DocumentMode.leaveOut,
      contentFilter: ContentFilter.everything,
    );
    expect(reasons.single, contains('exactly the same'));
  });

  test('best shots explains that single photos are not listed', () {
    final reasons = explainUngrouped(
      photo: _photo(features: _features()),
      tool: UngroupedTool.bestShots,
      documentMode: DocumentMode.leaveOut,
      contentFilter: ContentFilter.everything,
    );
    expect(reasons.join(' '), contains('two or more'));
  });

  test('best moments lists what is wrong with a lone photo', () {
    final reasons = explainUngrouped(
      photo: _photo(
        features: _features(
          sharpness: 5,
          faces: const FaceSignals(
            count: 1,
            eyesOpenMin: 0.1,
            smileAverage: 0.5,
          ),
        ),
      ),
      tool: UngroupedTool.bestMoments,
      documentMode: DocumentMode.leaveOut,
      contentFilter: ContentFilter.everything,
    );
    final text = reasons.join(' ');
    expect(text, contains('soft'));
    expect(text, contains('eyes look closed'));
  });

  test('loneShotProblems is empty exactly when isClearlyGood', () {
    expect(loneShotProblems(_features()), isEmpty);
    expect(isClearlyGood(_features()), isTrue);
    expect(loneShotProblems(_features(sharpness: 5)), isNotEmpty);
    expect(isClearlyGood(_features(sharpness: 5)), isFalse);
  });
}
