import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/features/photos/share/share_preview_page.dart';

FolderScanPhoto _photo(String name) => FolderScanPhoto(
  uri: name,
  name: name,
  relativePath: name,
  size: 1,
  modifiedAt: 0,
  sha256: null,
  visualHash: 0,
  qualityScore: 50,
  qualityNotes: const [],
  previewBytes: null,
);

void main() {
  testWidgets('removing a photo changes what is shared', (tester) async {
    List<FolderScanPhoto>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await Navigator.of(context)
                .push<List<FolderScanPhoto>>(
                  MaterialPageRoute(
                    builder: (_) => SharePreviewPage(
                      photos: [_photo('a'), _photo('b'), _photo('c')],
                    ),
                  ),
                ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Share 3 photos'), findsOneWidget);

    await tester.tap(find.byTooltip('Do not share this photo').first);
    await tester.pump();
    expect(find.text('Share 2 photos'), findsOneWidget);

    await tester.tap(find.text('Share 2 photos'));
    await tester.pumpAndSettle();
    expect(result!.map((p) => p.uri), ['b', 'c']);
  });

  testWidgets('going back shares nothing', (tester) async {
    var popped = false;
    List<FolderScanPhoto>? result = [_photo('x')];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<List<FolderScanPhoto>>(
                MaterialPageRoute(
                  builder: (_) => SharePreviewPage(photos: [_photo('a')]),
                ),
              );
              popped = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(result, isNull);
  });

  testWidgets('more than the limit shows a warning and only the top are sent',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    List<FolderScanPhoto>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await Navigator.of(context)
                .push<List<FolderScanPhoto>>(
                  MaterialPageRoute(
                    builder: (_) => SharePreviewPage(
                      photos: [for (var i = 0; i < 12; i++) _photo('p$i')],
                      noun: 'best moments',
                      maxPhotos: 9,
                    ),
                  ),
                ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('allows only 9 best moments'),
      findsOneWidget,
    );
    expect(find.text('Share 9 photos'), findsOneWidget);
    expect(find.text('Not included'), findsNWidgets(3));

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Do not share this photo').last);
      await tester.pump();
    }
    expect(find.textContaining('allows only'), findsNothing);
    expect(find.text('Not included'), findsNothing);
    await tester.tap(find.text('Share 9 photos'));
    await tester.pumpAndSettle();
    expect(result, hasLength(9));
  });
}
