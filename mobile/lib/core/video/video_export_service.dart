/// Saves a processed video as a new file; the original is never changed.
/// Not built yet.
abstract interface class VideoExportService {
  Future<String> exportCopy(String processedUri, {String? name});
}
