import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'similarity_grouping.dart' show DocumentMode, MatchLevel, TimeMode;

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

  AppSettings copyWith({
    bool? manualSelectionOnly,
    bool? useFaceSignals,
    bool? groupSessions,
    MatchLevel? matchLevel,
    bool? splitByPeople,
    bool? showEvents,
    TimeMode? timeMode,
    DocumentMode? documentMode,
  }) => AppSettings(
    manualSelectionOnly: manualSelectionOnly ?? this.manualSelectionOnly,
    useFaceSignals: useFaceSignals ?? this.useFaceSignals,
    groupSessions: groupSessions ?? this.groupSessions,
    matchLevel: matchLevel ?? this.matchLevel,
    splitByPeople: splitByPeople ?? this.splitByPeople,
    showEvents: showEvents ?? this.showEvents,
    timeMode: timeMode ?? this.timeMode,
    documentMode: documentMode ?? this.documentMode,
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
      other.documentMode == documentMode;

  @override
  int get hashCode => Object.hash(
    manualSelectionOnly,
    useFaceSignals,
    groupSessions,
    matchLevel,
    splitByPeople,
    showEvents,
    timeMode,
    documentMode,
  );
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
