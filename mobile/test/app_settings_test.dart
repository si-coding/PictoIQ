import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/app_settings.dart';
import 'package:pictoiq_mobile/similarity_grouping.dart';

void main() {
  late Directory directory;
  late SettingsStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pictoiq-settings-');
    store = SettingsStore(directory: () async => directory);
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('defaults let PictoIQ suggest photos and use faces', () {
    const settings = AppSettings();
    expect(settings.manualSelectionOnly, isFalse);
    expect(settings.useFaceSignals, isTrue);
    expect(settings.groupSessions, isFalse);
    expect(settings.matchLevel, MatchLevel.balanced);
    expect(settings.splitByPeople, isTrue);
    expect(settings.showEvents, isTrue);
    expect(settings.documentMode, DocumentMode.leaveOut);
    expect(settings.timeMode, TimeMode.hint);
  });

  test('matching options survive a save, and bad values fall back', () async {
    const saved = AppSettings(
      matchLevel: MatchLevel.loose,
      splitByPeople: false,
      showEvents: false,
      timeMode: TimeMode.session,
      documentMode: DocumentMode.strict,
    );
    await store.save(saved);
    expect(await store.load(), saved);
    final bad = AppSettings.fromJson({
      'matchLevel': 'nonsense',
      'splitByPeople': 'yes',
    });
    expect(bad.matchLevel, MatchLevel.balanced);
    expect(bad.splitByPeople, isTrue);
    expect(bad.timeMode, TimeMode.hint);
    expect(bad.documentMode, DocumentMode.leaveOut);
  });

  test('returns defaults when nothing was saved', () async {
    expect(await store.load(), const AppSettings());
  });

  test('saves and loads settings', () async {
    const saved = AppSettings(
      manualSelectionOnly: true,
      useFaceSignals: false,
      groupSessions: true,
    );
    await store.save(saved);
    expect(await store.load(), saved);
    expect(
      File('${directory.path}/pictoiq_settings.json.tmp').existsSync(),
      isFalse,
    );
  });

  test('falls back to defaults for a corrupt file', () async {
    await File('${directory.path}/pictoiq_settings.json').writeAsString('{oops');
    expect(await store.load(), const AppSettings());
  });

  test('ignores fields with the wrong type', () {
    final settings = AppSettings.fromJson({
      'manualSelectionOnly': 'yes',
      'useFaceSignals': false,
      'unknown': 1,
    });
    expect(settings.manualSelectionOnly, isFalse);
    expect(settings.useFaceSignals, isFalse);
  });

  test('copyWith changes only what is given', () {
    const base = AppSettings(manualSelectionOnly: true);
    final changed = base.copyWith(useFaceSignals: false, groupSessions: true);
    expect(changed.manualSelectionOnly, isTrue);
    expect(changed.useFaceSignals, isFalse);
    expect(changed.groupSessions, isTrue);
  });
}
