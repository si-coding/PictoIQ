import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/features/settings/category_settings.dart';
import 'package:pictoiq_mobile/shared/similarity_grouping.dart'
    show ContentFilter;

void main() {
  testWidgets('Best moments settings are about people only, with no scenery choice', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: momentSettingsChildren(const AppSettings(), (_) {}),
          ),
        ),
      ),
    );
    // An information panel, not a control that looks tappable.
    expect(find.text('Which photos to include'), findsNothing);
    expect(find.text('Always about people'), findsOneWidget);
    expect(find.text('Scenery'), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byType(Chip), findsNothing);
    // Documents and screenshots stay a choice.
    expect(find.text('Documents and screenshots of pages'), findsOneWidget);
  });

  test('Best moments summary says People whatever the shared filter is', () {
    for (final filter in ContentFilter.values) {
      final parts = settingsParts(
        SettingsCategory.bestMoments,
        AppSettings(contentFilter: filter),
      );
      expect(parts, contains('People'));
      expect(parts.join(' '), isNot(contains('Scenery')));
      expect(parts.join(' '), isNot(contains('All photos')));
    }
  });

  test('other tools still show the shared filter', () {
    final parts = settingsParts(
      SettingsCategory.bestShot,
      const AppSettings(contentFilter: ContentFilter.sceneryOnly),
    );
    expect(parts, contains(ContentFilter.sceneryOnly.label));
  });
}
