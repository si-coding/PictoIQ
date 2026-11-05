import 'package:pictoiq_mobile/core/media/media_asset.dart';

/// What can be read from a file without analysing its content.
class MediaMetadata {
  const MediaMetadata({
    this.capturedAt,
    this.width,
    this.height,
    this.durationMs,
    this.latitude,
    this.longitude,
  });

  final DateTime? capturedAt;
  final int? width;
  final int? height;

  /// Videos only.
  final int? durationMs;
  final double? latitude;
  final double? longitude;
}

abstract interface class MediaMetadataService {
  Future<MediaMetadata> read(String uri, MediaKind kind);
}
