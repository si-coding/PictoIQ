import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/features/scan/scan_configuration_page.dart';
import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart';

void main() {
  testWidgets('configuration keeps date range above album preview and scan', (
    tester,
  ) async {
    var settingsOpened = false;
    var privacyOpened = false;
    final folder = FolderSelection(
      uri: 'media:camera',
      name: 'Camera',
      albumId: 'camera',
      count: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ScanConfigurationPage(
          title: 'Best Moments',
          description: 'Find the photos worth sharing.',
          isVideo: false,
          initialDateRange: FolderDateRange.week,
          initialCustomRange: null,
          onDateRangeSelected: (range) async => null,
          initialPhotoFolder: folder,
          initialVideoAlbum: null,
          browsePhotoFolder: () async => folder,
          browseVideoAlbum: () async => null,
          loadPhotoGallery: (_) async => <Uint8List?>[null],
          loadVideoGallery: (_) async => const <VideoPreview>[],
          scanEnabled: true,
          scanLabel: 'Scan Best Moments',
          onSettings: () => settingsOpened = true,
          onPrivacy: () => privacyOpened = true,
          onScan: () async => false,
          onCancelScan: () {},
          scanProgressRevision: ValueNotifier(0),
          scanProgressBuilder: () => const Text('Analyzing photos…'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1. Choose a date range'), findsOneWidget);
    expect(find.text('PictoIQ'), findsOneWidget);
    expect(find.text('Best Moments'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Privacy'), findsOneWidget);
    expect(find.text('2. Browse your album or folder'), findsOneWidget);
    expect(find.text('3. Album preview · 1 recent item'), findsOneWidget);
    expect(find.text('Scan Best Moments'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('1. Choose a date range')).dy,
      lessThan(
        tester.getTopLeft(find.text('3. Album preview · 1 recent item')).dy,
      ),
    );
    await tester.tap(find.byTooltip('Settings'));
    expect(settingsOpened, isTrue);
    await tester.tap(find.byTooltip('Privacy'));
    expect(privacyOpened, isTrue);
  });

  testWidgets('scan stays disabled until an album or folder is chosen', (
    tester,
  ) async {
    final folder = FolderSelection(
      uri: 'media:camera',
      name: 'Camera',
      albumId: 'camera',
      count: 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ScanConfigurationPage(
          title: 'Exact Duplicates',
          description: 'Review identical photos.',
          isVideo: false,
          initialDateRange: FolderDateRange.week,
          initialCustomRange: null,
          onDateRangeSelected: (range) async => null,
          initialPhotoFolder: null,
          initialVideoAlbum: null,
          browsePhotoFolder: () async => folder,
          browseVideoAlbum: () async => null,
          loadPhotoGallery: (_) async => <Uint8List?>[null],
          loadVideoGallery: (_) async => const <VideoPreview>[],
          scanEnabled: true,
          scanLabel: 'Scan Exact Duplicates',
          onSettings: () {},
          onPrivacy: () {},
          onScan: () async => false,
          onCancelScan: () {},
          scanProgressRevision: ValueNotifier(0),
          scanProgressBuilder: () => const Text('Analyzing photos…'),
        ),
      ),
    );

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Scan Exact Duplicates'),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.text('Choose an album or folder'));
    await tester.pumpAndSettle();
    expect(find.text('3. Album preview · 1 recent item'), findsOneWidget);
    final selectedButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Scan Exact Duplicates'),
    );
    expect(selectedButton.onPressed, isNotNull);
  });

  testWidgets('scan progress keeps configuration visible and frozen', (
    tester,
  ) async {
    final folder = FolderSelection(
      uri: 'media:camera',
      name: 'Camera',
      albumId: 'camera',
      count: 1,
    );
    final scanCompletion = Completer<bool>();
    var cancelRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ScanConfigurationPage(
          title: 'Best Moments',
          description: 'Find the photos worth sharing.',
          isVideo: false,
          initialDateRange: FolderDateRange.week,
          initialCustomRange: null,
          onDateRangeSelected: (range) async => null,
          initialPhotoFolder: folder,
          initialVideoAlbum: null,
          browsePhotoFolder: () async => folder,
          browseVideoAlbum: () async => null,
          loadPhotoGallery: (_) async => <Uint8List?>[null],
          loadVideoGallery: (_) async => const <VideoPreview>[],
          scanEnabled: true,
          scanLabel: 'Scan Best Moments',
          onSettings: () {},
          onPrivacy: () {},
          onScan: () => scanCompletion.future,
          onCancelScan: () => cancelRequested = true,
          scanProgressRevision: ValueNotifier(0),
          scanProgressBuilder: () => const Text('Analyzing photos…'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan Best Moments'));
    await tester.pump();

    expect(find.text('1. Choose a date range'), findsOneWidget);
    expect(find.text('2. Browse your album or folder'), findsOneWidget);
    expect(find.text('3. Album preview · 1 recent item'), findsOneWidget);
    expect(find.text('Analyzing photos…'), findsOneWidget);
    expect(find.text('Cancel scan'), findsOneWidget);
    expect(find.text('Scan Best Moments'), findsNothing);

    await tester.tap(find.text('Cancel scan'));
    expect(cancelRequested, isTrue);
    scanCompletion.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Scan Best Moments'), findsOneWidget);
  });
}
