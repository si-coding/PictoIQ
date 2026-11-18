import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/core/storage/private_photos.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/features/photos/library/photo_viewer_page.dart';
import 'package:pictoiq_mobile/features/photos/share/share_guard.dart';
import 'package:pictoiq_mobile/features/photos/share/sensitive_warning.dart';
import 'package:pictoiq_mobile/shared/sensitive_content.dart';

FolderScanPhoto _photo(String name) => FolderScanPhoto(
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
);

class _FakeDetector implements SensitiveContentDetector {
  _FakeDetector(this.scores);

  final Map<String, double?> scores;
  final checked = <String>[];

  @override
  bool get isAvailable => true;

  @override
  Future<double?> score(Uint8List imageBytes) async {
    final key = utf8.decode(imageBytes);
    checked.add(key);
    return scores[key];
  }
}

Future<Uint8List?> _bytesOf(String uri) async =>
    Uint8List.fromList(utf8.encode(uri.split('/').last));

void main() {
  group('screenForSharing', () {
    test('a photo already scored is not checked again', () async {
      final detector = _FakeDetector({'a.jpg': 0.1, 'b.jpg': 0.9});
      final cache = <String, double>{};
      final first = await screenForSharing(
        [_photo('a.jpg'), _photo('b.jpg')],
        markedPrivate: const {},
        detector: detector,
        loadBytes: _bytesOf,
        cache: cache,
      );
      expect(first.blocked.map((p) => p.name), ['b.jpg']);
      expect(cache.length, 2);
      final second = await screenForSharing(
        [_photo('a.jpg'), _photo('b.jpg')],
        markedPrivate: const {},
        detector: detector,
        loadBytes: _bytesOf,
        cache: cache,
      );
      expect(second.blocked.map((p) => p.name), ['b.jpg']);
      expect(detector.checked, ['a.jpg', 'b.jpg']);
    });

    test('photos marked private are blocked without being checked', () async {
      final detector = _FakeDetector({'ok.jpg': 0.0});
      final result = await screenForSharing(
        [_photo('ok.jpg'), _photo('secret.jpg')],
        markedPrivate: {'content://test/secret.jpg'},
        detector: detector,
        loadBytes: _bytesOf,
      );
      expect(result.clear.map((p) => p.name), ['ok.jpg']);
      expect(result.blocked.map((p) => p.name), ['secret.jpg']);
      expect(detector.checked, ['ok.jpg']);
    });

    test('a high score blocks a photo, a low one does not', () async {
      final result = await screenForSharing(
        [_photo('a.jpg'), _photo('b.jpg'), _photo('c.jpg')],
        markedPrivate: {},
        detector: _FakeDetector({'a.jpg': 0.95, 'b.jpg': 0.2, 'c.jpg': 0.6}),
        loadBytes: _bytesOf,
      );
      expect(result.blocked.map((p) => p.name), ['a.jpg', 'c.jpg']);
      expect(result.clear.map((p) => p.name), ['b.jpg']);
    });

    test('photos that could not be checked are kept and counted', () async {
      final result = await screenForSharing(
        [_photo('a.jpg'), _photo('b.jpg')],
        markedPrivate: {},
        detector: _FakeDetector({'a.jpg': null, 'b.jpg': 0.1}),
        loadBytes: (uri) async =>
            uri.endsWith('a.jpg') ? null : _bytesOf(uri),
      );
      expect(result.clear, hasLength(2));
      expect(result.unchecked, 1);
    });

    test('an unavailable detector is never asked to load anything', () async {
      var loads = 0;
      final result = await screenForSharing(
        [_photo('a.jpg')],
        markedPrivate: {},
        detector: const NoSensitiveDetector(),
        loadBytes: (uri) async {
          loads++;
          return null;
        },
      );
      expect(loads, 0);
      expect(result.clear, hasLength(1));
      expect(result.blocked, isEmpty);
    });
  });

  group('PrivatePhotoStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('private_photos'));
    tearDown(() => dir.deleteSync(recursive: true));

    PrivatePhotoStore store() => PrivatePhotoStore(directory: () async => dir);

    test('marks are saved and read back by a new store', () async {
      final first = store();
      await first.setPrivate('a', true);
      await first.setPrivate('b', true);
      await first.setPrivate('a', false);
      final second = store();
      await second.load();
      expect(second.contains('b'), isTrue);
      expect(second.contains('a'), isFalse);
      expect(second.all, {'b'});
    });

    test('a damaged file means nothing is marked', () async {
      File('${dir.path}/private_photos.json').writeAsStringSync('{not json');
      final s = store();
      await s.load();
      expect(s.all, isEmpty);
    });
  });

  group('warning dialog', () {
    Future<SensitiveChoice?> open(
      WidgetTester tester, {
      required int blocked,
      required int remaining,
      required String tap,
    }) async {
      SensitiveChoice? choice;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => choice = await showSensitiveWarning(
                context,
                blocked: blocked,
                remaining: remaining,
                action: 'share',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tap));
      await tester.pumpAndSettle();
      return choice;
    }

    testWidgets('says how many photos will not be shared', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSensitiveWarning(
                context,
                blocked: 2,
                remaining: 3,
                action: 'share',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('2 photos will not be shared'), findsOneWidget);
      expect(find.text('Continue with 3'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
    });

    testWidgets('Review and Continue are returned', (tester) async {
      expect(
        await open(tester, blocked: 1, remaining: 2, tap: 'Review'),
        SensitiveChoice.review,
      );
      expect(
        await open(tester, blocked: 1, remaining: 2, tap: 'Continue with 2'),
        SensitiveChoice.continueWithout,
      );
      expect(
        await open(tester, blocked: 1, remaining: 2, tap: 'Cancel'),
        isNull,
      );
    });

    testWidgets('there is nothing to continue with when all are blocked', (
      tester,
    ) async {
      await open(tester, blocked: 1, remaining: 0, tap: 'Cancel');
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSensitiveWarning(
                context,
                blocked: 1,
                remaining: 0,
                action: 'share',
              ),
              child: const Text('again'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('again'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Continue with'), findsNothing);
    });
  });

  testWidgets('the viewer can mark a photo private and undo it', (tester) async {
    final calls = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PhotoViewerPage(
          photos: [
            ViewerPhoto(
              title: 'a.jpg',
              preview: null,
              loadLarge: () async => null,
              onPrivateChanged: calls.add,
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.byTooltip('Mark as private (never shared)'));
    await tester.pump();
    expect(calls, [true]);
    await tester.tap(find.byTooltip('Private: never shared. Tap to undo'));
    await tester.pump();
    expect(calls, [true, false]);
  });
}
