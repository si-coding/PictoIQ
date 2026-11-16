import 'dart:typed_data';

/// A score at or above this means a picture is treated as sensitive.
const sensitiveThreshold = 0.6;

/// Decides whether a picture looks sexual, nude or otherwise sensitive, so it
/// is never shared or put in a reel. Everything runs on the phone.
///
/// Android's built-in labeller (ML Kit's default model) cannot do this: its
/// label list has no nudity or underwear labels, so a detector needs its own
/// model. Until one is bundled the app uses [NoSensitiveDetector] and relies
/// on photos the person marked as private.
abstract class SensitiveContentDetector {
  /// True when this detector can really recognise sensitive pictures.
  bool get isAvailable;

  /// 0 (fine) to 1 (sensitive) for an encoded image, or null when the picture
  /// could not be checked.
  Future<double?> score(Uint8List imageBytes);
}

/// The detector used when no model is bundled: it checks nothing.
class NoSensitiveDetector implements SensitiveContentDetector {
  const NoSensitiveDetector();

  @override
  bool get isAvailable => false;

  @override
  Future<double?> score(Uint8List imageBytes) async => null;
}
