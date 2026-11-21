import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/photos/library/date_range_page.dart';

void main() {
  Future<void> open(WidgetTester tester, ValueSetter<DateTimeRange?> done) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => done(
              await Navigator.of(context).push<DateTimeRange>(
                MaterialPageRoute(
                  builder: (_) => DateRangePage(
                    firstDate: DateTime(2026, 1, 1),
                    lastDate: DateTime(2026, 11, 20),
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('Apply is at the left and Close at the right', (
    tester,
  ) async {
    await open(tester, (_) {});
    final apply = tester.getCenter(find.text('Apply'));
    expect(find.byIcon(Icons.check), findsOneWidget);
    final close = tester.getCenter(find.byTooltip('Close'));
    expect(apply.dx, lessThan(close.dx));
  });

  testWidgets('picks a from and to date', (tester) async {
    DateTimeRange? picked;
    await open(tester, (range) => picked = range);
    // Apply is disabled until a day is chosen.
    expect(
      tester.widget<FilledButton>(find.bySubtype<FilledButton>()).onPressed,
      isNull,
    );
    await tester.tap(find.text('10').first);
    await tester.pump();
    await tester.tap(find.text('15').first);
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
    expect(picked!.end.difference(picked!.start).inDays, 5);
  });

  testWidgets('Close returns nothing', (tester) async {
    DateTimeRange? picked = DateTimeRange(
      start: DateTime(2026),
      end: DateTime(2026),
    );
    await open(tester, (range) => picked = range);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
