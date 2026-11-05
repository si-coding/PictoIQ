import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/clutter/clutter_classifier.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/shared/shot_ranking.dart';

FolderScanPhoto _photo(
  String name, {
  String? path,
  double sharpness = 200,
  double meanLuma = 120,
  double shadowClip = 0,
  double highlightClip = 0,
  double megapixels = 12,
  int faces = 0,
  bool document = false,
  int size = 1000,
  bool withFeatures = true,
}) => FolderScanPhoto(
  uri: 'content://test/$name',
  name: name,
  relativePath: path ?? name,
  size: size,
  modifiedAt: 1700000000000,
  sha256: null,
  visualHash: 0,
  qualityScore: 0,
  qualityNotes: const [],
  previewBytes: null,
  isDocument: document,
  features: withFeatures
      ? ShotFeatures(
          signals: ImageSignals(
            sharpness: sharpness,
            meanLuma: meanLuma,
            highlightClip: highlightClip,
            shadowClip: shadowClip,
          ),
          megapixels: megapixels,
          faces: FaceSignals(
            count: faces,
            eyesOpenMin: null,
            smileAverage: null,
          ),
        )
      : null,
);

void main() {
  group('looksLikeScreenshot', () {
    test('matches common Android screenshot names and folders', () {
      expect(looksLikeScreenshot('Screenshot_20260101-101010.png', 'a.png'), isTrue);
      expect(looksLikeScreenshot('Screen_Shot_1.png', 'a.png'), isTrue);
      expect(looksLikeScreenshot('screen-capture.png', 'a.png'), isTrue);
      expect(looksLikeScreenshot('x.png', 'Screenshots/x.png'), isTrue);
      expect(looksLikeScreenshot('IMG_1234.jpg', 'Camera/IMG_1234.jpg'), isFalse);
    });
  });

  group('clutterKindOf', () {
    test('a normal photo is not clutter', () {
      expect(clutterKindOf(_photo('IMG_1.jpg')), isNull);
    });

    test('screenshot by name wins over other reasons', () {
      final photo = _photo('Screenshot_1.png', document: true, sharpness: 1);
      expect(clutterKindOf(photo), ClutterKind.screenshot);
    });

    test('screenshot needs no analysis data', () {
      final photo = _photo('Screenshot_1.png', withFeatures: false);
      expect(clutterKindOf(photo), ClutterKind.screenshot);
    });

    test('document without faces', () {
      expect(clutterKindOf(_photo('scan.jpg', document: true)), ClutterKind.document);
    });

    test('document-like image with a face is not a document', () {
      expect(clutterKindOf(_photo('p.jpg', document: true, faces: 1)), isNull);
    });

    test('black and white frames are blank', () {
      expect(
        clutterKindOf(_photo('b.jpg', meanLuma: 5, shadowClip: 0.95)),
        ClutterKind.blank,
      );
      expect(
        clutterKindOf(_photo('w.jpg', meanLuma: 250, highlightClip: 0.95)),
        ClutterKind.blank,
      );
    });

    test('a very dark frame is blank even with a few lit pixels', () {
      expect(
        clutterKindOf(_photo('d.jpg', meanLuma: 25, shadowClip: 0.7)),
        ClutterKind.blank,
      );
    });

    test('a moderately dark photo is kept', () {
      expect(clutterKindOf(_photo('n.jpg', meanLuma: 60, shadowClip: 0.3)), isNull);
    });

    test('blurry when soft everywhere', () {
      expect(clutterKindOf(_photo('s.jpg', sharpness: 5)), ClutterKind.blurry);
    });

    test('a soft photo with a face is kept', () {
      expect(clutterKindOf(_photo('s.jpg', sharpness: 5, faces: 2)), isNull);
    });

    test('tiny images', () {
      expect(clutterKindOf(_photo('t.jpg', megapixels: 0.1)), ClutterKind.small);
      expect(clutterKindOf(_photo('t.jpg', megapixels: 2)), isNull);
    });

    test('thresholds can be changed', () {
      const strict = ClutterThresholds(blurrySharpness: 300);
      expect(
        clutterKindOf(_photo('s.jpg', sharpness: 200), thresholds: strict),
        ClutterKind.blurry,
      );
    });

    test('a photo with no analysis and no screenshot name is not clutter', () {
      expect(clutterKindOf(_photo('x.jpg', withFeatures: false)), isNull);
    });
  });

  group('findClutter', () {
    test('lists each photo once, grouped by kind, largest first', () {
      final items = findClutter([
        _photo('ok.jpg'),
        _photo('blur_small.jpg', sharpness: 1, size: 10),
        _photo('blur_big.jpg', sharpness: 1, size: 500),
        _photo('Screenshot_1.png', size: 50),
      ]);
      expect([for (final i in items) i.photo.name], [
        'Screenshot_1.png',
        'blur_big.jpg',
        'blur_small.jpg',
      ]);
      expect(items.first.kind, ClutterKind.screenshot);
    });

    test('returns nothing for a clean folder', () {
      expect(findClutter([_photo('a.jpg'), _photo('b.jpg')]), isEmpty);
    });
  });
}
