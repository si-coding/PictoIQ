import 'dart:typed_data';

import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart'
    show FolderScanPhoto;
import 'package:pictoiq_mobile/shared/sensitive_content.dart';

/// The result of checking photos before they are shared or put in a reel.
class ShareScreening {
  const ShareScreening({
    required this.clear,
    required this.blocked,
    this.unchecked = 0,
  });

  /// Photos that may be shared.
  final List<FolderScanPhoto> clear;

  /// Photos that must not be shared: marked private, or found sensitive.
  final List<FolderScanPhoto> blocked;

  /// How many photos the detector could not check (still in [clear]).
  final int unchecked;
}

/// Splits [photos] into the ones that may be shared and the ones that must
/// not. A photo is blocked when the person marked it private, or when
/// [detector] scores its picture as sensitive. [loadBytes] supplies the
/// encoded picture for the detector and is not called when the detector is
/// unavailable.
Future<ShareScreening> screenForSharing(
  List<FolderScanPhoto> photos, {
  required Set<String> markedPrivate,
  required SensitiveContentDetector detector,
  required Future<Uint8List?> Function(String uri) loadBytes,
}) async {
  final clear = <FolderScanPhoto>[];
  final blocked = <FolderScanPhoto>[];
  var unchecked = 0;
  for (final photo in photos) {
    if (markedPrivate.contains(photo.uri)) {
      blocked.add(photo);
      continue;
    }
    if (!detector.isAvailable) {
      clear.add(photo);
      continue;
    }
    double? score;
    try {
      final bytes = await loadBytes(photo.uri);
      score = bytes == null ? null : await detector.score(bytes);
    } catch (_) {
      score = null;
    }
    if (score == null) {
      unchecked++;
      clear.add(photo);
    } else if (score >= sensitiveThreshold) {
      blocked.add(photo);
    } else {
      clear.add(photo);
    }
  }
  return ShareScreening(clear: clear, blocked: blocked, unchecked: unchecked);
}
