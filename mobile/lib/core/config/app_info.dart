import 'package:package_info_plus/package_info_plus.dart';

/// Facts about the app shown to the person and used in the store listing.
/// The owner changes them here.
abstract final class AppInfo {
  static const name = 'PictoIQ';

  /// Shown in the app's About box. Copyright exists the moment the work is
  /// made; this notice just states it.
  static const copyright = '© 2026 PictoIQ All rights reserved.';

  /// Where people write about the app and its privacy policy.
  static const contactEmail = 'pictoiq@gmail.com';
}

/// "Version 1.0.0 (build 1)", from the app's own package information (the
/// `version:` line of pubspec.yaml). [load] is replaceable for tests.
Future<String> appVersionLabel([
  Future<PackageInfo> Function()? load,
]) async {
  try {
    final info = await (load ?? PackageInfo.fromPlatform)();
    final build = info.buildNumber.isEmpty ? '' : ' (build ${info.buildNumber})';
    return 'Version ${info.version}$build';
  } catch (_) {
    return 'Version unknown';
  }
}
