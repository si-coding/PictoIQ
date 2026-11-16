/// Limits set by the owner of the app, changed here and released. They are not
/// shown in Settings and the person using the app cannot change them.
abstract final class AppLimits {
  /// Most photos shared at one time (best shots or best moments).
  static const int shareMaxPhotos = 9;

  /// Most photos in one reel.
  static const int reelMaxPhotos = 9;

  /// Most photos looked at in one scan. When a folder has more, the newest
  /// photos are scanned and the person is told how many were left out.
  static const int scanMaxPhotos = 500;
}
