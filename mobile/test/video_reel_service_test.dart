import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/core/video/video_reel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  const reelChannel = MethodChannel('com.pictoiq.app/video_reel');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('pictoiq_reel_test');
    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      if (call.method == 'getTemporaryDirectory') return tempDirectory.path;
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    messenger.setMockMethodCallHandler(reelChannel, null);
    await tempDirectory.delete(recursive: true);
  });

  test('creates an MP4 from the supplied photo paths', () async {
    List<String>? receivedPaths;
    String? receivedAudioPath;
    Map<Object?, Object?>? receivedArguments;
    messenger.setMockMethodCallHandler(reelChannel, (call) async {
      expect(call.method, 'createBestMomentsReel');
      final arguments = call.arguments as Map<Object?, Object?>;
      receivedArguments = arguments;
      receivedPaths = (arguments['imagePaths'] as List<Object?>).cast<String>();
      receivedAudioPath = arguments['audioPath'] as String?;
      final outputPath = arguments['outputPath'] as String;
      await File(outputPath).writeAsBytes([1, 2, 3]);
      return outputPath;
    });

    final path = await VideoReelService().createReel(
      ['first.jpg', 'second.jpg'],
      audioPath: 'selected-audio.m4a',
      secondsPerPhoto: 5,
      transitionMillis: 750,
      title: 'Family trip',
      titleStyle: 'elegant',
    );

    expect(receivedPaths, ['first.jpg', 'second.jpg']);
    expect(receivedAudioPath, 'selected-audio.m4a');
    expect(receivedArguments?['secondsPerPhoto'], 5);
    expect(receivedArguments?['transitionMillis'], 750);
    expect(receivedArguments?['title'], 'Family trip');
    expect(receivedArguments?['titleStyle'], 'elegant');
    expect(path, endsWith('.mp4'));
    expect(await File(path).length(), 3);
  });

  test('rejects an empty selection before calling the platform', () async {
    await expectLater(
      VideoReelService().createReel(
        const [],
        secondsPerPhoto: 3,
        transitionMillis: 400,
        titleStyle: 'clean',
      ),
      throwsArgumentError,
    );
  });

  test('returns the audio file selected by Android', () async {
    messenger.setMockMethodCallHandler(reelChannel, (call) async {
      expect(call.method, 'pickReelAudio');
      return '/temporary/pictoiq_reel_audio_1';
    });

    expect(
      await VideoReelService().pickAudio(),
      '/temporary/pictoiq_reel_audio_1',
    );
  });

  test('maps native reel cancellation to a cancellation exception', () async {
    messenger.setMockMethodCallHandler(reelChannel, (call) async {
      if (call.method == 'createBestMomentsReel') {
        throw PlatformException(
          code: 'reel_creation_cancelled',
          message: 'Reel creation was cancelled.',
        );
      }
      return null;
    });

    await expectLater(
      VideoReelService().createReel(
        ['first.jpg'],
        secondsPerPhoto: 3,
        transitionMillis: 400,
        titleStyle: 'clean',
      ),
      throwsA(isA<ReelCreationCancelledException>()),
    );
  });

  test('sends reel cancellation to Android', () async {
    var cancellationRequested = false;
    messenger.setMockMethodCallHandler(reelChannel, (call) async {
      expect(call.method, 'cancelBestMomentsReel');
      cancellationRequested = true;
      return null;
    });

    await VideoReelService().cancelReelCreation();

    expect(cancellationRequested, isTrue);
  });
}
