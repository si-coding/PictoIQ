import 'dart:ui' show Color;

/// Which look the app has. Chosen when the app is built, like a feature flag:
///
/// ```
/// flutter run --dart-define=PICTOIQ_THEME=fresh
/// flutter build appbundle --dart-define=PICTOIQ_THEME=forest
/// ```
///
/// Values: `fresh` (light and bright, the default), `forest` (deep green
/// header and saturated cards) and `classic` (the original soft pastel look).
/// An unknown value falls back to `fresh`. To change the default for every
/// build, edit [defaultTheme].
const String defaultTheme = 'fresh';

/// The theme name this build runs with.
const String themeName = String.fromEnvironment(
  'PICTOIQ_THEME',
  defaultValue: defaultTheme,
);

const bool _classic = themeName == 'classic';
const bool _forest = themeName == 'forest';

/// The colours every page uses. All values are compile-time constants, so
/// pages can keep using them in `const` widgets.
abstract final class AppColors {
  /// True for `fresh` and `forest`: they show the hero header and the white
  /// round arrow button on cards. `classic` keeps the original layout.
  static const bool modern = !_classic;

  /// True when the header is deep green with light text.
  static const bool darkHero = _forest;

  /// Main brand green: buttons, selected states, links.
  static const Color primary = _classic ? Color(0xFF54744C) : Color(0xFF0F7A55);

  /// Text colour on the page.
  static const Color ink = _classic ? Color(0xFF282B25) : Color(0xFF1D2A24);

  /// Top of the shared page background and the app bar colour: the fresh
  /// green that fades to [canvas] at the bottom of every screen.
  static const Color pageTop = _classic ? Color(0xFFF7F8F4) : Color(0xFFD3F1DD);

  /// Page background.
  static const Color canvas = _classic
      ? Color(0xFFF7F8F4)
      : Color(0xFFF6F8F2);

  /// Secondary text (captions, descriptions).
  static const Color body = _classic ? Color(0xFF596252) : Color(0xFF4A5B52);

  /// Hints and small notes. 5.3:1 on the page in the modern themes.
  static const Color hint = _classic ? Color(0xFF77796F) : Color(0xFF5B6B62);

  /// A very light green fill (banners, selected rows).
  static const Color tint = _classic ? Color(0xFFE8F3E8) : Color(0xFFE3F5E8);

  /// A stronger light green fill.
  static const Color tintStrong = _classic
      ? Color(0xFFE3EEDF)
      : Color(0xFFD3F1DD);

  /// Outline for tinted panels and outlined buttons.
  static const Color tintBorder = _classic
      ? Color(0xFFB9D4B3)
      : Color(0xFFA9D9BC);

  /// The "iq" in the wordmark and the tagline.
  static const Color accent = _classic
      ? Color(0xFF54744C)
      : _forest
      ? Color(0xFFB7F36B)
      : Color(0xFF0F7A55);

  /// The pill behind the selected bottom tab.
  static const Color navIndicator = Color(0xFFD3F1DD);

  // Hero header (modern themes only).
  static const Color heroTop = _forest ? Color(0xFF0B3B2C) : Color(0xFFD3F1DD);
  static const Color heroBottom = _forest
      ? Color(0xFF14543F)
      : Color(0xFFF6F8F2);
  static const Color heroTitle = _forest
      ? Color(0xFFFFFFFF)
      : Color(0xFF0B3B2C);
  static const Color heroBody = _forest ? Color(0xFFCFEBDD) : Color(0xFF33423B);
  static const Color heroStat = _forest
      ? Color(0x1FFFFFFF)
      : Color(0xFFFFFFFF);
  static const Color heroStatValue = _forest
      ? Color(0xFFFFFFFF)
      : Color(0xFF0B3B2C);
  /// The totals (Photos, Videos, Albums) in the home header: green on the
  /// light themes, lime on the dark one.
  static const Color heroStatAccent = _forest
      ? Color(0xFFB7F36B)
      : Color(0xFF0F7A55);
  static const Color heroStatLabel = _forest
      ? Color(0xFFCFEBDD)
      : Color(0xFF4A5B52);
  static const Color heroBadge = _forest
      ? Color(0xFFB7F36B)
      : Color(0xFF0F7A55);
  static const Color heroBadgeInk = _forest
      ? Color(0xFF0B3B2C)
      : Color(0xFFFFFFFF);

