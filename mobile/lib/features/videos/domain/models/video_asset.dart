/// A video on the device as the video tools see it. Not built yet.
class VideoAsset {
  const VideoAsset({
    required this.uri,
    required this.name,
    required this.duration,
    this.sizeBytes,
    this.createdAt,
  });

  final String uri;
  final String name;
  final Duration duration;
  final int? sizeBytes;
  final DateTime? createdAt;
}
