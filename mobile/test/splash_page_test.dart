import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/splash/splash_page.dart';

void main() {
  testWidgets('shows the wordmark, then the app', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SplashPage(next: (_) => const Scaffold(body: Text('home'))),
      ),
    );
    expect(find.text('picto'), findsOneWidget);
    expect(find.text('iq'), findsOneWidget);
    expect(find.text('home'), findsNothing);

    // The slide-in runs, then the screen waits briefly before moving on.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(find.text('picto'), findsNothing);
  });
}
