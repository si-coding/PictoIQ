import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart';
import 'package:pictoiq_mobile/features/videos/library/video_album_contents_page.dart';
import 'package:pictoiq_mobile/features/videos/library/video_album_picker_page.dart';

const _album = VideoAlbum(id: 'cam', name: 'Camera', count: 5);

Future<List<VideoPreview>> _load(int start, int end) async => [
  for (var i = start; i < end; i++)
    VideoPreview(
      thumbnail: null,
      durationSeconds: 65 + i,
      createdAt: DateTime(2026, 10, 1),
    ),
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

void main() {
  testWidgets('shows the videos with lengths and selects the album', (
    tester,
  ) async {
    Object? result;
    await tester.pumpWidget(
      _host(
        VideoAlbumContentsPage(album: _album, loadVideos: _load),
        (value) => result = value,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('5 videos · tap a video to play it'), findsOneWidget);
    expect(find.text('1:05'), findsOneWidget);
    expect(find.text('1:09'), findsOneWidget);

    await tester.tap(find.text('Select this album (5)'));
    await tester.pumpAndSettle();
    expect((result as VideoAlbum).id, 'cam');
  });

  testWidgets('loads more videos as the grid is scrolled', (tester) async {
    final requests = <(int, int)>[];
    const many = VideoAlbum(id: 'all', name: 'All videos', count: 200);
    await tester.pumpWidget(
      _host(
        VideoAlbumContentsPage(
          album: many,
          pageSize: 30,
          loadVideos: (start, end) {
            requests.add((start, end));
            return _load(start, end);
          },
        ),
        (_) {},
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(requests.first, (0, 30));
    await tester.drag(find.byType(GridView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(requests.length, greaterThan(1));
    expect(requests[1].$1, 30);
  });

  testWidgets('choosing an album in the picker opens its contents first', (
    tester,
  ) async {
    Object? result;
    await tester.pumpWidget(
      _host(
        VideoAlbumPickerPage(
          requestAccess: () async => VideoAccess.granted,
          loadAlbums: () async => const [_album],
          loadCover: (_) async => null,
          openSettings: () async {},
          loadVideos: (id, start, end) => _load(start, end),
        ),
        (value) => result = value,
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    // Nothing is chosen yet: the contents screen is showing.
    expect(result, isNull);
    expect(find.text('Select this album (5)'), findsOneWidget);

    await tester.tap(find.text('Select this album (5)'));
    await tester.pumpAndSettle();
    expect((result as VideoAlbum).id, 'cam');
  });
}
