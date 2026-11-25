import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/shared/shot_ranking.dart';
import 'package:pictoiq_mobile/shared/sunglasses.dart';

const _size = 200;

Uint8List _face(List<int> skin) {
  final data = Uint8List(_size * _size * 4);
  for (var i = 0; i < _size * _size; i++) {
    data[i * 4] = skin[0];
    data[i * 4 + 1] = skin[1];
    data[i * 4 + 2] = skin[2];
    data[i * 4 + 3] = 255;
  }
  return data;
}

void _paint(Uint8List data, int x0, int y0, int x1, int y1, List<int> color) {
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = (y * _size + x) * 4;
      data[i] = color[0];
      data[i + 1] = color[1];
      data[i + 2] = color[2];
    }
  }
}

bool _check(Uint8List data) => eyesHiddenBySunglasses(
  data,
  _size,
  _size,
  leftEye: (70, 80),
  rightEye: (130, 80),
);

void main() {
  group('eyesHiddenBySunglasses', () {
    test('dark lenses over both eyes are recognised', () {
      final data = _face([210, 170, 140]);
      _paint(data, 48, 66, 152, 96, [20, 20, 20]);
      expect(_check(data), isTrue);
    });

    test('light tinted lenses are recognised', () {
      final data = _face([190, 150, 125]);
      _paint(data, 48, 66, 152, 96, [88, 88, 88]);
      expect(_check(data), isTrue);
    });

    test('clear glasses over dark eyes are not sunglasses', () {
      final data = _face([150, 110, 90]);
      _paint(data, 56, 70, 84, 90, [95, 80, 70]);
      _paint(data, 116, 70, 144, 90, [95, 80, 70]);
      expect(_check(data), isFalse);
    });

    test('open eyes with small dark pupils are not sunglasses', () {
      final data = _face([210, 170, 140]);
      _paint(data, 66, 77, 74, 83, [30, 20, 15]);
      _paint(data, 126, 77, 134, 83, [30, 20, 15]);
      expect(_check(data), isFalse);
    });

    test('a darker skin tone is not mistaken for sunglasses', () {
      final data = _face([95, 65, 50]);
      expect(_check(data), isFalse);
    });

    test('one dark eye (a shadow or a wink) is not sunglasses', () {
      final data = _face([210, 170, 140]);
      _paint(data, 55, 66, 85, 96, [20, 20, 20]);
      expect(_check(data), isFalse);
    });

    test('eyes at the edge of the picture cannot be measured', () {
      final data = _face([210, 170, 140]);
      expect(
        eyesHiddenBySunglasses(
          data,
          _size,
          _size,
          leftEye: (2, 80),
          rightEye: (130, 80),
        ),
        isFalse,
      );
    });
  });

  group('ranking with sunglasses', () {
    ShotInput shot(String id, FaceSignals faces, {double sharpness = 100}) =>
        ShotInput(
          id: id,
          tieBreaker: id,
          features: ShotFeatures(
            signals: ImageSignals(
              sharpness: sharpness,
              meanLuma: 120,
              highlightClip: 0,
              shadowClip: 0,
            ),
            megapixels: 12,
            faces: faces,
          ),
        );

    test('sunglasses are not marked as closed eyes', () {
      const glasses = FaceSignals(
        count: 1,
        eyesOpenMin: null,
        smileAverage: null,
        sunglassesCount: 1,
      );
      const blink = FaceSignals(count: 1, eyesOpenMin: 0.1, smileAverage: null);
      final ranking = rankShots([
        shot('blink', blink),
        shot('glasses', glasses),
      ]);
      expect(ranking.best.id, 'glasses');
      final ranked = ranking.shotFor('glasses')!;
      expect(ranked.isDisqualified, isFalse);
      expect(
        ranked.strengths,
        contains('Sunglasses on, so eyes are not judged'),
      );
    });

    test('a sunglasses shot scores about the same as an open-eyed one', () {
      const glasses = FaceSignals(
        count: 1,
        eyesOpenMin: null,
        smileAverage: null,
        sunglassesCount: 1,
      );
      const open = FaceSignals(count: 1, eyesOpenMin: 0.9, smileAverage: null);
      final ranking = rankShots([shot('plain', open), shot('glasses', glasses)]);
      final plain = ranking.shotFor('plain')!;
      final cool = ranking.shotFor('glasses')!;
      expect(cool.isDisqualified, isFalse);
      expect((plain.score - cool.score).abs(), lessThanOrEqualTo(3));
    });

    test('effectiveEyesOpen treats sunglasses as open eyes', () {
      const glasses = FaceSignals(
        count: 1,
        eyesOpenMin: null,
        smileAverage: null,
        sunglassesCount: 1,
      );
      expect(effectiveEyesOpen(glasses), greaterThan(0.8));
      expect(effectiveEyesOpen(FaceSignals.none), isNull);
      expect(effectiveEyesOpen(null), isNull);
    });
  });
}
