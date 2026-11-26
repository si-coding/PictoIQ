import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/shared/shot_ranking.dart';

ShotFeatures _features({
  double sharpness = 120,
  FaceSignals? faces,
}) => ShotFeatures(
  signals: ImageSignals(
    sharpness: sharpness,
    meanLuma: 120,
    highlightClip: 0,
    shadowClip: 0,
  ),
  megapixels: 12,
  faces: faces,
);

const _clearPerson = FaceSignals(
  count: 1,
  eyesOpenMin: 0.9,
  smileAverage: 0.6,
  largestFaceArea: 0.05,
  faceSharpness: 40,
  frameSharpness: 100,
);

void main() {
  group('a best moment needs a clear person', () {
    test('a sharp photo of a clearly visible person qualifies', () {
      expect(isMeaningfulMoment(_features(faces: _clearPerson)), isTrue);
    });

    test('scenery is never a best moment, even when it is sharp', () {
      expect(isMeaningfulMoment(_features()), isFalse);
      expect(
        isMeaningfulMoment(_features(faces: FaceSignals.none)),
        isFalse,
      );
      expect(
        momentProblems(_features()).join(' '),
        contains('No person can be seen clearly'),
      );
    });

    test('unmeasured photos do not qualify', () {
      expect(isMeaningfulMoment(null), isFalse);
    });

    test('a person with a soft face does not qualify', () {
      const soft = FaceSignals(
        count: 2,
        eyesOpenMin: 0.9,
        smileAverage: 0.5,
        largestFaceArea: 0.05,
        faceSharpness: 4,
        frameSharpness: 100,
      );
      expect(isMeaningfulMoment(_features(faces: soft)), isFalse);
    });

    test('a soft whole picture does not qualify', () {
      expect(
        isMeaningfulMoment(_features(sharpness: 20, faces: _clearPerson)),
        isFalse,
      );
    });

    test('a single small face (0.5% of the picture) is not the subject', () {
      const small = FaceSignals(
        count: 1,
        eyesOpenMin: 0.86,
        smileAverage: 0.7,
        largestFaceArea: 0.005,
        faceSharpness: 366,
        frameSharpness: 1623,
      );
      expect(isMeaningfulMoment(_features(faces: small)), isFalse);
      expect(
        momentProblems(_features(faces: small)).join(' '),
        contains('fills only 0.5%'),
      );
    });

    test('a full-length couple with small clear faces qualifies', () {
      const couple = FaceSignals(
        count: 2,
        eyesOpenMin: 0.9,
        smileAverage: 0.8,
        largestFaceArea: 0.007,
        faceSharpness: 300,
        frameSharpness: 900,
      );
      expect(isMeaningfulMoment(_features(faces: couple)), isTrue);
    });

    test('a group needs less per face than one person', () {
      const group = FaceSignals(
        count: 5,
        eyesOpenMin: 0.9,
        smileAverage: 0.6,
        largestFaceArea: 0.0045,
        faceSharpness: 200,
        frameSharpness: 800,
      );
      expect(isMeaningfulMoment(_features(faces: group)), isTrue);
    });

    test('glasses or a big smile can lower the eye reading without a blink', () {
      const squint = FaceSignals(
        count: 2,
        eyesOpenMin: 0.38,
        smileAverage: 0.8,
        largestFaceArea: 0.007,
        faceSharpness: 300,
        frameSharpness: 900,
      );
      expect(isMeaningfulMoment(_features(faces: squint)), isTrue);
    });

    test('clearly closed eyes still rule a photo out', () {
      const blink = FaceSignals(
        count: 2,
        eyesOpenMin: 0.08,
        smileAverage: 0.8,
        largestFaceArea: 0.02,
        faceSharpness: 300,
        frameSharpness: 900,
      );
      expect(isMeaningfulMoment(_features(faces: blink)), isFalse);
      expect(
        momentProblems(_features(faces: blink)).join(' '),
        contains('eyes look closed'),
      );
    });

    test('a low eye reading with nobody smiling is still closed', () {
      const flat = FaceSignals(
        count: 1,
        eyesOpenMin: 0.38,
        smileAverage: 0.1,
        largestFaceArea: 0.02,
        faceSharpness: 300,
        frameSharpness: 900,
      );
      expect(isMeaningfulMoment(_features(faces: flat)), isFalse);
    });

    test('a tiny distant face does not count as a person', () {
      const tiny = FaceSignals(
        count: 1,
        eyesOpenMin: 0.9,
        smileAverage: 0.5,
        largestFaceArea: 0.0005,
      );
      expect(isMeaningfulMoment(_features(faces: tiny)), isFalse);
    });
  });
}
