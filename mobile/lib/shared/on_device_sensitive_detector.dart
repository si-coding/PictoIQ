import 'dart:typed_data';

import 'package:flutter_nsfw_detector/flutter_nsfw_detector.dart';
import 'package:pictoiq_mobile/shared/sensitive_content.dart';

/// Loads the model once. Replaceable so tests need no phone.
typedef DetectorInitializer = Future<void> Function();

/// Scores an encoded picture from 0 (fine) to 1 (sensitive).
typedef DetectorScorer = Future<double> Function(Uint8List imageBytes);

Future<void> _initializeModel() => FlutterNsfwDetector.initialize();

Future<double> _scoreWithModel(Uint8List bytes) async {
  final result = await FlutterNsfwDetector.scanImageBytes(bytes: bytes);
  return result.nsfwScore;
}

/// Finds sexual or nude pictures with the small model that ships inside the
/// app (the `flutter_nsfw_detector` package, run by LiteRT on the phone). The
/// picture is never sent anywhere.
///
/// The model loads the first time it is needed. If it cannot load, the
/// detector reports itself unavailable and the app falls back to the photos
/// the person marked private.
class OnDeviceSensitiveDetector implements SensitiveContentDetector {
  OnDeviceSensitiveDetector({
    DetectorInitializer? initialize,
    DetectorScorer? scorer,
  }) : _initialize = initialize ?? _initializeModel,
       _scorer = scorer ?? _scoreWithModel;

  final DetectorInitializer _initialize;
  final DetectorScorer _scorer;
  Future<void>? _loading;
  bool _failed = false;

  @override
  bool get isAvailable => !_failed;

  @override
  Future<double?> score(Uint8List imageBytes) async {
    if (_failed) return null;
    try {
      await (_loading ??= _initialize());
    } catch (_) {
      _failed = true;
      return null;
    }
    try {
      return await _scorer(imageBytes);
    } catch (_) {
      return null;
    }
  }
}
