import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/core/config/app_colors.dart';
import 'package:pictoiq_mobile/shared/app_menu_button.dart';

/// The back arrow every page uses: a white round button that stands out on
/// the green app bar. Pass `enabled: false` while work is running.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.enabled = true, this.onPressed});

  final bool enabled;

  /// Defaults to going back one screen.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: IconButton.filled(
      tooltip: 'Back',
      onPressed: enabled
          ? (onPressed ?? () => Navigator.of(context).maybePop())
          : null,
      icon: const Icon(Icons.arrow_back, size: 22),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: Colors.white70,
        fixedSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
    ),
  );
}

/// The home icon shown on browse and results screens, just left of the ⋮
/// menu. It returns to the home screen, or runs [onPressed] when the screen
/// is not its own route.
class AppHomeButton extends StatelessWidget {
  const AppHomeButton({super.key, this.enabled = true, this.onPressed});

  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    child: IconButton.filled(
      tooltip: 'Home',
      onPressed: enabled
          ? (onPressed ??
                () {
                  final goHome = AppMenuActions.goHome;
                  if (goHome != null) {
                    goHome();
                  } else {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
                })
          : null,
      icon: const Icon(Icons.home_outlined, size: 22),
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: Colors.white70,
        fixedSize: const Size(40, 40),
        padding: EdgeInsets.zero,
      ),
    ),
  );
}

/// Pass to `AppBar.leadingWidth` together with [AppBackButton].
const double appBackButtonWidth = 60;
