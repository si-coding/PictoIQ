/// Heavy video work (trimming, stabilising, brightening) run off the UI
/// thread. Not built yet.
abstract interface class VideoProcessingService {
  Future<String> process(String uri, {required String operation});
}
