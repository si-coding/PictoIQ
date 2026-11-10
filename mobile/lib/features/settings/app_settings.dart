import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:pictoiq_mobile/features/photos/best_moments/moment_selection.dart';
import 'package:pictoiq_mobile/features/photos/clutter/clutter_classifier.dart'
    show ClutterBlur, ClutterKind;
import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart'
    show VideoKeep;
import 'package:pictoiq_mobile/shared/similarity_grouping.dart' show DocumentMode, MatchLevel, TimeMode;

enum ReelTitleStyle { clean, bold, elegant }

/// Preferences that outlive one run of the app.
class AppSettings {
  const AppSettings({
    this.manualSelectionOnly = false,
    this.useFaceSignals = true,
    this.groupSessions = false,
    this.matchLevel = MatchLevel.balanced,
    this.splitByPeople = true,
    this.showEvents = true,
    this.timeMode = TimeMode.hint,
    this.documentMode = DocumentMode.leaveOut,
    this.momentWindow = MomentWindow.activity,
    this.momentCount = 2,
    this.momentVariety = MomentVariety.balanced,
    this.momentPeople = MatchLevel.balanced,
    this.momentExpression = MomentExpression.balanced,
    this.momentSeparateTypes = true,
    this.momentShowScenes = false,
    this.momentPlace = MomentPlace.off,
    this.clutterOff = const {},
    this.clutterBlur = ClutterBlur.balanced,
    this.videoKeep = VideoKeep.oldest,
    this.reelMaxPhotos = 15,
    this.reelSecondsPerPhoto = 3,
    this.reelTransitionMillis = 400,
    this.reelTitleStyle = ReelTitleStyle.clean,
  });

  /// When true, PictoIQ never picks a similar photo to keep: the user marks
  /// the ones to keep, and nothing is selected for deletion until they do.
  final bool manualSelectionOnly;

  /// Whether face and eye detection feed the best-shot ranking. Turning it off
  /// makes scans faster and ranks on sharpness, lighting and resolution only.
  final bool useFaceSignals;

  /// When true, similar-photo scans also group photos of the same scene taken
  /// up to ten minutes apart, so a photo session is reviewed as one group.
  final bool groupSessions;

  /// How readily similar-photo scans group pictures.
  final MatchLevel matchLevel;

  /// Keep photos with clearly different numbers of people in separate groups.
  final bool splitByPeople;

  /// Show event headings (by camera time or a date in the file name) above
  /// the groups in the results.
  final bool showEvents;

  /// How capture time takes part in grouping. The default only uses reliable
  /// camera times as a hint; file dates are never trusted, because copied
  /// files carry misleading ones.
  final TimeMode timeMode;

  /// What to do with pages of text and similar document images.
  final DocumentMode documentMode;

  /// Best moments: how far apart in time the photos of one moment may be.
  final MomentWindow momentWindow;

  /// Best moments: how many photos are shown for each moment (1 to 3).
  final int momentCount;

  /// Best moments: how different the shown photos should be from each other.
  final MomentVariety momentVariety;

  /// Best moments: how closely the people (by clothing colour) must match.
  final MatchLevel momentPeople;

  /// Best moments: whether smiles count more or less.
  final MomentExpression momentExpression;

  /// Best moments: keep single, couple and group photos in separate moments.
  final bool momentSeparateTypes;

  /// Best moments: also list moments with no people in them (objects,
  /// rooms, screenshots). Off by default: they are mostly clutter.
  final bool momentShowScenes;

  /// Best moments: keep photos taken in different places apart.
  final MomentPlace momentPlace;

  /// Clutter: the kinds of clutter that are not looked for. Empty means all.
  final Set<ClutterKind> clutterOff;

  /// Clutter: how soft a photo must be to count as blurry.
  final ClutterBlur clutterBlur;

  /// Exact duplicate videos: which video of a set is kept by default.
  final VideoKeep videoKeep;

  /// Maximum photos included by default when opening the reel editor.
  final int reelMaxPhotos;

  /// How long each photo remains in the generated reel.
  final int reelSecondsPerPhoto;

  /// Crossfade duration between photos; zero disables transitions.
  final int reelTransitionMillis;

  /// Default style for an optional title on the first reel photo.
  final ReelTitleStyle reelTitleStyle;

