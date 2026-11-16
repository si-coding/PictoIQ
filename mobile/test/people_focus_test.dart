import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/clutter/clutter_classifier.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/features/photos/library/photo_explain.dart';
import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/shared/photo_content.dart';
import 'package:pictoiq_mobile/shared/shot_ranking.dart';
import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

List<PhotoLabel> _labels(Map<String, double> values) => [
  for (final entry in values.entries) PhotoLabel(entry.key, entry.value),
];

FaceSignals _face({
  double? faceSharpness,
  double? frameSharpness,
  double area = 0.05,
}) => FaceSignals(
  count: 1,
  eyesOpenMin: 0.9,
  smileAverage: 0.8,
  largestFaceArea: area,
  faceSharpness: faceSharpness,
  frameSharpness: frameSharpness,
);

ShotInput _shot(String id, {required double frame, FaceSignals? faces}) =>
    ShotInput(
      id: id,
      tieBreaker: id,
      features: ShotFeatures(
        signals: ImageSignals(
          sharpness: frame,
          meanLuma: 120,
          highlightClip: 0,
          shadowClip: 0,
        ),
        megapixels: 12,
        faces: faces,
      ),
    );

FolderScanPhoto _photo(
  String name, {
  FaceSignals? faces,
  List<PhotoLabel>? labels,
  bool favorite = false,
  double sharpness = 200,
}) => FolderScanPhoto(
  uri: 'content://test/$name',
  name: name,
  relativePath: name,
  size: 1000,
  modifiedAt: 1700000000000,
  sha256: null,
  visualHash: 0,
  qualityScore: 0,
  qualityNotes: const [],
  previewBytes: null,
  isFavorite: favorite,
  features: ShotFeatures(
    signals: ImageSignals(
      sharpness: sharpness,
      meanLuma: 120,
      highlightClip: 0,
      shadowClip: 0,
    ),
    megapixels: 12,
    faces: faces ?? FaceSignals.none,
    labels: labels,
  ),
);

Uint8List _rgba(int width, int height, int Function(int x, int y) value) {
  final bytes = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final v = value(x, y);
      bytes[i] = v;
      bytes[i + 1] = v;
      bytes[i + 2] = v;
      bytes[i + 3] = 255;
    }
  }
  return bytes;
}

