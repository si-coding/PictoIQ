import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/shared/brand_wordmark.dart';

/// The opening screen: the logo with "picto" sliding in from the left and
/// "iq" from the right until they meet just below it, then the app appears.
/// The colour and logo size match the native launch screen, so the hand-over
/// from Android's splash is seamless.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.next});

  /// Builds the screen shown once the animation has finished.
  final WidgetBuilder next;

  /// Same value as `pictoiq_launcher_background` in the Android resources.
  static const background = Brand.iconBackground;
  static const lime = Color(0xFFB7F36B);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _slide = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      _timer = Timer(const Duration(milliseconds: 500), _continue);
    });
  }

  void _continue() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, _, _) => widget.next(context),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The logo leads; the wordmark sits under it, clearly smaller.
    final logo = math.max(250 / MediaQuery.devicePixelRatioOf(context), 132.0);
    const wordmarkHeight = 34.0;
    return Scaffold(
      backgroundColor: SplashPage.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(logo * .22),
              child: Image.asset(
                'assets/brand/pictoiq-icon.png',
                width: logo,
                height: logo,
                fit: BoxFit.cover,
              ),
            ),
            // The icon art has margin of its own, so pull the wordmark up.
            Transform.translate(
              offset: Offset(0, -logo * .1),
              child: AnimatedBuilder(
              animation: _slide,
              builder: (context, _) {
                final t = _slide.value;
                final offset = (1 - t) * 140;
                return Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(
                        offset: Offset(-offset, 0),
                        child: const WordmarkPart.picto(
                          key: ValueKey('wordmark-picto'),
                          height: wordmarkHeight,
                          color: Colors.white,
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(offset, 0),
                        child: const WordmarkPart.iq(
                          key: ValueKey('wordmark-iq'),
                          height: wordmarkHeight,
                          color: SplashPage.lime,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            ),
          ],
        ),
      ),
    );
  }
}
