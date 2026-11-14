import 'package:flutter/material.dart';

import 'package:pictoiq_mobile/core/config/app_colors.dart';
import 'package:pictoiq_mobile/features/photos/best_moments/moment_selection.dart';
import 'package:pictoiq_mobile/features/photos/clutter/clutter_classifier.dart'
    show ClutterBlur, ClutterKind;
import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart'
    show VideoKeep;
import 'package:pictoiq_mobile/shared/similarity_grouping.dart'
    show ContentFilter, DocumentMode, MatchLevel, TimeMode;

const _green = AppColors.primary;
const _muted = AppColors.body;

/// The groups of settings that belong to one tool. The same controls are
/// shown on the Settings page, on a tool's Find screen and above its results.
enum SettingsCategory {
  bestMoments('Best moments', 'Update Best Moments Filter'),
  bestShot('Best shot and similar photos', 'Update Best Shots Filter'),
  duplicates('Exact duplicates', 'Update Duplicate Photo Filter'),
  clutter('Clutter', 'Update Clutter Filter'),
  video('Exact duplicate videos', 'Update Duplicate Video Filter');

  const SettingsCategory(this.title, this.filterTitle);
  final String title;

  /// The heading of the collapsible panel on a Find screen.
  final String filterTitle;
}

typedef SettingsChanged = ValueChanged<AppSettings>;

/// A one-line description of the settings that shape a tool's results.
String settingsSummary(SettingsCategory category, AppSettings s) =>
    settingsParts(category, s).join(' · ');

/// The same description as short pieces, shown as chips.
List<String> settingsParts(SettingsCategory category, AppSettings s) {
  return switch (category) {
    SettingsCategory.bestMoments => [
      s.momentWindow.label,
      if (s.momentPlace != MomentPlace.off) s.momentPlace.label,
      '${s.momentCount} photo${s.momentCount == 1 ? '' : 's'} each',
      if (s.momentShowScenes) 'with no-people moments',
    ],
    SettingsCategory.bestShot => [
      '${s.matchLevel.label} match',
      if (s.timeMode != TimeMode.off) 'time: ${s.timeMode.label}',
      s.contentFilter.label,
      if (s.bestShotSelection == BestShotSelection.multiple) 'keep several',
    ],
    SettingsCategory.duplicates => [
      s.contentFilter.label,
      'documents: ${s.documentMode.label}',
    ],
    SettingsCategory.clutter => [
      s.clutterOff.length == ClutterKind.values.length
          ? 'nothing looked for'
          : '${ClutterKind.values.length - s.clutterOff.length} of ${ClutterKind.values.length} types',
      '${s.clutterBlur.label} blur',
    ],
    SettingsCategory.video => ['keep the ${s.videoKeep.label.toLowerCase()}'],
  };
}

/// "Last 7 days (7 Nov 2026 – 14 Nov 2026)" becomes "Last 7 days".
String shortRange(String range) => range.split(' (').first;

List<Widget> settingsChildrenFor(
  SettingsCategory category,
  AppSettings s,
  SettingsChanged change,
) => switch (category) {
  SettingsCategory.bestMoments => momentSettingsChildren(s, change),
  SettingsCategory.bestShot => bestShotSettingsChildren(s, change),
  SettingsCategory.duplicates => duplicateSettingsChildren(s, change),
  SettingsCategory.clutter => clutterSettingsChildren(s, change),
  SettingsCategory.video => videoSettingsChildren(s, change),
};

List<Widget> duplicateSettingsChildren(
  AppSettings s,
  SettingsChanged change,
) => [
  settingsChoice<ContentFilter>(
    title: 'Which photos to include',
    values: ContentFilter.values,
    selected: s.contentFilter,
    label: (mode) => mode.label,
    onSelected: (mode) => change(s.copyWith(contentFilter: mode)),
    note: s.contentFilter.description,
  ),
  settingsChoice<DocumentMode>(
    title: 'Documents and screenshots of pages',
    values: DocumentMode.values,
    selected: s.documentMode,
    label: (mode) => mode.label,
    onSelected: (mode) => change(s.copyWith(documentMode: mode)),
    note: s.documentMode.description,
  ),
];

