import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class VideoReelService {
  static const _channel = MethodChannel('com.pictoiq.app/video_reel');

  Future<String?> pickAudio() => _channel.invokeMethod<String>('pickReelAudio');

  Future<String> createReel(
    List<String> imagePaths, {
    String? audioPath,
  }) async {
    if (imagePaths.isEmpty) {
      throw ArgumentError.value(imagePaths, 'imagePaths', 'Must not be empty.');
    }

    final directory = await getTemporaryDirectory();
    final outputPath = p.join(
      directory.path,
      'pictoiq_best_moments_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    final resultPath = await _channel.invokeMethod<String>(
      'createBestMomentsReel',
      {
        'imagePaths': imagePaths,
        'outputPath': outputPath,
        'audioPath': audioPath,
      },
    );
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
