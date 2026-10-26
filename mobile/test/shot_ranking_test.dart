import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pictoiq_mobile/shot_ranking.dart';

ShotInput _shot(
  String id, {
  double sharpness = 100,
  double meanLuma = 120,
  double highlightClip = 0,
  double shadowClip = 0,
  double megapixels = 12,
  FaceSignals? faces,
}) => ShotInput(
  id: id,
  tieBreaker: id,
  features: ShotFeatures(
    signals: ImageSignals(
      sharpness: sharpness,
      meanLuma: meanLuma,
      highlightClip: highlightClip,
      shadowClip: shadowClip,
    ),
    megapixels: megapixels,
    faces: faces,
  ),
);

img.Image _checkerboard() {
  final image = img.Image(width: 200, height: 200);
  for (var y = 0; y < 200; y++) {
    for (var x = 0; x < 200; x++) {
      final value = ((x ~/ 4) + (y ~/ 4)).isEven ? 0 : 255;
      image.setPixelRgb(x, y, value, value, value);
    }
  }
  return image;
}

img.Image _solid(int value) {
  final image = img.Image(width: 100, height: 100);
  img.fill(image, color: img.ColorRgb8(value, value, value));
  return image;
}

void main() {
  group('rankShots', () {
    test('ranks the sharper photo first and explains why', () {
      final ranking = rankShots([
        _shot('soft', sharpness: 25),
        _shot('sharp', sharpness: 100),
      ]);
      expect(ranking.shots.map((s) => s.id), ['sharp', 'soft']);
      expect(ranking.shots.map((s) => s.rank), [1, 2]);
      expect(ranking.best.strengths, contains('Sharpest in the group'));
      expect(
        ranking.shotFor('soft')!.concerns.join(' '),
        contains('Softer'),
      );
      expect(ranking.isClearWinner, isTrue);
      expect(ranking.headline, startsWith('Recommended'));
    });

    test('near-equal photos are too close to call', () {
      final ranking = rankShots([
        _shot('a', sharpness: 100),
        _shot('b', sharpness: 98),
      ]);
      expect(ranking.margin, lessThan(GroupRanking.clearWinnerMargin));
      expect(ranking.isClearWinner, isFalse);
      expect(ranking.headline, contains('you decide'));
    });

    test('flags blown highlights', () {
      final ranking = rankShots([
        _shot('clean'),
        _shot('blown', highlightClip: 0.1),
      ]);
      expect(ranking.best.id, 'clean');
      expect(
        ranking.shotFor('blown')!.concerns.join(' '),
        contains('washed out'),
      );
    });

    test('prefers higher resolution and says so', () {
      final ranking = rankShots([
        _shot('small', megapixels: 8),
        _shot('large', megapixels: 12),
      ]);
      expect(ranking.best.id, 'large');
      expect(ranking.best.strengths, contains('Highest resolution (12.0 MP)'));
      expect(
        ranking.shotFor('small')!.concerns,
        contains('Lower resolution (8.0 MP vs 12.0 MP)'),
      );
    });

    test('open eyes can outweigh a slightly sharper photo', () {
      const open = FaceSignals(count: 2, eyesOpenMin: 0.9, smileAverage: null);
      const blink = FaceSignals(count: 2, eyesOpenMin: 0.1, smileAverage: null);
      final ranking = rankShots([
        _shot('blink', sharpness: 100, faces: blink),
        _shot('open', sharpness: 90, faces: open),
      ]);
      expect(ranking.usedFaceSignals, isTrue);
      expect(ranking.best.id, 'open');
      expect(
        ranking.shotFor('blink')!.concerns,
        contains('Someone may have their eyes closed'),
      );
    });

    test('face signals are ignored unless every photo was assessed', () {
      const face = FaceSignals(count: 1, eyesOpenMin: 0.9, smileAverage: 0.9);
      final partial = rankShots([
        _shot('a', faces: face),
        _shot('b', sharpness: 60),
      ]);
      expect(partial.usedFaceSignals, isFalse);
      final noFaces = rankShots([
        _shot('a', faces: FaceSignals.none),
        _shot('b', faces: FaceSignals.none),
      ]);
      expect(noFaces.usedFaceSignals, isFalse);
    });

    test('equal photos keep a stable order', () {
      final ranking = rankShots([_shot('b'), _shot('a')]);
      expect(ranking.shots.map((s) => s.id), ['a', 'b']);
    });

    test('handles one photo and none', () {
      final single = rankShots([_shot('only')]);
      expect(single.best.rank, 1);
      expect(single.margin, 100);
      expect(rankShots(const []).shots, isEmpty);
    });

    test('scores stay within 0-100', () {
      final ranking = rankShots([
        _shot('a', sharpness: 0, meanLuma: 255, highlightClip: 1, megapixels: 0),
        _shot('b', sharpness: 500),
      ]);
      for (final shot in ranking.shots) {
        expect(shot.score, inInclusiveRange(0, 100));
      }
    });
  });

  group('disqualifiers and finalists', () {
    const clean = FaceSignals(count: 1, eyesOpenMin: 0.9, smileAverage: 0.8);

    test('a cut-off face rules a photo out even if it is sharper', () {
      final ranking = rankShots([
        _shot(
          'cut',
          sharpness: 100,
          faces: const FaceSignals(
            count: 1,
            eyesOpenMin: 0.9,
            smileAverage: 0.8,
            edgeCutoff: true,
          ),
        ),
        _shot('ok', sharpness: 95, faces: clean),
      ]);
      expect(ranking.best.id, 'ok');
      expect(
        ranking.shotFor('cut')!.disqualifiers,
        contains('a face is cut off at the edge'),
      );
      expect(ranking.shotFor('cut')!.isFinalist, isFalse);
      expect(ranking.isClearWinner, isTrue);
    });

    test('closed eyes and looking away are faults; a slight turn is not', () {
      final ranking = rankShots([
        _shot(
          'closed',
          faces: const FaceSignals(
            count: 2,
            eyesOpenMin: 0.1,
            smileAverage: null,
          ),
        ),
        _shot(
          'away',
          faces: const FaceSignals(
            count: 2,
            eyesOpenMin: 0.9,
            smileAverage: null,
            lookingAwayMax: 40,
          ),
        ),
        _shot(
          'slight',
          faces: const FaceSignals(
            count: 2,
            eyesOpenMin: 0.9,
            smileAverage: null,
            lookingAwayMax: 20,
          ),
        ),
      ]);
      expect(ranking.shotFor('closed')!.disqualifiers, ['eyes closed']);
      expect(ranking.shotFor('away')!.disqualifiers, [
        'someone is looking away',
      ]);
      expect(ranking.shotFor('slight')!.isDisqualified, isFalse);
      expect(ranking.best.id, 'slight');
    });

    test('very blurry or washed-out photos are ruled out', () {
      final ranking = rankShots([
        _shot('good', sharpness: 100),
        _shot('blur', sharpness: 20),
        _shot('white', highlightClip: 0.3),
      ]);
      expect(ranking.shotFor('blur')!.disqualifiers, [
        'too blurry compared with the others',
      ]);
      expect(ranking.shotFor('white')!.disqualifiers, ['washed out']);
      expect(ranking.best.id, 'good');
      expect(ranking.shots.last.isDisqualified, isTrue);
    });

    test('when every photo has a fault there are no finalists', () {
      const closed = FaceSignals(count: 1, eyesOpenMin: 0.1, smileAverage: null);
      final ranking = rankShots([
        _shot('a', faces: closed),
        _shot('b', faces: closed),
      ]);
      expect(ranking.finalists, isEmpty);
      expect(ranking.isClearWinner, isFalse);
      expect(ranking.headline, startsWith('Every shot has a fault'));
    });

    test('at most three close photos become finalists', () {
      final ranking = rankShots([
        _shot('a', sharpness: 100),
        _shot('b', sharpness: 95),
        _shot('c', sharpness: 90),
        _shot('d', sharpness: 85),
        _shot('e', sharpness: 40),
      ]);
      expect(ranking.finalists.map((s) => s.id), ['a', 'b', 'c']);
      expect(ranking.isClearWinner, isFalse);
      expect(ranking.headline, '3 strong candidates; you decide');
    });

    test('a photo far behind the best is not a finalist', () {
      final ranking = rankShots([
        _shot('a', sharpness: 100),
        _shot('b', sharpness: 40),
      ]);
      expect(ranking.finalists.map((s) => s.id), ['a']);
      expect(ranking.isClearWinner, isTrue);
    });

    test('scores never go below zero with several faults', () {
      final ranking = rankShots([
        _shot('best'),
        _shot(
          'bad',
          sharpness: 1,
          highlightClip: 0.5,
          shadowClip: 0.6,
          faces: const FaceSignals(
            count: 1,
            eyesOpenMin: 0,
            smileAverage: 0,
            edgeCutoff: true,
            lookingAwayMax: 80,
          ),
        ),
      ]);
      expect(ranking.shotFor('bad')!.score, inInclusiveRange(0, 100));
      expect(ranking.shotFor('bad')!.disqualifiers.length, greaterThan(2));
    });
  });

  group('measureImage', () {
    test('a crisp image measures sharper than a blurred copy', () {
      final crisp = measureImage(_checkerboard());
      final blurred = measureImage(img.gaussianBlur(_checkerboard(), radius: 3));
      expect(crisp.sharpness, greaterThan(blurred.sharpness * 2));
    });

    test('a crisp subject on a blurred background is not judged soft', () {
      // Crisp checkerboard only in the middle, flat grey around it, like a
      // portrait-mode photo.
      final portrait = img.Image(width: 200, height: 200);
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 200; x++) {
          final inside = x >= 40 && x < 160 && y >= 40 && y < 160;
          final shade = inside ? (((x ~/ 4) + (y ~/ 4)).isEven ? 0 : 255) : 128;
          portrait.setPixelRgb(x, y, shade, shade, shade);
        }
      }
      final blurred = measureImage(img.gaussianBlur(_checkerboard(), radius: 3));
      expect(
        measureImage(portrait).sharpness,
        greaterThan(blurred.sharpness * 2),
      );
    });

    test('detects blown highlights and crushed shadows', () {
      final white = measureImage(_solid(255));
      expect(white.highlightClip, closeTo(1, 0.01));
      expect(white.meanLuma, closeTo(255, 1));
      expect(white.exposureScore, lessThan(40));
      final black = measureImage(_solid(0));
      expect(black.shadowClip, closeTo(1, 0.01));
      expect(black.exposureScore, lessThan(60));
    });

    test('mid-grey with no clipping scores full exposure', () {
      final grey = measureImage(_solid(120));
      expect(grey.highlightClip, 0);
      expect(grey.shadowClip, 0);
      expect(grey.exposureScore, closeTo(100, 1));
      expect(grey.sharpness, 0);
    });
  });
}
