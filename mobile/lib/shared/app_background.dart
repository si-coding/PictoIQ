import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/core/config/app_colors.dart';

/// The page background every screen shares: the light page colour. The fresh
/// green is reserved for the header (app bar).
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: AppColors.canvas, child: child);
}

/// A [Scaffold] on the shared [AppBackground]. Use it for every normal screen
/// so the look stays the same everywhere.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) => AppBackground(
    child: Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBar,
      body: body,
      bottomNavigationBar: bottomNavigationBar,
    ),
  );
}
