import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/features/settings/category_settings.dart';
import 'package:pictoiq_mobile/shared/photo_content.dart';
import 'package:pictoiq_mobile/shared/shot_ranking.dart';
import 'package:pictoiq_mobile/shared/similarity_grouping.dart'
    show ContentFilter;

Widget _body(SettingsCategory category, AppSettings settings, ValueChanged<AppSettings> onChanged) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CategorySettingsBody(
            category: category,
            settings: settings,
            onChanged: onChanged,
          ),
        ),
      ),
    );

void main() {
  group('content choice', () {
    test('People and Scenery combine into one filter', () {
      expect(
        ContentFilter.fromChoice(people: true, scenery: true),
        ContentFilter.peopleAndScenery,
      );
      expect(
        ContentFilter.fromChoice(people: true, scenery: false),
        ContentFilter.peopleOnly,
      );
      expect(
        ContentFilter.fromChoice(people: false, scenery: true),
        ContentFilter.sceneryOnly,
      );
      expect(
        ContentFilter.fromChoice(people: false, scenery: false),
        ContentFilter.everything,
      );
    });

    test('what each filter includes', () {
      expect(ContentFilter.peopleOnly.includesScenery, isFalse);
      expect(ContentFilter.sceneryOnly.includesPeople, isFalse);
      expect(ContentFilter.peopleAndScenery.includesPeople, isTrue);
      expect(ContentFilter.peopleAndScenery.includesScenery, isTrue);
      expect(ContentFilter.everything.includesPeople, isTrue);
    });

    test('new installs look for people and scenery', () {
      expect(const AppSettings().contentFilter, ContentFilter.peopleAndScenery);
    });

    test('isAboutScenery needs a sure scenery label and no clear face', () {
      List<PhotoLabel> l(Map<String, double> m) => [
        for (final e in m.entries) PhotoLabel(e.key, e.value),
      ];
      expect(isAboutScenery(faceCount: 1, labels: l({'Sky': 0.95})), isFalse);
      expect(isAboutScenery(faceCount: 0, labels: l({'Sky': 0.9})), isTrue);
      expect(
        isAboutScenery(faceCount: 0, labels: l({'Sky': 0.65, 'Table': 0.95})),
        isFalse,
      );
      expect(isAboutScenery(faceCount: 0, labels: const []), isFalse);
      expect(isAboutScenery(faceCount: null, labels: null), isTrue);
    });

    test('an unclear subject is judged on a prominent face only', () {
      const soft = FaceSignals(
        count: 1,
        eyesOpenMin: null,
        smileAverage: null,
        largestFaceArea: 0.05,
        faceSharpness: 1,
        frameSharpness: 200,
      );
      expect(soft.isUnclearSubject(), isTrue);
      const tiny = FaceSignals(
        count: 1,
        eyesOpenMin: null,
        smileAverage: null,
        largestFaceArea: 0.0005,
        faceSharpness: 1,
        frameSharpness: 200,
      );
      expect(tiny.isUnclearSubject(), isFalse);
      expect(FaceSignals.none.isUnclearSubject(), isFalse);
    });
  });

  group('settings shared by Best moments and Best shots', () {
    for (final category in [
      SettingsCategory.bestMoments,
      SettingsCategory.bestShot,
      SettingsCategory.duplicates,
    ]) {
      testWidgets('${category.name} offers people, scenery and documents', (
        tester,
      ) async {
        await tester.pumpWidget(
          _body(category, const AppSettings(), (_) {}),
        );
        expect(find.text('Which photos to include'), findsOneWidget);
        expect(find.widgetWithText(FilterChip, 'People'), findsOneWidget);
        expect(find.widgetWithText(FilterChip, 'Scenery'), findsOneWidget);
        expect(
          find.text('Documents and screenshots of pages'),
          findsOneWidget,
        );
      });
    }

    testWidgets('Best moments no longer has a separate no-people switch', (
      tester,
    ) async {
      await tester.pumpWidget(
        _body(SettingsCategory.bestMoments, const AppSettings(), (_) {}),
      );
      expect(find.text('Show moments with no people'), findsNothing);
    });

    testWidgets('both chips are lit by default and switch off one at a time', (
      tester,
    ) async {
      AppSettings? saved;
      await tester.pumpWidget(
        _body(
          SettingsCategory.bestMoments,
          const AppSettings(),
          (s) => saved = s,
        ),
      );
      FilterChip chip(String label) =>
          tester.widget<FilterChip>(find.widgetWithText(FilterChip, label));
      expect(chip('People').selected, isTrue);
      expect(chip('Scenery').selected, isTrue);

      await tester.tap(find.widgetWithText(FilterChip, 'Scenery'));
      await tester.pumpAndSettle();
      expect(saved?.contentFilter, ContentFilter.peopleOnly);

      await tester.tap(find.widgetWithText(FilterChip, 'People'));
      await tester.pumpAndSettle();
      expect(saved?.contentFilter, ContentFilter.everything);
    });

    test('the moments summary names the content choice', () {
      expect(
        settingsSummary(SettingsCategory.bestMoments, const AppSettings()),
        contains('People and scenery'),
      );
    });
  });

  group('results Change Filter panel', () {
    Widget host({VoidCallback? onFindAgain, ValueChanged<AppSettings>? onChanged}) =>
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScanScopeCard(
                showScanDetails: false,
                folder: 'Camera',
                range: 'Last 7 days (7 Nov 2026 – 14 Nov 2026)',
                counts: '143 photos scanned · 3 groups',
                category: SettingsCategory.bestMoments,
                settings: const AppSettings(),
                scannedWith: const AppSettings(),
                onChanged: onChanged ?? (_) {},
                onFindAgain: onFindAgain ?? () {},
              ),
            ),
          ),
        );

    testWidgets('is just a collapsed Change Filter row', (tester) async {
      await tester.pumpWidget(host());
      expect(find.text('Change Filter'), findsOneWidget);
      expect(find.text('Scan details'), findsNothing);
      expect(find.text('Camera · Last 7 days'), findsNothing);
      expect(find.text('Which photos to include'), findsNothing);
    });

    testWidgets('opens to the filters and offers Find again after a change', (
      tester,
    ) async {
      var again = 0;
      await tester.pumpWidget(host(onFindAgain: () => again++));
      await tester.tap(find.text('Change Filter'));
      await tester.pumpAndSettle();
      expect(find.text('Which photos to include'), findsOneWidget);
      expect(find.text('This scan'), findsNothing);
      expect(find.text('Find again with these filters'), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'Scenery'));
      await tester.pumpAndSettle();
      final button = find.text('Find again with these filters');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      expect(again, 1);
    });
  });
}
