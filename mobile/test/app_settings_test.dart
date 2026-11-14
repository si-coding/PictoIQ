import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pictoiq_mobile/features/settings/app_settings.dart';
import 'package:pictoiq_mobile/features/photos/best_moments/moment_selection.dart';
import 'package:pictoiq_mobile/features/photos/clutter/clutter_classifier.dart'
    show ClutterBlur, ClutterKind;
import 'package:pictoiq_mobile/features/videos/duplicates/video_duplicates.dart'
    show VideoKeep;
import 'package:pictoiq_mobile/shared/similarity_grouping.dart';

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
    expect(settings.bestShotSelection, BestShotSelection.single);
    expect(settings.useFaceSignals, isTrue);
    expect(settings.groupSessions, isFalse);
    expect(settings.matchLevel, MatchLevel.balanced);
    expect(settings.splitByPeople, isTrue);
    expect(settings.showEvents, isTrue);
    expect(settings.documentMode, DocumentMode.leaveOut);
    expect(settings.timeMode, TimeMode.hint);
  });

  test('reel settings default and survive a save', () async {
    expect(const AppSettings().reelMaxPhotos, 15);
    expect(const AppSettings().reelSecondsPerPhoto, 3);
    expect(const AppSettings().reelTransitionMillis, 400);
    expect(const AppSettings().reelTitleStyle, ReelTitleStyle.clean);

    const saved = AppSettings(
      reelMaxPhotos: 20,
      reelSecondsPerPhoto: 5,
      reelTransitionMillis: 750,
      reelTitleStyle: ReelTitleStyle.elegant,
    );
    await store.save(saved);
    expect(await store.load(), saved);
  });

  test('best moments options survive a save', () async {
    const saved = AppSettings(
      momentWindow: MomentWindow.outing,
      momentCount: 3,
      momentVariety: MomentVariety.strong,
      momentExpression: MomentExpression.candid,
      momentPeople: MatchLevel.loose,
      momentSeparateTypes: false,
      momentShowScenes: true,
      momentPlace: MomentPlace.area,
    );
    await store.save(saved);
    expect(await store.load(), saved);
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

  test('clutter and video options survive a save, and bad values fall back',
      () async {
    const saved = AppSettings(
      clutterOff: {ClutterKind.document, ClutterKind.small},
      clutterBlur: ClutterBlur.strict,
      videoKeep: VideoKeep.newest,
    );
    await store.save(saved);
    final loaded = await store.load();
    expect(loaded, saved);
    expect(loaded.clutterOff, {ClutterKind.document, ClutterKind.small});
    expect(const AppSettings().clutterOff, isEmpty);
    expect(const AppSettings().clutterBlur, ClutterBlur.balanced);
    expect(const AppSettings().videoKeep, VideoKeep.oldest);
    final bad = AppSettings.fromJson({
      'clutterOff': 'nope',
      'clutterBlur': 'x',
      'videoKeep': 3,
    });
    expect(bad.clutterOff, isEmpty);
    expect(bad.clutterBlur, ClutterBlur.balanced);
    expect(bad.videoKeep, VideoKeep.oldest);
    expect(
      const AppSettings(clutterOff: {ClutterKind.blank}) ==
          const AppSettings(clutterOff: {ClutterKind.small}),
      isFalse,
    );
  });

  test('best shot selection mode survives a save and ignores bad values', () async {
    const saved = AppSettings(bestShotSelection: BestShotSelection.multiple);
    await store.save(saved);
    expect((await store.load()).bestShotSelection, BestShotSelection.multiple);
    expect(
      AppSettings.fromJson({'bestShotSelection': 'many'}).bestShotSelection,
      BestShotSelection.single,
    );
    expect(
      const AppSettings(bestShotSelection: BestShotSelection.multiple) ==
          const AppSettings(),
      isFalse,
    );
  });

  test('content filter survives a save and ignores bad values', () async {
    await store.save(
      const AppSettings(contentFilter: ContentFilter.peopleAndScenery),
    );
    expect(
      (await store.load()).contentFilter,
      ContentFilter.peopleAndScenery,
    );
    expect(
      AppSettings.fromJson({'contentFilter': 'x'}).contentFilter,
      ContentFilter.everything,
    );
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