void main() {
  group('regionSharpness', () {
    test('a sharp pattern scores far higher than a smooth one', () {
      final sharp = _rgba(64, 64, (x, y) => ((x + y).isEven) ? 0 : 255);
      final smooth = _rgba(64, 64, (x, y) => 120 + x ~/ 8);
      final sharpScore = regionSharpness(sharp, 64, 64, 0, 0, 64, 64)!;
      final smoothScore = regionSharpness(smooth, 64, 64, 0, 0, 64, 64)!;
      expect(sharpScore, greaterThan(smoothScore * 100));
    });

    test('a region that is too small is not measured', () {
      final pixels = _rgba(64, 64, (x, y) => 100);
      expect(regionSharpness(pixels, 64, 64, 10, 10, 14, 14), isNull);
    });

    test('measures only the requested region', () {
      // Sharp on the left half, flat on the right half.
      final pixels = _rgba(64, 64, (x, y) => x < 32 ? ((x + y).isEven ? 0 : 255) : 128);
      final left = regionSharpness(pixels, 64, 64, 1, 1, 30, 63)!;
      final right = regionSharpness(pixels, 64, 64, 34, 1, 63, 63)!;
      expect(left, greaterThan(right));
    });
  });

  group('isAboutPeople', () {
    test('a clear face is enough', () {
      expect(
        isAboutPeople(faceCount: 1, labels: _labels({'Stool': 0.9})),
        isTrue,
      );
    });

    test('scenery alone does not count', () {
      expect(
        isAboutPeople(faceCount: 0, labels: _labels({'Sky': 0.95})),
        isFalse,
      );
    });

    test('people beside a bigger object do not count, beside a small one do', () {
      expect(
        isAboutPeople(
          faceCount: 0,
          labels: _labels({'Person': 0.65, 'Projection screen': 0.95}),
        ),
        isFalse,
      );
      expect(
        isAboutPeople(
          faceCount: 0,
          labels: _labels({'Person': 0.9, 'Table': 0.7}),
        ),
        isTrue,
      );
    });

    test('unknown is kept, nothing recognised is not', () {
      expect(isAboutPeople(faceCount: null, labels: null), isTrue);
      expect(isAboutPeople(faceCount: 0, labels: const []), isFalse);
    });
  });

  group('face focus in the ranking', () {
    test('a soft face loses to a sharp face even on a crisp background', () {
      final ranking = rankShots([
        _shot('soft', frame: 200, faces: _face(faceSharpness: 5, frameSharpness: 200)),
        _shot('sharp', frame: 150, faces: _face(faceSharpness: 100, frameSharpness: 150)),
      ]);
      expect(ranking.best.id, 'sharp');
      final soft = ranking.shotFor('soft')!;
      expect(soft.disqualifiers, contains('the face is out of focus'));
      expect(ranking.best.strengths, contains('Face is the sharpest in the group'));
    });

    test('without face measurements the ranking is unchanged', () {
      final ranking = rankShots([
        _shot('a', frame: 200, faces: _face()),
        _shot('b', frame: 150, faces: _face()),
      ]);
      expect(ranking.best.id, 'a');
      expect(ranking.shotFor('b')!.disqualifiers, isEmpty);
    });

    test('similar face sharpness raises no fault', () {
      final ranking = rankShots([
        _shot('a', frame: 200, faces: _face(faceSharpness: 90, frameSharpness: 200)),
        _shot('b', frame: 190, faces: _face(faceSharpness: 80, frameSharpness: 190)),
      ]);
      expect(ranking.shotFor('a')!.disqualifiers, isEmpty);
      expect(ranking.shotFor('b')!.disqualifiers, isEmpty);
    });
  });

  group('unclear people clutter', () {
    test('a very soft face is unclear', () {
      final photo = _photo(
        'a.jpg',
        faces: _face(faceSharpness: 1, frameSharpness: 20),
      );
      expect(clutterKindOf(photo), ClutterKind.unclearPeople);
    });

    test('focus behind the person is unclear', () {
      final photo = _photo(
        'a.jpg',
        faces: _face(faceSharpness: 8, frameSharpness: 200),
      );
      expect(clutterKindOf(photo), ClutterKind.unclearPeople);
    });

    test('a sharp face is a normal photo', () {
      final photo = _photo(
        'a.jpg',
        faces: _face(faceSharpness: 60, frameSharpness: 200),
      );
      expect(clutterKindOf(photo), isNull);
    });

    test('a tiny distant face is not judged', () {
      final photo = _photo(
        'a.jpg',
        faces: _face(faceSharpness: 0.5, frameSharpness: 200, area: 0.0005),
      );
      expect(clutterKindOf(photo), isNull);
    });

    test('faces that were not measured are never unclear', () {
      expect(clutterKindOf(_photo('a.jpg', faces: _face())), isNull);
    });

    test('a favourite is never listed as clutter', () {
      final unclear = _photo(
        'a.jpg',
        favorite: true,
        faces: _face(faceSharpness: 1, frameSharpness: 20),
      );
      expect(findClutter([unclear]), isEmpty);
      expect(
        findClutter([_photo('b.jpg', faces: _face(faceSharpness: 1, frameSharpness: 20))]),
        hasLength(1),
      );
    });
  });

  group('settings and explanation', () {
    test('people only is a stored content filter', () {
      expect(ContentFilter.values, contains(ContentFilter.peopleOnly));
      final json = const AppSettings(contentFilter: ContentFilter.peopleOnly).toJson();
      expect(AppSettings.fromJson(json).contentFilter, ContentFilter.peopleOnly);
    });

    test('the explanation lists labels, faces and favourites', () {
      final photo = _photo(
        'stool.jpg',
        favorite: true,
        faces: FaceSignals.none,
        labels: _labels({'Stool': 0.82, 'Grass': 0.7}),
      );
      final text = explainPhoto(photo).join('\n');
      expect(text, contains('favourite'));
      expect(text, contains('no faces found'));
      expect(text, contains('Stool 82%'));
      expect(text, contains('objects 82%'));
      expect(text, contains('scenery 70%'));
    });

    test('a scan without analysis explains nothing', () {
      const photo = FolderScanPhoto(
        uri: 'x',
        name: 'x',
        relativePath: 'x',
        size: 1,
        modifiedAt: 0,
        sha256: 'abc',
        visualHash: 0,
        qualityScore: 0,
        qualityNotes: [],
        previewBytes: null,
      );
      expect(explainPhoto(photo), isEmpty);
    });
  });
}
