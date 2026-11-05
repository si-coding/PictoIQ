/// Content fingerprints used to find exact copies (SHA-256 of the bytes).
/// Works for any file, so photos and videos share it.
abstract interface class MediaFingerprintService {
  Future<String> sha256(String uri);
}
