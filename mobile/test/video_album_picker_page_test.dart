import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart';
import 'package:pictoiq_mobile/features/videos/library/video_album_picker_page.dart';

const _albums = [
  VideoAlbum(id: 'all', name: 'All videos', count: 40),
  VideoAlbum(id: 'cam', name: 'Camera', count: 25),
  VideoAlbum(id: 'one', name: 'Downloads', count: 1),
];

Widget _host(Widget page, void Function(Object?) onResult) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () async => onResult(
            await Navigator.of(context).push<Object>(
              MaterialPageRoute<Object>(builder: (_) => page),
            ),
          ),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

VideoAlbumPickerPage _page({
  Future<VideoAccess> Function()? access,
  Future<List<VideoAlbum>> Function()? albums,
  void Function()? onSettings,
}) => VideoAlbumPickerPage(
  requestAccess: access ?? () async => VideoAccess.granted,
  loadAlbums: albums ?? () async => _albums,
  loadCover: (_) async => null,
  openSettings: () async => onSettings?.call(),
);

Future<void> _open(WidgetTester tester, Widget page, [void Function(Object?)? r]) async {
  await tester.pumpWidget(_host(page, r ?? (_) {}));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists albums with counts and returns the chosen one', (
    tester,
  ) async {
    Object? result;
    await _open(tester, _page(), (value) => result = value);
    expect(find.text('All videos'), findsOneWidget);
    expect(find.text('40 videos'), findsOneWidget);
    expect(find.text('1 video'), findsOneWidget);

    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect((result as VideoAlbum).id, 'cam');
  });

  testWidgets('Other folder returns the folder choice', (tester) async {
    Object? result;
    await _open(tester, _page(), (value) => result = value);
    await tester.tap(find.text('Other folder…'));
    await tester.pumpAndSettle();
    expect(result, VideoPickerChoice.otherFolder);
  });

  testWidgets('denied access offers allow, settings and a folder', (
    tester,
  ) async {
    var settingsOpened = false;
    await _open(
      tester,
      _page(
        access: () async => VideoAccess.denied,
        onSettings: () => settingsOpened = true,
      ),
    );
    expect(find.text('Allow access'), findsOneWidget);
    expect(find.text('Choose a folder instead'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);
  });

  testWidgets('an empty library explains why and offers a folder', (
    tester,
  ) async {
    await _open(tester, _page(albums: () async => const []));
    expect(find.textContaining('No videos were found'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.text('Choose a folder instead'), findsOneWidget);
  });

  testWidgets('limited access with nothing shared says so', (tester) async {
    await _open(
      tester,
      _page(
        access: () async => VideoAccess.limited,
        albums: () async => const [],
      ),
    );
    expect(find.textContaining('chose to share'), findsOneWidget);
  });

  testWidgets('partial access offers to choose videos and shows the detail', (
    tester,
  ) async {
    var managed = 0;
    await _open(
      tester,
      VideoAlbumPickerPage(
        requestAccess: () async => VideoAccess.limited,
        loadAlbums: () async => const [],
        loadCover: (_) async => null,
        openSettings: () async {},
        manageLimited: () async => managed += 1,
        accessDetail: () => 'Android reports: limited. Video albums found: 0.',
      ),
    );
    expect(find.text('Android reports: limited. Video albums found: 0.'),
        findsOneWidget);
    await tester.tap(find.text('Choose videos to share'));
    await tester.pumpAndSettle();
    expect(managed, 1);
  });

  testWidgets('a failure can be retried', (tester) async {
    var calls = 0;
    await _open(
      tester,
      _page(
        albums: () async {
          calls += 1;
          if (calls == 1) throw StateError('boom');
          return _albums;
        },
      ),
    );
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Camera'), findsOneWidget);
  });
}
