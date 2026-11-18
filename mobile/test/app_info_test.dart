import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pictoiq_mobile/core/config/app_info.dart';

PackageInfo _info(String version, String build) => PackageInfo(
  appName: 'PictoIQ',
  packageName: 'com.pictoiq.app',
  version: version,
  buildNumber: build,
);

void main() {
  test('version label shows version and build number', () async {
    expect(
      await appVersionLabel(() async => _info('1.0.0', '1')),
      'Version 1.0.0 (build 1)',
    );
    expect(
      await appVersionLabel(() async => _info('2.1.0', '')),
      'Version 2.1.0',
    );
  });

  test('version label survives a failed lookup', () async {
    expect(
      await appVersionLabel(() async => throw StateError('no platform')),
      'Version unknown',
    );
  });

  test('owner facts are set', () {
    expect(AppInfo.contactEmail, 'pictoiq@gmail.com');
    expect(AppInfo.copyright, contains('All rights reserved'));
  });
}
