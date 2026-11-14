import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/shared/app_menu_button.dart';
import 'package:pictoiq_mobile/shared/app_bar_title.dart';
import 'package:pictoiq_mobile/shared/app_background.dart';
import 'package:pictoiq_mobile/shared/app_back_button.dart';
import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/features/settings/category_settings.dart';
import 'package:pictoiq_mobile/core/config/app_colors.dart';

const _green = AppColors.primary;
const _muted = AppColors.body;

/// All of PictoIQ's settings on one page, grouped by what they affect. Every
/// change is applied and saved at once through [onChanged].
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.initial,
    required this.onChanged,
    this.showVideoSettings = true,
  });

  final AppSettings initial;
  final ValueChanged<AppSettings> onChanged;

  /// False when videos are switched off for this build, which hides the
  /// Videos section.
  final bool showVideoSettings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late AppSettings _settings = widget.initial;

  void _change(AppSettings settings) {
    setState(() => _settings = settings);
    widget.onChanged(settings);
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    appBar: AppBar(
      leading: const AppBackButton(),
      leadingWidth: appBackButtonWidth,
      title: const AppBarTitle(icon: Icons.settings_outlined, title: 'Settings'),
      actions: const [AppMenuButton(showSettings: false)],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          _section(
            title: 'Best moments',
            icon: Icons.collections_outlined,
            note:
                'How moments are found and which photos are shown. Changes to finding moments apply to the next scan.',
            children: momentSettingsChildren(_settings, _change),
          ),
          _section(
            title: 'Best shot and similar photos',
            icon: Icons.photo_camera_outlined,
            note:
                'How photos are matched and ranked. Changes apply to the next scan.',
            children: bestShotSettingsChildren(_settings, _change),
          ),
          _section(
            title: 'Clutter',
            icon: Icons.cleaning_services_outlined,
            note:
                'Which kinds of photos are listed as clutter. Nothing is deleted until you confirm. Changes apply to the next scan.',
            children: clutterSettingsChildren(_settings, _change),
          ),
          if (widget.showVideoSettings)
            _section(
              title: 'Video',
              icon: Icons.videocam_outlined,
              note: 'Exact duplicate videos. Changes apply to the next scan.',
              children: videoSettingsChildren(_settings, _change),
            ),
          _section(
            title: 'Reel',
            icon: Icons.movie_creation_outlined,
            note: 'Default photo count, timing and title style for new reels.',
            children: [
              settingsChoice<int>(
                title: 'Maximum photos in a reel',
                values: const [5, 10, 15, 20, 30],
                selected: _settings.reelMaxPhotos,
                label: (count) => '$count',
                onSelected: (count) =>
                    _change(_settings.copyWith(reelMaxPhotos: count)),
                note: 'Reels open with up to 15 photos by default.',
              ),
              settingsChoice<int>(
                title: 'Time per photo',
                values: const [2, 3, 4, 5, 6],
                selected: _settings.reelSecondsPerPhoto,
                label: (seconds) => '${seconds}s',
                onSelected: (seconds) => _change(
                  _settings.copyWith(reelSecondsPerPhoto: seconds),
                ),
              ),
              settingsChoice<int>(
                title: 'Transition between photos',
                values: const [0, 250, 400, 500, 750, 1000],
                selected: _settings.reelTransitionMillis,
                label: (millis) => millis == 0 ? 'Off' : '${millis}ms',
                onSelected: (millis) => _change(
                  _settings.copyWith(reelTransitionMillis: millis),
                ),
              ),
              settingsChoice<ReelTitleStyle>(
                title: 'Default title style',
                values: ReelTitleStyle.values,
                selected: _settings.reelTitleStyle,
                label: (style) => switch (style) {
                  ReelTitleStyle.clean => 'Clean',
                  ReelTitleStyle.bold => 'Bold',
                  ReelTitleStyle.elegant => 'Elegant',
                },
                onSelected: (style) =>
                    _change(_settings.copyWith(reelTitleStyle: style)),
              ),
            ],
          ),
          _section(
            title: 'Results',
            icon: Icons.view_agenda_outlined,
            children: [
              settingsSwitch(
                title: 'Show event headings',
                subtitle:
                    'Lists groups under a date heading when the camera time or a date in the file name is known. Never affects what is grouped.',
                value: _settings.showEvents,
                onChanged: (value) =>
                    _change(_settings.copyWith(showEvents: value)),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _section({
    required String title,
    required IconData icon,
    String? note,
    required List<Widget> children,
  }) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Card(
      elevation: 0,
      color: const Color(0xFFF4F6F1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ExpansionTile(
        leading: Icon(icon, size: 20, color: _green),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        subtitle: note == null
            ? null
            : Text(
                note,
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        children: children,
      ),
    ),
  );
}