List<Widget> momentSettingsChildren(AppSettings s, SettingsChanged change) => [
          settingsChoice<MomentWindow>(
            title: 'How long a moment can last',
            values: MomentWindow.values,
            selected: s.momentWindow,
            label: (window) => window.label,
            onSelected: (window) =>
                change(s.copyWith(momentWindow: window)),
            note:
                '${s.momentWindow.description} Needs a camera time on the photos.',
          ),
          settingsChoice<MomentPlace>(
            title: 'Keep different places apart',
            values: MomentPlace.values,
            selected: s.momentPlace,
            label: (place) => place.label,
            onSelected: (place) =>
                change(s.copyWith(momentPlace: place)),
            note:
                '${s.momentPlace.description} Uses the location saved in the photo; Android may hide it.',
          ),
          settingsChoice<MatchLevel>(
            title: 'How closely clothing must match',
            values: MatchLevel.values,
            selected: s.momentPeople,
            label: (level) => level.label,
            onSelected: (level) =>
                change(s.copyWith(momentPeople: level)),
          ),
          settingsSwitch(
            title: 'Separate portraits, couples and groups',
            subtitle:
                'A portrait and a family photo at the same place become different moments. Face counts are approximate.',
            value: s.momentSeparateTypes,
            onChanged: (value) =>
                change(s.copyWith(momentSeparateTypes: value)),
          ),
          settingsSwitch(
            title: 'Show moments with no people',
            subtitle:
                'Objects, rooms and screenshots. Usually clutter, so they are hidden.',
            value: s.momentShowScenes,
            onChanged: (value) =>
                change(s.copyWith(momentShowScenes: value)),
          ),
          settingsChoice<int>(
            title: 'Photos shown per moment',
            values: const [1, 2, 3],
            selected: s.momentCount,
            label: (count) => '$count',
            onSelected: (count) =>
                change(s.copyWith(momentCount: count)),
          ),
          settingsChoice<MomentVariety>(
            title: 'Variety between the photos shown',
            values: MomentVariety.values,
            selected: s.momentVariety,
            label: (variety) => variety.label,
            onSelected: (variety) =>
                change(s.copyWith(momentVariety: variety)),
            note: s.momentVariety.description,
          ),
          settingsChoice<MomentExpression>(
            title: 'Smiles and candid shots',
            values: MomentExpression.values,
            selected: s.momentExpression,
            label: (expression) => expression.label,
            onSelected: (expression) =>
                change(s.copyWith(momentExpression: expression)),
            note: s.momentExpression.description,
          ),
];

