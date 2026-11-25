import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/shared/photo_content.dart';
import 'package:pictoiq_mobile/shared/shot_ranking.dart';
import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

SimilarityCandidate _shot(String name, int hash) => SimilarityCandidate(
  visualHash: hash,
  capturedAt: 0,
  captureSource: CaptureSource.unknown,
  tieBreaker: name,
  faceCount: 1,
  colorLayout: List<double>.filled(12, 0.5),
);

int _bits(int bits) => (1 << bits) - 1;

SimilarityCandidate _couple(String name, List<double> clothes) =>
    SimilarityCandidate(
      visualHash: 0,
      capturedAt: 0,
      captureSource: CaptureSource.unknown,
      tieBreaker: name,
      faceCount: 2,
      colorLayout: List<double>.filled(12, 0.5),
      personColors: [clothes, clothes],
    );

void main() {
  test('a chain of look-alikes cannot join different people', () {
    // a~b and b~c match on clothing, but a and c do not.
    final shots = [
      _couple('a', [1.0, 0.0, 0.0, 0.0]),
      _couple('b', [0.88, 0.12, 0.0, 0.0]),
      _couple('c', [0.76, 0.24, 0.0, 0.0]),
    ];
    final clusters = clusterSimilar(
      shots,
      thresholds: SimilarityThresholds.forLevel(
        MatchLevel.balanced,
        samePeople: true,
      ),
    );
    for (final cluster in clusters) {
      final names = [for (final i in cluster.members) shots[i].tieBreaker];
      expect(names.contains('a') && names.contains('c'), isFalse);
    }
  });

  test('same background with faces but no clothing to compare is grouped by default', () {
    final shots = [_shot('a', 0), _shot('b', _bits(9))];
    final clusters = clusterSimilar(
      shots,
      thresholds: SimilarityThresholds.forLevel(MatchLevel.balanced),
    );
    expect(clusters.where((c) => c.members.length == 2), hasLength(1));
  });

  test('Same people only needs a near-identical frame without clothing evidence', () {
    final shots = [_shot('a', 0), _shot('b', _bits(9))];
    final clusters = clusterSimilar(
      shots,
      thresholds: SimilarityThresholds.forLevel(MatchLevel.balanced, samePeople: true),
    );
    expect(clusters.where((c) => c.members.length == 2), isEmpty);
    final close = [_shot('a', 0), _shot('b', _bits(4))];
    final joined = clusterSimilar(
      close,
      thresholds: SimilarityThresholds.forLevel(MatchLevel.balanced, samePeople: true),
    );
    expect(joined.where((c) => c.members.length == 2), hasLength(1));
  });

  test('Same people only is on by default and survives saving', () {
    expect(const AppSettings().shotSamePeople, isTrue);
    final json = const AppSettings(shotSamePeople: false).toJson();
    expect(AppSettings.fromJson(json).shotSamePeople, isFalse);
  });

  ShotFeatures features({List<PhotoLabel>? labels, FaceSignals? faces}) =>
      ShotFeatures(
        signals: const ImageSignals(
          sharpness: 200,
          meanLuma: 120,
          highlightClip: 0,
          shadowClip: 0,
        ),
        megapixels: 12,
        faces: faces,
        labels: labels,
      );

  test('people seen from behind are not a clearly good lone photo', () {
    final behind = features(
      faces: FaceSignals.none,
      labels: const [PhotoLabel('Scenery', 0.7), PhotoLabel('Sitting', 0.69)],
    );
    expect(isClearlyGood(behind), isFalse);
    expect(loneShotProblems(behind).join(' '), contains('no face'));
    final scenery = features(
      faces: FaceSignals.none,
      labels: const [PhotoLabel('Sky', 0.9), PhotoLabel('Cloud', 0.8)],
    );
    expect(isClearlyGood(scenery), isTrue);
  });

  test('tiny faces are not praised for open eyes', () {
    final tiny = features(
      faces: const FaceSignals(
        count: 2,
        eyesOpenMin: 0.77,
        smileAverage: 0.6,
        largestFaceArea: 0.001,
      ),
      labels: const [PhotoLabel('Jacket', 0.61)],
    );
    expect(isClearlyGood(tiny), isFalse);
  });
}
