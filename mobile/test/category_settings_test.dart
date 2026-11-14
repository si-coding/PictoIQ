import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/features/settings/category_settings.dart';
import 'package:pictoiq_mobile/shared/similarity_grouping.dart'
    show MatchLevel;

void main() {
  test('summaries describe the tool settings', () {
    const s = AppSettings(matchLevel: MatchLevel.strict);
    expect(settingsSummary(SettingsCategory.bestShot, s), contains('Strict'));
    expect(settingsSummary(SettingsCategory.clutter, s), contains('types'));
    expect(settingsSummary(SettingsCategory.video, s), contains('keep'));
  });

  testWidgets('panel is collapsed, opens on tap and saves a change', (
    tester,
  ) async {
    AppSettings? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CategorySettingsPanel(
              category: SettingsCategory.bestShot,
              settings: const AppSettings(),
              onChanged: (s) => saved = s,
            ),
          ),
        ),
      ),
    );
    expect(find.text('How closely photos must match'), findsNothing);
    await tester.tap(find.text('Update Best Shots Filter'));
    await tester.pumpAndSettle();
    expect(find.text('How closely photos must match'), findsOneWidget);
    // "Strict" also names a time option, so take the match-level chip, which
    // comes first in the list.
    final strict = find.widgetWithText(ChoiceChip, 'Strict').first;
    await tester.ensureVisible(strict);
    await tester.pumpAndSettle();
    await tester.tap(strict);
    await tester.pumpAndSettle();
    expect(saved?.matchLevel, MatchLevel.strict);
  });

  group('scan scope card', () {
    Widget host({required VoidCallback onFindAgain, ValueChanged<AppSettings>? onChanged}) =>
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScanScopeCard(
                folder: 'Camera',
                range: 'Last 7 days (7 Nov 2026 – 14 Nov 2026)',
                counts: '143 photos scanned · 3 groups',
                scannedLine: '143 of 150 photos',
                category: SettingsCategory.bestShot,
                settings: const AppSettings(),
                scannedWith: const AppSettings(),
                onChanged: onChanged ?? (_) {},
                onFindAgain: onFindAgain,
              ),
            ),
          ),
        );

    testWidgets('shows a short header and the filters as chips', (
      tester,
    ) async {
      await tester.pumpWidget(host(onFindAgain: () {}));
      expect(find.text('Scan details'), findsOneWidget);
      expect(find.text('Camera · Last 7 days'), findsOneWidget);
      expect(find.text('143 photos scanned · 3 groups'), findsOneWidget);
      expect(find.text('Balanced match'), findsOneWidget);
      expect(find.text('Find again with these filters'), findsNothing);
    });

    testWidgets('opens, and offers Find again only after a change', (
      tester,
    ) async {
      var again = 0;
      AppSettings? saved;
      await tester.pumpWidget(
        host(onFindAgain: () => again++, onChanged: (s) => saved = s),
      );
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('This scan'), findsOneWidget);
      expect(find.text('143 of 150 photos'), findsOneWidget);
      expect(find.text('Find again with these filters'), findsNothing);

      final strict = find.widgetWithText(ChoiceChip, 'Strict').first;
      await tester.ensureVisible(strict);
      await tester.pumpAndSettle();
      await tester.tap(strict);
      await tester.pumpAndSettle();
      expect(saved?.matchLevel, MatchLevel.strict);

      final again0 = find.text('Find again with these filters');
      await tester.ensureVisible(again0);
      await tester.pumpAndSettle();
      await tester.tap(again0);
      expect(again, 1);
    });
  });
}
