import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pictoiq_mobile/shared/app_back_button.dart';
import 'package:pictoiq_mobile/shared/app_menu_button.dart';

Widget _host() => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Scaffold(
                            appBar: AppBar(actions: const [AppHomeButton()]),
                            body: const Text('deep'),
                          ),
                        ),
                      ),
                      child: const Text('second'),
                    ),
                  ),
                ),
              ),
            ),
          ),
          child: const Text('home'),
        ),
      ),
    ),
  ),
);

Future<void> _openDeep(WidgetTester tester) async {
  await tester.pumpWidget(_host());
  await tester.tap(find.text('home'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('second'));
  await tester.pumpAndSettle();
  expect(find.text('deep'), findsOneWidget);
}

void main() {
  tearDown(() => AppMenuActions.goHome = null);

  testWidgets('Home closes every screen above the first one', (tester) async {
    await _openDeep(tester);
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text('deep'), findsNothing);
  });

  testWidgets('Home runs the home screen action when there is one', (
    tester,
  ) async {
    var called = 0;
    AppMenuActions.goHome = () => called++;
    await _openDeep(tester);
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    expect(called, 1);
  });

  testWidgets('a disabled Home button does nothing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppHomeButton(enabled: false)),
      ),
    );
    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });
}
