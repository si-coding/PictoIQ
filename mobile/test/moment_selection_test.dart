import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/best_moments/moment_selection.dart';
import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

MomentPhoto photo(
  String id,
  double score, {
  int hash = 0,
  int? faces = 2,
  double? smile,
  bool disqualified = false,
}) => MomentPhoto(
  id: id,
  baseScore: score,
  visualHash: hash,
  faceCount: faces,
  smile: smile,
  disqualified: disqualified,
);

void main() {
  test('compositionOf names the kind of photo', () {
    expect(compositionOf(null), Composition.unknown);
    expect(compositionOf(0), Composition.noFaces);
    expect(compositionOf(1), Composition.single);
    expect(compositionOf(2), Composition.couple);
    expect(compositionOf(5), Composition.group);
  });

  test('compositionsConflict separates portraits, couples and groups', () {
    expect(compositionsConflict(1, 2), isTrue);
    expect(compositionsConflict(2, 4), isTrue);
    expect(compositionsConflict(3, 6), isFalse);
    expect(compositionsConflict(null, 2), isFalse);
  });

  test('the best photo is first and count limits the result', () {
    final photos = [photo('a', 0.5), photo('b', 0.9), photo('c', 0.7)];
    expect(
      chooseMomentPhotos(photos, count: 1, variety: MomentVariety.off),
      ['b'],
    );
    expect(
      chooseMomentPhotos(photos, count: 3, variety: MomentVariety.off),
      ['b', 'c', 'a'],
    );
    expect(chooseMomentPhotos(const [], count: 2), isEmpty);
  });

  test('variety prefers a different photo over a near-twin', () {
    final photos = [
      photo('best', 0.90, hash: 0),
      photo('twin', 0.88, hash: 0),
      photo('other', 0.80, hash: 0xFFFFFF),
    ];
    expect(
      chooseMomentPhotos(photos, count: 2, variety: MomentVariety.off),
      ['best', 'twin'],
    );
    expect(
      chooseMomentPhotos(photos, count: 2, variety: MomentVariety.strong),
      ['best', 'other'],
    );
  });

  test('a different couple in the moment is not shown next to the best photo', () {
    List<double> bin(int i) => [for (var k = 0; k < 64; k++) k == i ? 1.0 : 0.0];
    MomentPhoto couple(String id, double score, int a, int b, int hash) =>
        MomentPhoto(
          id: id,
          baseScore: score,
          visualHash: hash,
          faceCount: 2,
          people: [bin(a), bin(b)],
        );
    final photos = [
      couple('best', 0.9, 1, 2, 0),
      couple('same', 0.7, 1, 2, 0xFFFFF),
      couple('other', 0.8, 30, 31, 0xFFFFFF),
    ];
    expect(chooseMomentPhotos(photos, count: 2, clothingLimit: 0.18), [
      'best',
      'same',
    ]);
    // Never fewer photos than asked for: the other couple fills the last slot.
    expect(chooseMomentPhotos(photos, count: 3, clothingLimit: 0.18), [
      'best',
      'same',
      'other',
    ]);
    expect(
      chooseMomentPhotos(photos, count: 2, variety: MomentVariety.off),
      ['best', 'other'],
    );
  });

  test('a faulty photo is only chosen when no clean one is left', () {
    final photos = [
      photo('fault', 0.9, disqualified: true),
      photo('clean', 0.6),
    ];
    expect(chooseMomentPhotos(photos, count: 2).first, 'clean');
    expect(chooseMomentPhotos(photos, count: 2), ['clean', 'fault']);
  });

  test('a group photo with someone blinking loses to one with eyes open', () {
    final photos = [
      MomentPhoto(
        id: 'blink',
        baseScore: 0.80,
        visualHash: 0,
        faceCount: 5,
        eyesOpen: 0.1,
      ),
      MomentPhoto(
        id: 'open',
        baseScore: 0.76,
        visualHash: 0,
        faceCount: 5,
        eyesOpen: 0.95,
      ),
    ];
    expect(
      chooseMomentPhotos(photos, count: 1, variety: MomentVariety.off),
      ['open'],
    );
  });

  test('a cut-off face counts against a portrait', () {
    final photos = [
      MomentPhoto(
        id: 'cut',
        baseScore: 0.80,
        visualHash: 0,
        faceCount: 1,
        edgeCutoff: true,
      ),
      MomentPhoto(id: 'whole', baseScore: 0.75, visualHash: 0, faceCount: 1),
    ];
    expect(
      chooseMomentPhotos(photos, count: 1, variety: MomentVariety.off),
      ['whole'],
    );
  });

  test('expression setting changes how much smiles count', () {
    final photos = [
      photo('posed', 0.50, smile: 1.0),
      photo('candid', 0.55, smile: 0.0),
    ];
    String first(MomentExpression e) => chooseMomentPhotos(
      photos,
      count: 1,
      variety: MomentVariety.off,
      expression: e,
    ).first;
    expect(first(MomentExpression.candid), 'candid');
    expect(first(MomentExpression.smiles), 'posed');
  });
}
