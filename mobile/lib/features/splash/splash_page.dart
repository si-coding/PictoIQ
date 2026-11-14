import 'dart:async';

import 'package:flutter/material.dart';

/// The opening screen: the logo with "picto" sliding in from the left and
/// "iq" from the right until they meet just below it, then the app appears.
/// The colour and logo size match the native launch screen, so the hand-over
/// from Android's splash is seamless.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, required this.next});

  /// Builds the screen shown once the animation has finished.
  final WidgetBuilder next;

  /// Same value as `pictoiq_launcher_background` in the Android resources.
  static const background = Color(0xFF153A36);
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
    // The native splash draws the logo 250 physical pixels wide.
    final logo = 250 / MediaQuery.devicePixelRatioOf(context);
    const style = TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
      height: 1,
    );
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
            const SizedBox(height: 18),
            AnimatedBuilder(
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
                        child: Text(
                          'picto',
                          style: style.copyWith(color: Colors.white),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(offset, 0),
                        child: Text(
                          'iq',
                          style: style.copyWith(color: SplashPage.lime),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