  /// Bottom corner radius of the hero header.
  static const double heroRadius = _forest ? 32 : 0;
}

/// Colours of one tool card on the home screen.
class ToolCardColors {
  const ToolCardColors({
    required this.background,
    this.backgroundEnd,
    required this.artBackground,
    required this.iconInk,
    required this.title,
    required this.caption,
    required this.chipBackground,
    required this.chipInk,
    required this.selectedBorder,
  });

  /// Card face (gradient start when [backgroundEnd] is set).
  final Color background;
  final Color? backgroundEnd;

  /// The picture area at the top of the card.
  final Color artBackground;

  /// Icons, the arrow and the artwork's hills.
  final Color iconInk;
  final Color title;
  final Color caption;
  final Color chipBackground;
  final Color chipInk;

  /// Outline of the card that is currently chosen.
  final Color selectedBorder;
}

/// The four photo tools and four video tools, per theme.
abstract final class AppToolColors {
  static const ToolCardColors moments = _classic
      ? ToolCardColors(
          background: Color(0xFFE3EEDF),
          artBackground: Color(0xFFE3EEDF),
          iconInk: Color(0xFF54744C),
          title: Color(0xFF282B25),
          caption: Color(0xA8282B25),
          chipBackground: Color(0x99FFFFFF),
          chipInk: Color(0xFF54744C),
          selectedBorder: Color(0xFF54744C),
        )
      : _forest
      ? ToolCardColors(
          background: Color(0xFF187F58),
          backgroundEnd: Color(0xFF0B5A44),
          artBackground: Color(0x33FFFFFF),
          iconInk: Color(0xFF0B5A44),
          title: Color(0xFFFFFFFF),
          caption: Color(0xFFFFFFFF),
          chipBackground: Color(0x38FFFFFF),
          chipInk: Color(0xFFFFFFFF),
          selectedBorder: Color(0xFFB7F36B),
        )
      : ToolCardColors(
          background: Color(0xFFC9F0D8),
          artBackground: Color(0xFFA7E3C0),
          iconInk: Color(0xFF0B4A36),
          title: Color(0xFF0B4A36),
          caption: Color(0xFF2B3A33),
          chipBackground: Color(0xFFFFFFFF),
          chipInk: Color(0xFF0B4A36),
          selectedBorder: Color(0xFF0B4A36),
        );

  static const ToolCardColors duplicates = _classic
      ? ToolCardColors(
          background: Color(0xFFF3E9DD),
          artBackground: Color(0xFFF3E9DD),
          iconInk: Color(0xFF9A6A3A),
          title: Color(0xFF282B25),
          caption: Color(0xA8282B25),
          chipBackground: Color(0x99FFFFFF),
          chipInk: Color(0xFF9A6A3A),
          selectedBorder: Color(0xFF9A6A3A),
        )
      : _forest
      ? ToolCardColors(
          background: Color(0xFFB45309),
          backgroundEnd: Color(0xFF8F3A0C),
          artBackground: Color(0x33FFFFFF),
          iconInk: Color(0xFF8F3A0C),
          title: Color(0xFFFFFFFF),
          caption: Color(0xFFFFFFFF),
          chipBackground: Color(0x38FFFFFF),
          chipInk: Color(0xFFFFFFFF),
          selectedBorder: Color(0xFFB7F36B),
        )
      : ToolCardColors(
          background: Color(0xFFFFDDB0),
          artBackground: Color(0xFFFFCB8F),
          iconInk: Color(0xFF7A3A06),
          title: Color(0xFF7A3A06),
          caption: Color(0xFF3A2F26),
          chipBackground: Color(0xFFFFFFFF),
          chipInk: Color(0xFF7A3A06),
          selectedBorder: Color(0xFF7A3A06),
        );

