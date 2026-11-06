import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/features/photos/best_moments/moment_selection.dart';
import 'package:pictoiq_mobile/features/photos/clutter/clutter_classifier.dart'
    show ClutterBlur, ClutterKind;
import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart'
    show VideoKeep;
import 'package:pictoiq_mobile/shared/similarity_grouping.dart' show DocumentMode, MatchLevel, TimeMode;

const _green = Color(0xFF54744C);
const _muted = Color(0xFF596252);

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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: const Text('Settings'),
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
            children: [
              _choice<MomentWindow>(
                title: 'How long a moment can last',
                values: MomentWindow.values,
                selected: _settings.momentWindow,
                label: (window) => window.label,
                onSelected: (window) =>
                    _change(_settings.copyWith(momentWindow: window)),
                note:
                    '${_settings.momentWindow.description} Needs a camera time on the photos.',
              ),
              _choice<MomentPlace>(
                title: 'Keep different places apart',
                values: MomentPlace.values,
                selected: _settings.momentPlace,
                label: (place) => place.label,
                onSelected: (place) =>
                    _change(_settings.copyWith(momentPlace: place)),
                note:
                    '${_settings.momentPlace.description} Uses the location saved in the photo; Android may hide it.',
              ),
              _choice<MatchLevel>(
                title: 'How closely clothing must match',
                values: MatchLevel.values,
                selected: _settings.momentPeople,
                label: (level) => level.label,
                onSelected: (level) =>
                    _change(_settings.copyWith(momentPeople: level)),
              ),
              _switch(
                title: 'Separate portraits, couples and groups',
                subtitle:
                    'A portrait and a family photo at the same place become different moments. Face counts are approximate.',
                value: _settings.momentSeparateTypes,
                onChanged: (value) =>
                    _change(_settings.copyWith(momentSeparateTypes: value)),
              ),
              _switch(
                title: 'Show moments with no people',
                subtitle:
                    'Objects, rooms and screenshots. Usually clutter, so they are hidden.',
                value: _settings.momentShowScenes,
                onChanged: (value) =>
                    _change(_settings.copyWith(momentShowScenes: value)),
              ),
              _choice<int>(
                title: 'Photos shown per moment',
                values: const [1, 2, 3],
                selected: _settings.momentCount,
                label: (count) => '$count',
                onSelected: (count) =>
                    _change(_settings.copyWith(momentCount: count)),
              ),
              _choice<MomentVariety>(
                title: 'Variety between the photos shown',
                values: MomentVariety.values,
                selected: _settings.momentVariety,
                label: (variety) => variety.label,
                onSelected: (variety) =>
                    _change(_settings.copyWith(momentVariety: variety)),
                note: _settings.momentVariety.description,
              ),
              _choice<MomentExpression>(
                title: 'Smiles and candid shots',
                values: MomentExpression.values,
                selected: _settings.momentExpression,
                label: (expression) => expression.label,
                onSelected: (expression) =>
                    _change(_settings.copyWith(momentExpression: expression)),
                note: _settings.momentExpression.description,
              ),
            ],
          ),
          _section(
            title: 'Best shot and similar photos',
            icon: Icons.photo_camera_outlined,
            note:
                'How photos are matched and ranked. Changes apply to the next scan.',
            children: [
              _choice<MatchLevel>(
                title: 'How closely photos must match',
                values: MatchLevel.values,
                selected: _settings.matchLevel,
                label: (level) => level.label,
                onSelected: (level) =>
                    _change(_settings.copyWith(matchLevel: level)),
                note: _settings.matchLevel.description,
              ),
              _choice<TimeMode>(
                title: 'Also use time taken',
                values: TimeMode.values,
                selected: _settings.timeMode,
                label: (mode) => mode.label,
                onSelected: (mode) =>
                    _change(_settings.copyWith(timeMode: mode)),
                note:
                    '${_settings.timeMode.description}${_settings.timeMode == TimeMode.off || _settings.timeMode == TimeMode.hint ? '' : ' Uses camera time, else a date in the file name, else the file date; files that were copied or downloaded can carry misleading dates, and then fewer photos will group.'}',
              ),
              _choice<DocumentMode>(
                title: 'Documents and screenshots of pages',
                values: DocumentMode.values,
                selected: _settings.documentMode,
                label: (mode) => mode.label,
                onSelected: (mode) =>
                    _change(_settings.copyWith(documentMode: mode)),
                note: _settings.documentMode.description,
              ),
              _switch(
                title: 'Use faces and eyes when ranking',
                subtitle:
                    'Detects faces on this device to prefer open eyes and smiles. Turn off for faster scans that rank on sharpness, lighting and resolution only.',
                value: _settings.useFaceSignals,
                onChanged: (value) =>
                    _change(_settings.copyWith(useFaceSignals: value)),
              ),
              _switch(
                title: 'Keep different people apart',
                subtitle:
                    'Keeps photos with different numbers of people, or a main person dressed in clearly different colours, in separate groups. A rough check, not face recognition. Needs "Use faces and eyes" on.',
                value: _settings.splitByPeople,
                onChanged: (value) =>
                    _change(_settings.copyWith(splitByPeople: value)),
              ),
              _switch(
                title: 'I choose which photos to keep',
                subtitle:
                    'PictoIQ never picks a photo to keep in similar-shot groups. Nothing is selected for deletion until you choose a photo to keep.',
                value: _settings.manualSelectionOnly,
                onChanged: (value) =>
                    _change(_settings.copyWith(manualSelectionOnly: value)),
              ),
            ],
          ),
          _section(
            title: 'Clutter',
            icon: Icons.cleaning_services_outlined,
            note:
                'Which kinds of photos are listed as clutter. Nothing is deleted until you confirm. Changes apply to the next scan.',
            children: [
              _kindChips(),
              _choice<ClutterBlur>(
                title: 'How blurry counts as blurry',
                values: ClutterBlur.values,
                selected: _settings.clutterBlur,
                label: (blur) => blur.label,
                onSelected: (blur) =>
                    _change(_settings.copyWith(clutterBlur: blur)),
                note:
                    '${_settings.clutterBlur.description} Photos with faces are never listed as blurry, documents or tiny. Turning off "Use faces and eyes" under Best shot removes that protection.',
              ),
            ],
          ),
          if (widget.showVideoSettings)
            _section(
              title: 'Videos',
              icon: Icons.videocam_outlined,
              note: 'Exact duplicate videos. Changes apply to the next scan.',
              children: [
                _choice<VideoKeep>(
                  title: 'Copy to keep',
                  values: VideoKeep.values,
                  selected: _settings.videoKeep,
                  label: (keep) => keep.label,
                  onSelected: (keep) =>
                      _change(_settings.copyWith(videoKeep: keep)),
                  note:
                      '${_settings.videoKeep.description} You can still pick a different one in each set before deleting.',
                ),
              ],
            ),
          _section(
            title: 'Results',
            icon: Icons.view_agenda_outlined,
            children: [
              _switch(
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: _green),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  note,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
              ),
            ...children,
          ],
        ),
      ),
    ),
  );

  Widget _choice<T>({
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
    String? note,
  }) => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final value in values)
              ChoiceChip(
                label: Text(label(value)),
                selected: value == selected,
                showCheckmark: false,
                onSelected: (_) => onSelected(value),
              ),
          ],
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(note, style: const TextStyle(fontSize: 12, color: _muted)),
          ),
      ],
    ),
  );

  /// One chip per kind of clutter; a lit chip means it is looked for.
  Widget _kindChips() => Padding(
    padding: const EdgeInsets.only(top: 14, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Look for',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final kind in ClutterKind.values)
              FilterChip(
                label: Text(kind.title),
                selected: !_settings.clutterOff.contains(kind),
                showCheckmark: false,
                onSelected: (on) => _change(
                  _settings.copyWith(
                    clutterOff: on
                        ? ({..._settings.clutterOff}..remove(kind))
                        : {..._settings.clutterOff, kind},
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _settings.clutterOff.length == ClutterKind.values.length
              ? 'Everything is turned off, so a clutter scan finds nothing.'
              : 'Lit types are looked for. Each photo is listed under its first reason, in the order shown.',
          style: const TextStyle(fontSize: 12, color: _muted),
        ),
      ],
    ),
  );

  Widget _switch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(title),
    subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    value: value,
    onChanged: onChanged,
  );
}
