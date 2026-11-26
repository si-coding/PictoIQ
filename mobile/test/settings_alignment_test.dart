import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/features/settings/settings_page.dart';

void main() {
  testWidgets('controls in an opened Best moments section share a left edge', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          initial: const AppSettings(),
          onChanged: (_) {},
          showVideoSettings: false,
        ),
      ),
    );
    await tester.tap(find.text('Best moments'));
    await tester.pumpAndSettle();

    double left(String text) => tester.getTopLeft(find.text(text)).dx;
    final edge = left('How long a moment can last');
    expect(left('Documents and screenshots of pages'), edge);
    expect(left('Photos shown per moment'), edge);
    expect(left('Smiles and candid shots'), edge);
  });
}