  AppSettings copyWith({
    bool? manualSelectionOnly,
    bool? useFaceSignals,
    bool? groupSessions,
    MatchLevel? matchLevel,
    bool? splitByPeople,
    bool? showEvents,
    TimeMode? timeMode,
    DocumentMode? documentMode,
    MomentWindow? momentWindow,
    int? momentCount,
    MomentVariety? momentVariety,
    MatchLevel? momentPeople,
    MomentExpression? momentExpression,
    bool? momentSeparateTypes,
    bool? momentShowScenes,
    MomentPlace? momentPlace,
    Set<ClutterKind>? clutterOff,
    ClutterBlur? clutterBlur,
    VideoKeep? videoKeep,
    int? reelMaxPhotos,
    int? reelSecondsPerPhoto,
    int? reelTransitionMillis,
    ReelTitleStyle? reelTitleStyle,
  }) => AppSettings(
    manualSelectionOnly: manualSelectionOnly ?? this.manualSelectionOnly,
    useFaceSignals: useFaceSignals ?? this.useFaceSignals,
    groupSessions: groupSessions ?? this.groupSessions,
    matchLevel: matchLevel ?? this.matchLevel,
    splitByPeople: splitByPeople ?? this.splitByPeople,
    showEvents: showEvents ?? this.showEvents,
    timeMode: timeMode ?? this.timeMode,
    documentMode: documentMode ?? this.documentMode,
    momentWindow: momentWindow ?? this.momentWindow,
    momentCount: momentCount ?? this.momentCount,
    momentVariety: momentVariety ?? this.momentVariety,
    momentPeople: momentPeople ?? this.momentPeople,
    momentExpression: momentExpression ?? this.momentExpression,
    momentSeparateTypes: momentSeparateTypes ?? this.momentSeparateTypes,
    momentShowScenes: momentShowScenes ?? this.momentShowScenes,
    momentPlace: momentPlace ?? this.momentPlace,
    clutterOff: clutterOff ?? this.clutterOff,
    clutterBlur: clutterBlur ?? this.clutterBlur,
    videoKeep: videoKeep ?? this.videoKeep,
    reelMaxPhotos: reelMaxPhotos ?? this.reelMaxPhotos,
    reelSecondsPerPhoto: reelSecondsPerPhoto ?? this.reelSecondsPerPhoto,
    reelTransitionMillis: reelTransitionMillis ?? this.reelTransitionMillis,
    reelTitleStyle: reelTitleStyle ?? this.reelTitleStyle,
  );

  Map<String, Object?> toJson() => {
    'manualSelectionOnly': manualSelectionOnly,
    'useFaceSignals': useFaceSignals,
    'groupSessions': groupSessions,
    'matchLevel': matchLevel.name,
    'splitByPeople': splitByPeople,
    'showEvents': showEvents,
    'timeMode': timeMode.name,
    'documentMode': documentMode.name,
    'momentWindow': momentWindow.name,
    'momentCount': momentCount,
    'momentVariety': momentVariety.name,
    'momentPeople': momentPeople.name,
    'momentExpression': momentExpression.name,
    'momentSeparateTypes': momentSeparateTypes,
    'momentShowScenes': momentShowScenes,
    'momentPlace': momentPlace.name,
    'clutterOff': [for (final kind in clutterOff) kind.name]..sort(),
    'clutterBlur': clutterBlur.name,
    'videoKeep': videoKeep.name,
    'reelMaxPhotos': reelMaxPhotos,
    'reelSecondsPerPhoto': reelSecondsPerPhoto,
    'reelTransitionMillis': reelTransitionMillis,
    'reelTitleStyle': reelTitleStyle.name,
  };

