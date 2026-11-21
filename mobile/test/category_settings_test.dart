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
    await tester.tap(find.text('Change filter'));
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
    Widget host({VoidCallback? onChangeFilter}) =>
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
                onChangeFilter: onChangeFilter ?? () {},
              ),
            ),
          ),
        );

    testWidgets('shows a short header and the filters as chips', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      expect(find.text('Scan details'), findsOneWidget);
      expect(find.text('Camera · Last 7 days'), findsOneWidget);
      expect(find.text('143 photos scanned · 3 groups'), findsOneWidget);
      expect(find.text('Balanced match'), findsOneWidget);
    });

    testWidgets('opens to just the chosen filters and a Change filter button', (
      tester,
    ) async {
      var changed = 0;
      await tester.pumpWidget(host(onChangeFilter: () => changed++));
      await tester.tap(find.text('Selected filter').first);
      await tester.pumpAndSettle();
      expect(find.text('This scan'), findsOneWidget);
      expect(find.text('143 of 150 photos'), findsOneWidget);
      // The chosen filters only: no options to pick from.
      expect(find.text('Balanced match'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);

      await tester.ensureVisible(find.text('Change filter'));
      await tester.tap(find.text('Change filter'));
      expect(changed, 1);
    });
  });
}