List<Widget> bestShotSettingsChildren(AppSettings s, SettingsChanged change) => [
          settingsChoice<BestShotSelection>(
            title: 'Photos to keep from each group',
            values: BestShotSelection.values,
            selected: s.bestShotSelection,
            label: (mode) => mode == BestShotSelection.single
                ? 'Single best shot'
                : 'Multiple photos',
            onSelected: (mode) =>
                change(s.copyWith(bestShotSelection: mode)),
            note: s.bestShotSelection == BestShotSelection.single
                ? 'Keep one photo from each group. Choosing another photo replaces your choice.'
                : 'Choose as many photos as you like from each group. Tap a photo to add it to, or remove it from, the ones to keep. Everything else in the group can then be deleted after you confirm.',
          ),
          settingsChoice<MatchLevel>(
            title: 'How closely photos must match',
            values: MatchLevel.values,
            selected: s.matchLevel,
            label: (level) => level.label,
            onSelected: (level) =>
                change(s.copyWith(matchLevel: level)),
            note: s.matchLevel.description,
          ),
          settingsChoice<TimeMode>(
            title: 'Also use time taken',
            values: TimeMode.values,
            selected: s.timeMode,
            label: (mode) => mode.label,
            onSelected: (mode) =>
                change(s.copyWith(timeMode: mode)),
            note:
                '${s.timeMode.description}${s.timeMode == TimeMode.off || s.timeMode == TimeMode.hint ? '' : ' Uses camera time, else a date in the file name, else the file date; files that were copied or downloaded can carry misleading dates, and then fewer photos will group.'}',
          ),
          settingsChoice<ContentFilter>(
            title: 'Which photos to include',
            values: ContentFilter.values,
            selected: s.contentFilter,
            label: (mode) => mode.label,
            onSelected: (mode) =>
                change(s.copyWith(contentFilter: mode)),
            note: s.contentFilter.description,
          ),
          settingsChoice<DocumentMode>(
            title: 'Documents and screenshots of pages',
            values: DocumentMode.values,
            selected: s.documentMode,
            label: (mode) => mode.label,
            onSelected: (mode) =>
                change(s.copyWith(documentMode: mode)),
            note: s.documentMode.description,
          ),
          settingsSwitch(
            title: 'Use faces and eyes when ranking',
            subtitle:
                'Detects faces on this device to prefer open eyes and smiles. Turn off for faster scans that rank on sharpness, lighting and resolution only.',
            value: s.useFaceSignals,
            onChanged: (value) =>
                change(s.copyWith(useFaceSignals: value)),
          ),
          settingsSwitch(
            title: 'Keep different people apart',
            subtitle:
                'Keeps photos with different numbers of people, or a main person dressed in clearly different colours, in separate groups. A rough check, not face recognition. Needs "Use faces and eyes" on.',
            value: s.splitByPeople,
            onChanged: (value) =>
                change(s.copyWith(splitByPeople: value)),
          ),
          settingsSwitch(
            title: 'I choose which photos to keep',
            subtitle:
                'PictoIQ never picks a photo to keep in similar-shot groups. Nothing is selected for deletion until you choose a photo to keep.',
            value: s.manualSelectionOnly,
            onChanged: (value) =>
                change(s.copyWith(manualSelectionOnly: value)),
          ),
];

List<Widget> clutterSettingsChildren(AppSettings s, SettingsChanged change) => [
          settingsKindChips(s, change),
          settingsChoice<ClutterBlur>(
            title: 'How blurry counts as blurry',
            values: ClutterBlur.values,
            selected: s.clutterBlur,
            label: (blur) => blur.label,
            onSelected: (blur) =>
                change(s.copyWith(clutterBlur: blur)),
            note:
                '${s.clutterBlur.description} Photos with faces are never listed as blurry, documents or tiny. Turning off "Use faces and eyes" under Best shot removes that protection.',
          ),
];

List<Widget> videoSettingsChildren(AppSettings s, SettingsChanged change) => [
          settingsChoice<VideoKeep>(
            title: 'Copy to keep',
            values: VideoKeep.values,
            selected: s.videoKeep,
            label: (keep) => keep.label,
            onSelected: (keep) =>
                change(s.copyWith(videoKeep: keep)),
            note:
                '${s.videoKeep.description} You can still pick a different one in each set before deleting.',
          ),
];

Widget settingsChoice<T>({
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
          child: Text(
            note,
            style: const TextStyle(fontSize: 12, color: _muted),
          ),
        ),
    ],
  ),
);

Widget settingsSwitch({
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

/// One chip per kind of clutter; a lit chip means it is looked for.
Widget settingsKindChips(AppSettings s, SettingsChanged change) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 4),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Look for', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final kind in ClutterKind.values)
            FilterChip(
              label: Text(kind.title),
              selected: !s.clutterOff.contains(kind),
              showCheckmark: false,
              onSelected: (on) => change(
                s.copyWith(
                  clutterOff: on
                      ? ({...s.clutterOff}..remove(kind))
                      : {...s.clutterOff, kind},
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        s.clutterOff.length == ClutterKind.values.length
            ? 'Everything is turned off, so a clutter scan finds nothing.'
            : 'Lit types are looked for. Each photo is listed under its first reason, in the order shown.',
        style: const TextStyle(fontSize: 12, color: _muted),
      ),
    ],
  ),
);

