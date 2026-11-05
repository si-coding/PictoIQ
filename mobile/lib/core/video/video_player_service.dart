/// Plays a video inside the app (preview and review). Not built yet.
abstract interface class VideoPlayerService {
  Future<void> open(String uri);
  Future<void> seek(Duration position);
  Future<void> dispose();
}
