import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/core/config/feature_flags.dart';
import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/features/settings/settings_page.dart';

Future<void> _showSettings(
  WidgetTester tester, {
  required bool showVideoSettings,
}) async {
  tester.view.physicalSize = const Size(800, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsPage(
        initial: const AppSettings(),
        onChanged: (_) {},
        showVideoSettings: showVideoSettings,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('FeatureFlags', () {
    test('a flag can be set directly', () {
      expect(const FeatureFlags(videoEnabled: false).videoEnabled, isFalse);
      expect(const FeatureFlags(videoEnabled: true).videoEnabled, isTrue);
    });

    test('with no --dart-define the default applies', () {
      // Tests run without PICTOIQ_VIDEO, so this is the built-in default.
      expect(
        FeatureFlags.current.videoEnabled,
        FeatureFlags.defaultVideoEnabled,
      );
      expect(FeatureFlags.defaultVideoEnabled, isTrue);
    });
  });

  group('Settings page', () {
    testWidgets('shows the Videos section when videos are on', (tester) async {
      await _showSettings(tester, showVideoSettings: true);
      await tester.tap(find.text('Video'));
      await tester.pumpAndSettle();
      expect(find.text('Copy to keep'), findsOneWidget);
    });

    testWidgets('hides the Videos section when videos are off', (tester) async {
      await _showSettings(tester, showVideoSettings: false);
      expect(find.text('Copy to keep'), findsNothing);
      // The other sections are still there.
      expect(find.text('Results'), findsWidgets);
    });
  });
}