/// A white card whose header has a chevron on the left and an optional
/// widget on the right (such as a ⋮ menu); tapping the header shows or hides
/// [body].
class CollapsiblePanel extends StatefulWidget {
  const CollapsiblePanel({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.body,
    this.initiallyExpanded = false,
    this.chevronAtEnd = false,
    this.margin = EdgeInsets.zero,
  });

  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final Widget body;
  final bool initiallyExpanded;

  /// Puts the chevron at the right end of the header instead of the left.
  final bool chevronAtEnd;
  final EdgeInsetsGeometry margin;

  @override
  State<CollapsiblePanel> createState() => _CollapsiblePanelState();
}

class _CollapsiblePanelState extends State<CollapsiblePanel> {
  late bool _open = widget.initiallyExpanded;

  Widget _chevron() => Tooltip(
    message: _open ? 'Hide settings' : 'Show settings',
    child: AnimatedRotation(
      // Right-pointing chevron at the left turns down; at the right it is a
      // down arrow that turns up.
      turns: widget.chevronAtEnd ? (_open ? 0.5 : 0) : (_open ? 0.25 : 0),
      duration: const Duration(milliseconds: 180),
      child: Icon(
        widget.chevronAtEnd ? Icons.expand_more : Icons.chevron_right,
        color: _green,
        size: 26,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: widget.margin,
    // A Material (not a coloured DecoratedBox) so the switches and chips
    // inside can paint their splashes.
    child: Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.tintBorder),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.chevronAtEnd ? 14 : 4,
                    10,
                    8,
                    10,
                  ),
                  child: Row(
                    children: [
                      if (!widget.chevronAtEnd) ...[_chevron(), const SizedBox(width: 4)],
                      widget.leading,
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            widget.title,
                            if (widget.subtitle != null) ...[
                              const SizedBox(height: 2),
                              widget.subtitle!,
                            ],
                          ],
                        ),
                      ),
                      if (widget.chevronAtEnd) _chevron(),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
        if (_open) widget.body,
      ],
    ),
    ),
  );
}

/// The current settings of one tool, editable in place. Changes are applied
/// and saved at once through [onChanged] and used the next time the tool runs.
class CategorySettingsBody extends StatefulWidget {
  const CategorySettingsBody({
    super.key,
    required this.category,
    required this.settings,
    required this.onChanged,
    this.inset = true,
  });

  final SettingsCategory category;
  final AppSettings settings;
  final SettingsChanged onChanged;

  /// False when the parent already provides side padding.
  final bool inset;

  @override
  State<CategorySettingsBody> createState() => _CategorySettingsBodyState();
}

class _CategorySettingsBodyState extends State<CategorySettingsBody> {
  late AppSettings _s = widget.settings;

  void _change(AppSettings s) {
    setState(() => _s = s);
    widget.onChanged(s);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: widget.inset
        ? const EdgeInsets.fromLTRB(16, 0, 16, 12)
        : EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.inset) const Divider(height: 1),
        ...settingsChildrenFor(widget.category, _s, _change),
        const SizedBox(height: 8),
        const Text(
          'Changes are saved and used the next time you tap Find.',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
      ],
    ),
  );
}

/// The collapsible "current settings" panel for a tool, used on its Find
/// screen. [summary] is shown while collapsed.
class CategorySettingsPanel extends StatefulWidget {
  const CategorySettingsPanel({
    super.key,
    required this.category,
    required this.settings,
    required this.onChanged,
  });

  final SettingsCategory category;
  final AppSettings settings;
  final SettingsChanged onChanged;

  @override
  State<CategorySettingsPanel> createState() => _CategorySettingsPanelState();
}

