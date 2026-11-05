import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/library/album_picker_page.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';

const _albums = [
  MediaAlbum(id: 'all', name: 'All photos', count: 3200),
  MediaAlbum(id: 'cam', name: 'Camera', count: 1800),
  MediaAlbum(id: 'one', name: 'Screenshots', count: 1),
];

Widget _host(
  Widget page,
  void Function(Object?) onResult,
) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async =>
              onResult(await Navigator.of(context).push<Object>(
                MaterialPageRoute<Object>(builder: (_) => page),
              )),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

AlbumPickerPage _page({
  Future<bool> Function()? access,
  Future<List<MediaAlbum>> Function()? albums,
  void Function()? onSettings,
}) => AlbumPickerPage(
  requestAccess: access ?? () async => true,
  loadAlbums: albums ?? () async => _albums,
  loadCover: (_) async => null,
  loadThumbnails: (id, start, end) async =>
      List<Uint8List?>.filled(end - start, null),
  loadPhoto: (id, index) async => null,
  openSettings: () async => onSettings?.call(),
);

void main() {
  testWidgets('opening an album shows its photos and selecting needs a tap', (
    tester,
  ) async {
    Object? result;
    await tester.pumpWidget(_host(_page(), (value) => result = value));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    // Nothing is chosen yet: the contents screen is showing.
    expect(result, isNull);
    expect(find.text('Select this album (1800)'), findsOneWidget);
    expect(find.textContaining('tap a photo to enlarge'), findsOneWidget);

    await tester.tap(find.text('Select this album (1800)'));
    await tester.pumpAndSettle();
    final chosen = result as FolderSelection;
    expect(chosen.uri, '${FolderDuplicateScanner.albumPrefix}cam');
  });

  testWidgets('going back from an album keeps the list open', (tester) async {
    Object? result;
    await tester.pumpWidget(_host(_page(), (value) => result = value));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Choose an album'), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets('lists albums with counts and returns the chosen one', (
    tester,
  ) async {
    Object? result;
    await tester.pumpWidget(_host(_page(), (value) => result = value));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('All photos'), findsOneWidget);
    expect(find.text('3200 photos'), findsOneWidget);
    expect(find.text('1 photo'), findsOneWidget);

    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Select this album'));
    await tester.pumpAndSettle();
    final chosen = result as FolderSelection;
    expect(chosen.name, 'Camera');
    expect(chosen.uri, '${FolderDuplicateScanner.albumPrefix}cam');
  });

  testWidgets('explains a refusal and offers settings and the folder picker', (
    tester,
  ) async {
    var settingsOpened = false;
    Object? result;
    await tester.pumpWidget(
      _host(
        _page(access: () async => false, onSettings: () => settingsOpened = true),
        (value) => result = value,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('needs permission'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    expect(settingsOpened, isTrue);

    await tester.tap(find.text('Choose a folder instead'));
    await tester.pumpAndSettle();
    expect(result, AlbumPickerChoice.otherFolder);
  });

  testWidgets('can retry after a failure', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        _page(
          albums: () async {
            calls++;
            if (calls == 1) throw StateError('boom');
            return _albums;
          },
        ),
        (_) {},
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be loaded'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
  });

  testWidgets('"Other folder…" in the app bar picks the folder picker', (
    tester,
  ) async {
    Object? result;
    await tester.pumpWidget(_host(_page(), (value) => result = value));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other folder…'));
    await tester.pumpAndSettle();
    expect(result, AlbumPickerChoice.otherFolder);
  });
}
