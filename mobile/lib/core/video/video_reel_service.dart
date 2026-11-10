import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class VideoReelService {
  static const _channel = MethodChannel('com.pictoiq.app/video_reel');
  static const _progressChannel = EventChannel(
    'com.pictoiq.app/video_reel/progress',
  );

  Stream<double> get progress => _progressChannel.receiveBroadcastStream().map(
    (event) => (event as num).toDouble(),
  );

  Future<void> cancelReelCreation() =>
      _channel.invokeMethod<void>('cancelBestMomentsReel');

  Future<String?> pickAudio() => _channel.invokeMethod<String>('pickReelAudio');

  Future<void> discardAudio(String path) =>
      _channel.invokeMethod<void>('discardReelAudio', {'audioPath': path});

  Future<String> createReel(
    List<String> imagePaths, {
    String? audioPath,
    required int secondsPerPhoto,
    required int transitionMillis,
    String title = '',
    required String titleStyle,
    bool Function()? isCancellationRequested,
    void Function()? onNativeCreationStarted,
  }) async {
    if (imagePaths.isEmpty) {
      throw ArgumentError.value(imagePaths, 'imagePaths', 'Must not be empty.');
    }

    final directory = await getTemporaryDirectory();
    final outputPath = p.join(
      directory.path,
      'pictoiq_best_moments_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    if (isCancellationRequested?.call() ?? false) {
      throw const ReelCreationCancelledException();
    }
    onNativeCreationStarted?.call();
    final String? resultPath;
    try {
      resultPath = await _channel.invokeMethod<String>(
        'createBestMomentsReel',
        {
          'imagePaths': imagePaths,
          'outputPath': outputPath,
          'audioPath': audioPath,
          'secondsPerPhoto': secondsPerPhoto,
          'transitionMillis': transitionMillis,
          'title': title,
          'titleStyle': titleStyle,
        },
      );
    } on PlatformException catch (error) {
      if (error.code == 'reel_creation_cancelled') {
        throw const ReelCreationCancelledException();
      }
      rethrow;
    }
    if (resultPath == null) {
      throw StateError('The video encoder did not return an output file.');
    }

    final output = File(resultPath);
    if (!await output.exists() || await output.length() == 0) {
      throw StateError('The video encoder did not create a usable reel.');
    }
    return resultPath;
  }
}

class ReelCreationCancelledException implements Exception {
  const ReelCreationCancelledException();
}
