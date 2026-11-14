import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pictoiq_mobile/core/config/app_colors.dart';

double _contrast(Color a, Color b) {
  final first = a.computeLuminance();
  final second = b.computeLuminance();
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  const cards = {
    'moments': AppToolColors.moments,
    'duplicates': AppToolColors.duplicates,
    'bestShot': AppToolColors.bestShot,
    'clutter': AppToolColors.clutter,
    'soon': AppToolColors.soon,
  };

  test('the theme name is one the app knows', () {
    expect(const ['classic', 'forest', 'fresh'], contains(themeName));
    expect(defaultTheme, 'fresh');
  });

  test('the default build uses the modern look', () {
    // Run without --dart-define=PICTOIQ_THEME to check the default.
    if (themeName == defaultTheme) {
      expect(AppColors.modern, isTrue);
      expect(AppColors.primary, const Color(0xFF0F7A55));
    }
  });

  test('card text is readable on every card in the modern themes', () {
    if (!AppColors.modern) return;
    for (final entry in cards.entries) {
      final colors = entry.value;
      for (final face in [colors.background, ?colors.backgroundEnd]) {
        expect(
          _contrast(colors.title, face),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} title',
        );
        expect(
          _contrast(Color.alphaBlend(colors.caption, face), face),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} caption',
        );
      }
    }
  });

  test('the white icon tile and arrow button stay readable', () {
    for (final entry in cards.entries) {
      expect(
        _contrast(entry.value.iconInk, const Color(0xFFFFFFFF)),
        greaterThanOrEqualTo(4.5),
        reason: '${entry.key} icon on white',
      );
    }
  });

  test('buttons: white text on the primary colour is readable', () {
    if (!AppColors.modern) return;
    expect(
      _contrast(const Color(0xFFFFFFFF), AppColors.primary),
      greaterThanOrEqualTo(4.5),
    );
  });
}
