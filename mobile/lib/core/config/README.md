Build-time feature flags (`feature_flags.dart`), set with `--dart-define`.

## Theme (`app_colors.dart`)

The look of the app is chosen when it is built, like a feature flag:

```
flutter run --dart-define=PICTOIQ_THEME=fresh
flutter build appbundle --dart-define=PICTOIQ_THEME=forest
flutter build apk --release --dart-define=PICTOIQ_THEME=classic
```

| Value | Look |
|---|---|
| `fresh` (default) | Light mint header, pastel cards with deep-colour titles, white icon tile and round white arrow button |
| `forest` | Deep green header, saturated gradient cards with white text |
| `classic` | The original soft pastel look and layout |

An unknown value falls back to `fresh`. To change the default for every build
without a define, edit `defaultTheme` in `app_colors.dart`.

All colours live in that one file (`AppColors` for the page, `AppToolColors`
for the eight tool cards). Pages take their colours from there, so a new theme
or a changed shade is one edit. Every value is a compile-time constant, so
pages can keep using them in `const` widgets. `test/app_colors_test.dart`
checks that card text, captions and buttons keep at least 4.5:1 contrast.

