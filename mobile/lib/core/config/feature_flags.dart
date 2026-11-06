/// Switches for parts of the app that can be turned off in a build.
///
/// A flag is set when the app is built or run, with `--dart-define`:
///
/// ```
/// flutter run --dart-define=PICTOIQ_VIDEO=false
/// flutter build appbundle --dart-define=PICTOIQ_VIDEO=false
/// ```
///
/// Without a define, the value in [defaultVideoEnabled] is used. To change
/// the default for every build, edit that one line.
class FeatureFlags {
  const FeatureFlags({this.videoEnabled = defaultVideoEnabled});

  /// Videos on (true) or off (false) when no `PICTOIQ_VIDEO` define is given.
  static const bool defaultVideoEnabled = bool.fromEnvironment(
    'PICTOIQ_VIDEO',
    defaultValue: true,
  );

  /// The flags this build runs with.
  static const FeatureFlags current = FeatureFlags();

  /// Videos: the Photos | Videos switch on the home screen, the video
  /// scanning tools, and the Videos section in Settings. When false none of
  /// them are shown and no video code runs, so the app behaves as a photo
  /// app. The video permission (READ_MEDIA_VIDEO) is a separate manifest
  /// entry; see docs/play-release-checklist.md.
  final bool videoEnabled;
}
