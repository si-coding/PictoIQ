import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/shared/shot_ranking.dart';
import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

ShotFeatures _features({
  double sharpness = 200,
  double meanLuma = 120,
  FaceSignals? faces,
}) => ShotFeatures(
  signals: ImageSignals(
    sharpness: sharpness,
    meanLuma: meanLuma,
    highlightClip: 0,
    shadowClip: 0,
  ),
  megapixels: 12,
  faces: faces,
);

FolderScanPhoto _photo(String name) => FolderScanPhoto(
  uri: name,
  name: name,
  relativePath: name,
  size: 1,
  modifiedAt: 1,
  sha256: null,
  visualHash: 0,
  qualityScore: 0,
  qualityNotes: const [],
  previewBytes: null,
);

void main() {
  test('a sharp, well exposed photo is clearly good', () {
    expect(isClearlyGood(_features()), isTrue);
  });

  test('a blurry or badly exposed photo is not', () {
    expect(isClearlyGood(_features(sharpness: 10)), isFalse);
    expect(isClearlyGood(_features(meanLuma: 30)), isFalse);
  });

  test('a person with closed eyes or cut off is not', () {
    expect(
      isClearlyGood(
        _features(
          faces: const FaceSignals(
            count: 1,
            eyesOpenMin: 0.1,
            smileAverage: 0.5,
          ),
        ),
      ),
      isFalse,
    );
    expect(
      isClearlyGood(
        _features(
          faces: const FaceSignals(
            count: 1,
            eyesOpenMin: 0.9,
            smileAverage: 0.5,
            edgeCutoff: true,
          ),
        ),
      ),
      isFalse,
    );
    expect(
      isClearlyGood(
        _features(
          faces: const FaceSignals(
            count: 2,
            eyesOpenMin: 0.9,
            smileAverage: 0.7,
          ),
        ),
      ),
      isTrue,
    );
  });

  test('a group of one keeps its photo and explains itself', () {
    final group = rankedGroup(
      [_photo('a.jpg')],
      const SimilarityEvidence(
        confidence: SimilarityConfidence.high,
        maxDistance: 0,
        spanMs: 0,
        captureSource: CaptureSource.unknown,
        size: 1,
      ),
    );
    expect(group.photos, hasLength(1));
    expect(group.evidence!.notes.single, contains('Only photo'));
    expect(group.without(const {}), same(group));
    expect(group.without({'a.jpg'}), isNull);
  });
}
