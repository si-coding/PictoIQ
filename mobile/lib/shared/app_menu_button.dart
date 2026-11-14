import 'package:flutter/material.dart';

/// Where the menu's entries lead. The home screen sets these when it opens,
/// so every other screen can offer Settings and Privacy without knowing how
/// they are built.
abstract final class AppMenuActions {
  static VoidCallback? openSettings;
  static VoidCallback? showPrivacy;

  /// Closes every screen above the home screen and shows it.
  static VoidCallback? goHome;
}

/// The three-dot menu at the right of every header except Home's: Settings
/// and Privacy.
class AppMenuButton extends StatelessWidget {
  const AppMenuButton({
    super.key,
    this.showSettings = true,
    this.enabled = true,
    this.onSettings,
    this.onPrivacy,
  });

  /// False on the Settings screen itself.
  final bool showSettings;
  final bool enabled;

  /// Override the shared actions (tests, or a screen with its own).
  final VoidCallback? onSettings;
  final VoidCallback? onPrivacy;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Menu',
    enabled: enabled,
    icon: const Icon(Icons.more_vert),
    onSelected: (value) {
      if (value == 'settings') {
        (onSettings ?? AppMenuActions.openSettings)?.call();
      } else {
        (onPrivacy ?? AppMenuActions.showPrivacy)?.call();
      }
    },
    itemBuilder: (_) => [
      if (showSettings)
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Settings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      const PopupMenuItem(
        value: 'privacy',
        child: ListTile(
          leading: Icon(Icons.shield_outlined),
          title: Text('Privacy'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
  );
}
