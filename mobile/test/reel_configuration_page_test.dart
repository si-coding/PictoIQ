import 'dart:async';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart';
import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/features/videos/export/reel_configuration_page.dart';
import 'package:pictoiq_mobile/core/video/video_reel_service.dart';

void main() {
  FolderScanPhoto photo(String uri) => FolderScanPhoto(
    uri: uri,
    name: uri.split('/').last,
    relativePath: uri.split('/').last,
    size: 1,
    modifiedAt: 1,
    sha256: 'hash-$uri',
    visualHash: 0,
    qualityScore: 0,
    qualityNotes: const [],
    previewBytes: null,
  );

  Widget page({
    required List<FolderScanPhoto> photos,
    required Stream<double> progress,
    required Future<void> Function(ReelConfiguration) onCreate,
    Future<void> Function()? onCancel,
  }) => MaterialApp(
    home: ReelConfigurationPage(
      photos: photos,
      maxPhotos: 15,
      secondsPerPhoto: 3,
      transitionMillis: 400,
      titleStyle: ReelTitleStyle.clean,
      pickAudio: () async => null,
      discardAudio: (_) async {},
      reelProgress: progress,
      onCreate: onCreate,
      onCancel: onCancel ?? () async {},
    ),
  );

  testWidgets('shows reel progress without leaving the editor', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final progress = StreamController<double>.broadcast();
    final creation = Completer<void>();
    addTearDown(progress.close);
    await tester.pumpWidget(
      page(
        photos: [photo('file:///photo.jpg')],
        progress: progress.stream,
        onCreate: (_) => creation.future,
      ),
    );

    await tester.ensureVisible(find.text('Create reel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create reel'));
    await tester.pump();
    expect(find.text('Create your reel'), findsOneWidget);
    expect(find.text('Preparing your reel…'), findsOneWidget);

    progress.add(.42);
    await tester.pump();

    expect(find.text('Creating your reel… 42%'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator).last,
    );
    expect(bar.value, .42);
    expect(find.text('Create your reel'), findsOneWidget);

    creation.complete();
    await tester.pumpAndSettle();
    expect(find.text('Create your reel'), findsOneWidget);
  });

  testWidgets('dragging a photo onto another photo changes their order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final progress = StreamController<double>.broadcast();
    addTearDown(progress.close);
    const firstUri = 'file:///first.jpg';
    const secondUri = 'file:///second.jpg';

    await tester.pumpWidget(
      page(
        photos: [photo(firstUri), photo(secondUri)],
        progress: progress.stream,
        onCreate: (_) async {},
      ),
    );

    final firstFinder = find.byKey(const ValueKey('reel-photo-$firstUri'));
    final secondFinder = find.byKey(const ValueKey('reel-photo-$secondUri'));
    final firstBefore = tester.getCenter(firstFinder);
    final secondBefore = tester.getCenter(secondFinder);
    final gesture = await tester.startGesture(firstBefore);
    await tester.pump(kLongPressTimeout);
    await gesture.moveTo(secondBefore);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getCenter(firstFinder).dx, greaterThan(secondBefore.dx - 1));
    expect(tester.getCenter(secondFinder).dx, lessThan(firstBefore.dx + 1));
  });

  testWidgets('Cancel requests cancellation while keeping the editor open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final progress = StreamController<double>.broadcast();
    addTearDown(progress.close);
    var cancelRequested = false;
    final creation = Completer<void>();

    await tester.pumpWidget(
      page(
        photos: [photo('file:///photo.jpg')],
        progress: progress.stream,
        onCreate: (_) => creation.future,
        onCancel: () async {
          cancelRequested = true;
          creation.completeError(const ReelCreationCancelledException());
        },
      ),
    );

    await tester.ensureVisible(find.text('Create reel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create reel'));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(cancelRequested, isTrue);
    expect(find.text('Create your reel'), findsOneWidget);
    expect(
      find.text('Could not create the reel. Please try again.'),
      findsNothing,
    );
  });

  testWidgets('the whole page scrolls so every photo preview can be reached', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final progress = StreamController<double>.broadcast();
    addTearDown(progress.close);
    final photos = [
      for (var index = 0; index < 15; index++)
        photo('file:///photo-$index.jpg'),
    ];

    await tester.pumpWidget(
      page(photos: photos, progress: progress.stream, onCreate: (_) async {}),
    );

    expect(find.text('Text on the first photo (optional)'), findsOneWidget);
    expect(find.text('Photo preview · drag to reorder'), findsOneWidget);
    expect(find.byType(Scrollbar), findsOneWidget);

    final lastPhoto = find.byKey(
      const ValueKey('reel-photo-file:///photo-14.jpg'),
    );
    await tester.scrollUntilVisible(
      lastPhoto,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(lastPhoto, findsOneWidget);
    expect(find.text('Create reel'), findsOneWidget);
  });
}
