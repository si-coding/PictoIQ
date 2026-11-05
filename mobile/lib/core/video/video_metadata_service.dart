/// Duration, size, frame rate and creation time of a video. Not built yet.
class VideoMetadata {
  const VideoMetadata({
    required this.duration,
    this.width,
    this.height,
    this.framesPerSecond,
    this.createdAt,
  });

  final Duration duration;
  final int? width;
  final int? height;
  final double? framesPerSecond;
  final DateTime? createdAt;
}

abstract interface class VideoMetadataService {
  Future<VideoMetadata> read(String uri);
}
