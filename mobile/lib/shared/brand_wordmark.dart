import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The PictoIQ brand colours, taken from the logo.
abstract final class Brand {
  /// The dark green of "picto" and of the tagline.
  static const ink = Color(0xFF013E33);

  /// The green of "iq".
  static const green = Color(0xFF0EA050);

  /// The dark green of the app icon.
  static const iconBackground = Color(0xFF014135);

  /// The tagline font: Poppins Medium Italic (assets/fonts, SIL Open Font
  /// Licence).
  static const taglineStyle = TextStyle(
    fontFamily: 'Poppins',
    fontStyle: FontStyle.italic,
    fontWeight: FontWeight.w500,
    color: ink,
  );
}

/// Adds the licence of the bundled tagline font to the app's licence page
/// (Privacy > Open-source licences).
void registerBrandLicenses() {
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(
        ['Poppins font'],
        'Copyright 2020 The Poppins Project Authors '
        '(https://github.com/itfoundry/Poppins).\n\n'
        'This Font Software is licensed under the SIL Open Font License, '
        'Version 1.1. The licence text is at https://openfontlicense.org',
      ),
    ),
  );
}

/// The "pictoiq" logo text, drawn from the artwork in assets/brand. The two
/// parts are separate so the splash screen can slide them in from each side;
/// each is a white shape that is tinted with [color].
class WordmarkPart extends StatelessWidget {
  const WordmarkPart.picto({
    super.key,
    required this.height,
    this.color = Brand.ink,
  }) : _asset = 'assets/brand/pictoiq-wordmark-picto.png';

  const WordmarkPart.iq({
    super.key,
    required this.height,
    this.color = Brand.green,
  }) : _asset = 'assets/brand/pictoiq-wordmark-iq.png';

  final String _asset;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Image.asset(
    _asset,
    height: height,
    color: color,
    colorBlendMode: BlendMode.srcIn,
    filterQuality: FilterQuality.high,
    excludeFromSemantics: true,
  );
}

/// "picto" and "iq" side by side.
class PictoIqWordmark extends StatelessWidget {
  const PictoIqWordmark({
    super.key,
    required this.height,
    this.pictoColor = Brand.ink,
    this.iqColor = Brand.green,
  });

  final double height;
  final Color pictoColor;
  final Color iqColor;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'pictoiq',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WordmarkPart.picto(height: height, color: pictoColor),
          WordmarkPart.iq(height: height, color: iqColor),
        ],
      ),
    ),
  );
}
