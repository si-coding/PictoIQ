import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/shared/shot_ranking.dart';

ShotInput _shot(String id, FaceSignals faces) => ShotInput(
  id: id,
  tieBreaker: id,
  features: ShotFeatures(
    signals: const ImageSignals(
      sharpness: 100,
      meanLuma: 120,
      highlightClip: 0,
      shadowClip: 0,
    ),
    megapixels: 12,
    faces: faces,
  ),
);

/// How many points a big smile adds to a photo of [people] faces.
int _smileGap(int people) {
  final ranking = rankShots([
    _shot(
      'smile',
      FaceSignals(count: people, eyesOpenMin: 0.9, smileAverage: 0.9),
    ),
    _shot(
      'plain',
      FaceSignals(count: people, eyesOpenMin: 0.9, smileAverage: 0.1),
    ),
  ]);
  return ranking.shotFor('smile')!.score - ranking.shotFor('plain')!.score;
}

void main() {
  test('each face mix adds up to one', () {
    for (final people in [1, 2, 3, 8]) {
      final mix = faceMix(people);
      expect(mix.eyes + mix.smile + mix.presence, closeTo(1, 1e-9));
    }
  });

  test('a smile matters most for one person and least in a big group', () {
    expect(_smileGap(1), greaterThan(_smileGap(2)));
    expect(_smileGap(2), greaterThan(_smileGap(5)));
    expect(_smileGap(1), greaterThan(_smileGap(5) + 3));
  });

  test('open eyes count for the same in a group as for a pair', () {
    expect(faceMix(5).eyes, faceMix(2).eyes);
    expect(faceMix(5).eyes, greaterThan(faceMix(5).smile));
  });
}