class _CategorySettingsPanelState extends State<CategorySettingsPanel> {
  late AppSettings _s = widget.settings;

  @override
  Widget build(BuildContext context) => CollapsiblePanel(
    leading: const Icon(Icons.tune, color: _green, size: 22),
    chevronAtEnd: true,
    title: Text(
      widget.category.filterTitle,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    ),
    subtitle: Text(
      settingsSummary(widget.category, _s),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: _muted),
    ),
    body: CategorySettingsBody(
      category: widget.category,
      settings: _s,
      onChanged: (s) {
        setState(() => _s = s);
        widget.onChanged(s);
      },
    ),
  );
}

/// The card at the top of every results screen: what was scanned, the filters
/// that were used, and (when opened) the scan's facts and the editable
/// filters. After a filter is changed it offers "Find again", because the
/// change only applies to the next Find.
class ScanScopeCard extends StatefulWidget {
  const ScanScopeCard({
    super.key,
    required this.folder,
    required this.range,
    required this.counts,
    required this.category,
    required this.settings,
    required this.scannedWith,
    required this.onChanged,
    required this.onFindAgain,
    this.scannedLine,
    this.onViewFiles,
    this.menu,
    this.margin = EdgeInsets.zero,
  });

  final String folder;

  /// The date range as the scan reported it, e.g. "Last 7 days (7 Nov – 14 Nov)".
  final String range;

  /// e.g. "143 photos scanned · 12 groups".
  final String counts;

  /// A longer line for the opened card, e.g. "143 of 150 photos".
  final String? scannedLine;
  final SettingsCategory category;
  final AppSettings settings;

  /// The settings the results on screen were found with.
  final AppSettings scannedWith;
  final SettingsChanged onChanged;
  final VoidCallback onFindAgain;
  final VoidCallback? onViewFiles;

  /// Shown at the right of the header, e.g. a ⋮ menu.
  final Widget? menu;
  final EdgeInsetsGeometry margin;

  @override
  State<ScanScopeCard> createState() => _ScanScopeCardState();
}

class _ScanScopeCardState extends State<ScanScopeCard> {
  bool _open = false;
  late AppSettings _s = widget.settings;

  Widget _fact(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _green),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );

  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: AppColors.tint,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final changed = _s != widget.scannedWith;
    return Padding(
      padding: widget.margin,
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AppColors.tintBorder),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _open = !_open),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title row: what this card is, and the control.
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Scan details',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .4,
                                    color: _muted,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
                                decoration: BoxDecoration(
                                  color: AppColors.tint,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.tune,
                                      size: 16,
                                      color: _green,
                                    ),
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Filters',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    AnimatedRotation(
                                      turns: _open ? 0.5 : 0,
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      child: const Icon(
                                        Icons.expand_more,
                                        size: 18,
                                        color: _green,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.folder} · ${shortRange(widget.range)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.counts,
                            style: const TextStyle(fontSize: 12, color: _muted),
                          ),
                          if (!_open) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                for (final part in settingsParts(
                                  widget.category,
                                  _s,
                                ))
                                  _chip(part),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.menu != null) widget.menu! else const SizedBox(width: 8),
              ],
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 1),
                    const SizedBox(height: 10),
                    const Text(
                      'This scan',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    _fact(Icons.folder_open_outlined, widget.folder),
                    _fact(Icons.date_range_outlined, widget.range),
                    if (widget.scannedLine != null)
                      _fact(Icons.photo_library_outlined, widget.scannedLine!),
                    if (widget.onViewFiles != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: widget.onViewFiles,
                          child: const Text('View scanned files'),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(
                      widget.category.filterTitle.replaceFirst('Update ', ''),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    CategorySettingsBody(
                      category: widget.category,
                      settings: _s,
                      inset: false,
                      onChanged: (value) {
                        setState(() => _s = value);
                        widget.onChanged(value);
                      },
                    ),
                    if (changed) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: widget.onFindAgain,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Find again with these filters'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
