import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/scanned_files_page.dart';

FolderScanPhoto _photo(String name) => FolderScanPhoto(
  uri: 'content://test/$name',
  name: name,
  relativePath: name,
  size: 2048,
  modifiedAt: 1700000000000,
  sha256: 'x',
  visualHash: 0,
  qualityScore: 0,
  qualityNotes: const [],
  previewBytes: null,
);

void main() {
  testWidgets('shows counts, names, group badges and skipped files', (
    tester,
  ) async {
    final a = _photo('a.jpg');
    final b = _photo('b.jpg');
    final c = _photo('c.jpg');
    final scan = FolderScanResult(
      folderUri: 'content://test',
      folderName: 'Camera',
      imagesScanned: 3,
      duplicateGroups: [
        FolderDuplicateGroup(id: 'g', photos: [a, b]),
      ],
      bestShotsScan: false,
      dateRange: FolderDateRange.currentFolder,
      imagesSkipped: 1,
      imageFilesFound: 6,
      imagesOutsideDateRange: 2,
      scannedPhotos: [c, a, b],
      skippedNames: const ['broken.heic'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ScannedFilesPage(
          scan: scan,
          loadPreview: (_) async => null,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Image files found: 6'), findsOneWidget);
    expect(find.text('Scanned: 3'), findsOneWidget);
    expect(find.text('Left out by the date range: 2'), findsOneWidget);
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.text('Group 1'), findsNWidgets(2));
    expect(find.text('broken.heic'), findsOneWidget);

    await tester.tap(find.text('Not grouped (1)'));
    await tester.pump();
    expect(find.text('c.jpg'), findsOneWidget);
    expect(find.text('a.jpg'), findsNothing);
  });
}