  /// Unknown or wrongly typed fields fall back to their defaults.
  factory AppSettings.fromJson(Map<String, Object?> json) {
    const defaults = AppSettings();
    final manual = json['manualSelectionOnly'];
    final faces = json['useFaceSignals'];
    final sessions = json['groupSessions'];
    final level = json['matchLevel'];
    final people = json['splitByPeople'];
    final events = json['showEvents'];
    final time = json['timeMode'];
    final documents = json['documentMode'];
    final window = json['momentWindow'];
    final count = json['momentCount'];
    final variety = json['momentVariety'];
    final momentPeople = json['momentPeople'];
    final expression = json['momentExpression'];
    final separateTypes = json['momentSeparateTypes'];
    final showScenes = json['momentShowScenes'];
    final place = json['momentPlace'];
    final off = json['clutterOff'];
    final blur = json['clutterBlur'];
    final keep = json['videoKeep'];
    final reelPhotos = json['reelMaxPhotos'];
    final reelSeconds = json['reelSecondsPerPhoto'];
    final reelTransition = json['reelTransitionMillis'];
    final reelStyle = json['reelTitleStyle'];
    return AppSettings(
      manualSelectionOnly: manual is bool
          ? manual
          : defaults.manualSelectionOnly,
      useFaceSignals: faces is bool ? faces : defaults.useFaceSignals,
      groupSessions: sessions is bool ? sessions : defaults.groupSessions,
      matchLevel: MatchLevel.values.firstWhere(
        (value) => value.name == level,
        orElse: () => defaults.matchLevel,
      ),
      splitByPeople: people is bool ? people : defaults.splitByPeople,
      showEvents: events is bool ? events : defaults.showEvents,
      timeMode: TimeMode.values.firstWhere(
        (value) => value.name == time,
        orElse: () => defaults.timeMode,
      ),
      documentMode: DocumentMode.values.firstWhere(
        (value) => value.name == documents,
        orElse: () => defaults.documentMode,
      ),
      momentWindow: MomentWindow.values.firstWhere(
        (value) => value.name == window,
        orElse: () => defaults.momentWindow,
      ),
      momentCount: count is int && count >= 1 && count <= 3
          ? count
          : defaults.momentCount,
      momentVariety: MomentVariety.values.firstWhere(
        (value) => value.name == variety,
        orElse: () => defaults.momentVariety,
      ),
      momentPeople: MatchLevel.values.firstWhere(
        (value) => value.name == momentPeople,
        orElse: () => defaults.momentPeople,
      ),
      momentExpression: MomentExpression.values.firstWhere(
        (value) => value.name == expression,
        orElse: () => defaults.momentExpression,
      ),
      momentSeparateTypes: separateTypes is bool
          ? separateTypes
          : defaults.momentSeparateTypes,
      momentShowScenes: showScenes is bool
          ? showScenes
          : defaults.momentShowScenes,
      momentPlace: MomentPlace.values.firstWhere(
        (value) => value.name == place,
        orElse: () => defaults.momentPlace,
      ),
      clutterOff: off is List
          ? {
              for (final kind in ClutterKind.values)
                if (off.contains(kind.name)) kind,
            }
          : defaults.clutterOff,
      clutterBlur: ClutterBlur.values.firstWhere(
        (value) => value.name == blur,
        orElse: () => defaults.clutterBlur,
      ),
      videoKeep: VideoKeep.values.firstWhere(
        (value) => value.name == keep,
        orElse: () => defaults.videoKeep,
      ),
      reelMaxPhotos: reelPhotos is int && reelPhotos >= 1 && reelPhotos <= 30
          ? reelPhotos
          : defaults.reelMaxPhotos,
      reelSecondsPerPhoto:
          reelSeconds is int && reelSeconds >= 2 && reelSeconds <= 6
          ? reelSeconds
          : defaults.reelSecondsPerPhoto,
      reelTransitionMillis:
          reelTransition is int &&
              [0, 250, 400, 500, 750, 1000].contains(reelTransition)
          ? reelTransition
          : defaults.reelTransitionMillis,
      reelTitleStyle: ReelTitleStyle.values.firstWhere(
        (value) => value.name == reelStyle,
        orElse: () => defaults.reelTitleStyle,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.manualSelectionOnly == manualSelectionOnly &&
      other.useFaceSignals == useFaceSignals &&
      other.groupSessions == groupSessions &&
      other.matchLevel == matchLevel &&
      other.splitByPeople == splitByPeople &&
      other.showEvents == showEvents &&
      other.timeMode == timeMode &&
      other.documentMode == documentMode &&
      other.momentWindow == momentWindow &&
      other.momentCount == momentCount &&
      other.momentVariety == momentVariety &&
      other.momentPeople == momentPeople &&
      other.momentExpression == momentExpression &&
      other.momentSeparateTypes == momentSeparateTypes &&
      other.momentShowScenes == momentShowScenes &&
      other.momentPlace == momentPlace &&
      other.clutterOff.length == clutterOff.length &&
      other.clutterOff.containsAll(clutterOff) &&
      other.clutterBlur == clutterBlur &&
      other.videoKeep == videoKeep &&
      other.reelMaxPhotos == reelMaxPhotos &&
      other.reelSecondsPerPhoto == reelSecondsPerPhoto &&
      other.reelTransitionMillis == reelTransitionMillis &&
      other.reelTitleStyle == reelTitleStyle;

  @override
  int get hashCode => Object.hashAll([
    manualSelectionOnly,
    useFaceSignals,
    groupSessions,
    matchLevel,
    splitByPeople,
    showEvents,
    timeMode,
    documentMode,
    momentWindow,
    momentCount,
    momentVariety,
    momentPeople,
    momentExpression,
    momentSeparateTypes,
    momentShowScenes,
    momentPlace,
    Object.hashAll([for (final kind in clutterOff) kind.index]..sort()),
    clutterBlur,
    videoKeep,
    reelMaxPhotos,
    reelSecondsPerPhoto,
    reelTransitionMillis,
    reelTitleStyle,
  ]);
}

/// Keeps [AppSettings] in a small JSON file in the app's private storage.
class SettingsStore {
  SettingsStore({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _directory;

  Future<File> _file() async =>
      File(p.join((await _directory()).path, 'pictoiq_settings.json'));

  /// Returns the defaults when nothing was saved or the file is unreadable.
  Future<AppSettings> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const AppSettings();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, Object?>) return const AppSettings();
      return AppSettings.fromJson(decoded);
    } catch (error) {
      debugPrint('Settings unavailable: ${error.runtimeType}');
      return const AppSettings();
    }
  }

  /// Writes to a temporary file first so a crash cannot leave half a file.
  Future<void> save(AppSettings settings) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(settings.toJson()), flush: true);
    await temporary.rename(file.path);
  }
}
