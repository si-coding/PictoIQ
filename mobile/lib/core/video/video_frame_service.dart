import 'dart:typed_data';

/// Pulls still frames out of a video so the photo engines (similarity,
/// quality, moments) can judge it. Not built yet.
abstract interface class VideoFrameService {
  Future<List<Uint8List>> framesAt(String uri, List<Duration> positions);
}
