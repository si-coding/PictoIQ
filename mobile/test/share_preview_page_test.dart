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
}
