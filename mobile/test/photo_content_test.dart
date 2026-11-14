import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/shared/photo_content.dart';
import 'package:pictoiq_mobile/shared/shot_ranking.dart';

List<PhotoLabel> l(Map<String, double> m) => [
  for (final e in m.entries) PhotoLabel(e.key, e.value),
];

void main() {
  test('faces always mean a people photo', () {
    expect(
      isPeopleOrScenery(faceCount: 2, labels: l({'Document': 0.99})),
      isTrue,
    );
  });

  test('unknown is kept', () {
    expect(isPeopleOrScenery(faceCount: null, labels: null), isTrue);
    expect(isPeopleOrScenery(faceCount: 0, labels: const []), isTrue);
  });

  test('scenery is kept even when an object is also seen', () {
    expect(
      isPeopleOrScenery(
        faceCount: 0,
        labels: l({'Sky': 0.9, 'Car': 0.8}),
      ),
      isTrue,
    );
  });

  test('documents, screens and objects are left out', () {
    expect(
      isPeopleOrScenery(faceCount: 0, labels: l({'Text': 0.9, 'Font': 0.8})),
      isFalse,
    );
    expect(
      isPeopleOrScenery(
        faceCount: 0,
        labels: l({'Projection screen': 0.7, 'Technology': 0.6}),
      ),
      isFalse,
    );
    expect(isPeopleOrScenery(faceCount: 0, labels: l({'Food': 0.8})), isFalse);
  });

  test('weak object guesses do not hide a photo', () {
    expect(isPeopleOrScenery(faceCount: 0, labels: l({'Table': 0.4})), isTrue);
  });
  test('the subject decides: a far-off speaker behind a big screen is a screen',
      () {
    expect(
      isPeopleOrScenery(
        faceCount: 0,
        labels: l({'Crowd': 0.7, 'Display device': 0.9, 'Technology': 0.8}),
      ),
      isFalse,
    );
    expect(
      isPeopleOrScenery(
        faceCount: 0,
        labels: l({'Crowd': 0.85, 'Display device': 0.8}),
      ),
      isTrue,
    );
  });

  test('a tiny face does not make a photo a people photo', () {
    expect(
      const FaceSignals(
        count: 1,
        eyesOpenMin: null,
        smileAverage: null,
        largestFaceArea: 0.0004,
      ).hasProminentFace,
      isFalse,
    );
    expect(
      const FaceSignals(
        count: 1,
        eyesOpenMin: null,
        smileAverage: null,
        largestFaceArea: 0.03,
      ).hasProminentFace,
      isTrue,
    );
    expect(FaceSignals.none.hasProminentFace, isFalse);
  });
}