  static const ToolCardColors bestShot = _classic
      ? ToolCardColors(
          background: Color(0xFFE6E7F3),
          artBackground: Color(0xFFE6E7F3),
          iconInk: Color(0xFF5A5F94),
          title: Color(0xFF282B25),
          caption: Color(0xA8282B25),
          chipBackground: Color(0x99FFFFFF),
          chipInk: Color(0xFF5A5F94),
          selectedBorder: Color(0xFF5A5F94),
        )
      : _forest
      ? ToolCardColors(
          background: Color(0xFF5B54E6),
          backgroundEnd: Color(0xFF3730A3),
          artBackground: Color(0x33FFFFFF),
          iconInk: Color(0xFF3730A3),
          title: Color(0xFFFFFFFF),
          caption: Color(0xFFFFFFFF),
          chipBackground: Color(0x38FFFFFF),
          chipInk: Color(0xFFFFFFFF),
          selectedBorder: Color(0xFFB7F36B),
        )
      : ToolCardColors(
          background: Color(0xFFD5D2FF),
          artBackground: Color(0xFFBDB8FA),
          iconInk: Color(0xFF2E2A8A),
          title: Color(0xFF2E2A8A),
          caption: Color(0xFF2F3140),
          chipBackground: Color(0xFFFFFFFF),
          chipInk: Color(0xFF2E2A8A),
          selectedBorder: Color(0xFF2E2A8A),
        );

  static const ToolCardColors clutter = _classic
      ? ToolCardColors(
          background: Color(0xFFF3E4E1),
          artBackground: Color(0xFFF3E4E1),
          iconInk: Color(0xFF9A5A50),
          title: Color(0xFF282B25),
          caption: Color(0xA8282B25),
          chipBackground: Color(0x99FFFFFF),
          chipInk: Color(0xFF9A5A50),
          selectedBorder: Color(0xFF9A5A50),
        )
      : _forest
      ? ToolCardColors(
          background: Color(0xFFC9246B),
          backgroundEnd: Color(0xFF9D174D),
          artBackground: Color(0x33FFFFFF),
          iconInk: Color(0xFF9D174D),
          title: Color(0xFFFFFFFF),
          caption: Color(0xFFFFFFFF),
          chipBackground: Color(0x38FFFFFF),
          chipInk: Color(0xFFFFFFFF),
          selectedBorder: Color(0xFFB7F36B),
        )
      : ToolCardColors(
          background: Color(0xFFFFCDDD),
          artBackground: Color(0xFFFFB1CB),
          iconInk: Color(0xFF8A1445),
          title: Color(0xFF8A1445),
          caption: Color(0xFF402B33),
          chipBackground: Color(0xFFFFFFFF),
          chipInk: Color(0xFF8A1445),
          selectedBorder: Color(0xFF8A1445),
        );

  /// A tool that is not available yet.
  static const ToolCardColors soon = _classic
      ? ToolCardColors(
          background: Color(0xFFE6E7F3),
          artBackground: Color(0xFFE6E7F3),
          iconInk: Color(0xFF5A5F94),
          title: Color(0xFF282B25),
          caption: Color(0xA8282B25),
          chipBackground: Color(0x99FFFFFF),
          chipInk: Color(0xFF5A5F94),
          selectedBorder: Color(0xFF5A5F94),
        )
      : _forest
      ? ToolCardColors(
          background: Color(0xFF3F6B5A),
          backgroundEnd: Color(0xFF1F4034),
          artBackground: Color(0x33FFFFFF),
          iconInk: Color(0xFF1F4034),
          title: Color(0xFFFFFFFF),
          caption: Color(0xFFFFFFFF),
          chipBackground: Color(0x38FFFFFF),
          chipInk: Color(0xFFFFFFFF),
          selectedBorder: Color(0xFFB7F36B),
        )
      : ToolCardColors(
          background: Color(0xFFDDE4DE),
          artBackground: Color(0xFFC5D0C8),
          iconInk: Color(0xFF2F3E37),
          title: Color(0xFF2F3E37),
          caption: Color(0xFF3D4A42),
          chipBackground: Color(0xFFFFFFFF),
          chipInk: Color(0xFF2F3E37),
          selectedBorder: Color(0xFF2F3E37),
        );

  /// The Videos tab keeps each tool's original colour in the classic theme
  /// (green, tan, lavender, rose); the modern themes use the duplicates
  /// colour for the one working tool and [soon] for the rest.
  static const ToolCardColors videoDuplicates = _classic ? moments : duplicates;
  static const ToolCardColors videoSimilar = _classic ? duplicates : soon;
  static const ToolCardColors videoMoments = _classic ? bestShot : soon;
  static const ToolCardColors videoEnhance = _classic ? clutter : soon;
}
