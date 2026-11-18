import 'dart:typed_data';

import 'package:pictoiq_mobile/features/photos/duplicates/folder_duplicate_scanner.dart'
    show FolderScanPhoto, ScanCancelled;
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
  Map<String, double>? cache,
  void Function(int done)? onProgress,
  bool Function()? shouldCancel,
}) async {
  final clear = <FolderScanPhoto>[];
  final blocked = <FolderScanPhoto>[];
  var unchecked = 0;
  // Loading and shrinking each picture is the slow part, so a few are loaded
  // at once; the detector itself is still called one picture at a time.
  const batchSize = 4;
  for (var start = 0; start < photos.length; start += batchSize) {
    final batch = photos.sublist(
      start,
      start + batchSize > photos.length ? photos.length : start + batchSize,
    );
    if (shouldCancel?.call() ?? false) throw const ScanCancelled();
    final loading = <Future<Uint8List?>?>[
      for (final photo in batch)
        markedPrivate.contains(photo.uri) ||
                !detector.isAvailable ||
                (cache?.containsKey(photo.uri) ?? false)
            ? null
            : loadBytes(photo.uri).then<Uint8List?>(
                (bytes) => bytes,
                onError: (Object _) => null,
              ),
    ];
    for (var i = 0; i < batch.length; i++) {
      final photo = batch[i];
      if (markedPrivate.contains(photo.uri)) {
        blocked.add(photo);
        continue;
      }
      if (!detector.isAvailable) {
        clear.add(photo);
        continue;
      }
      double? score = cache?[photo.uri];
      if (score == null) {
        try {
          final bytes = await loading[i];
          score = bytes == null ? null : await detector.score(bytes);
        } catch (_) {
          score = null;
        }
        if (score != null) cache?[photo.uri] = score;
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
    onProgress?.call(start + batch.length);
  }
  return ShareScreening(clear: clear, blocked: blocked, unchecked: unchecked);
}
