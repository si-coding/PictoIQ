# PictoIQ architecture

Everything runs on the device. Code is split into three layers; a layer may use the ones below it, never the ones above.

```
lib/
├── main.dart                 App shell and the home screen
├── features/                 What the person uses (depends on core and shared)
│   ├── photos/
│   │   ├── best_shot/        selection_policy.dart
│   │   ├── best_moments/     moment_selection.dart
│   │   ├── duplicates/       folder_duplicate_scanner.dart
│   │   └── library/          album pickers, scanned files, photo viewer
│   ├── settings/             app_settings.dart, settings_page.dart
│   ├── photos/share/         share_preview_page.dart (review photos before sharing)
│   ├── splash/               splash_page.dart (animated PictoIQ wordmark after the native launch screen)
│   └── videos/               Planned; interfaces and folders only
│       ├── library/  duplicates/  similarity/  moments/
│       ├── enhancement/  player/  export/
│       ├── domain/           models, repositories, use_cases
│       ├── data/             repositories, sources
│       └── application/      controllers, providers
├── shared/                   Photo and video engines that know no screen
│   ├── event_grouping.dart
│   ├── similarity_grouping.dart
│   ├── shot_ranking.dart
│   └── media_quality_scoring.dart
└── core/                     Device services (depends on nothing above it)
    ├── media/                media_asset, access, metadata, fingerprint, permissions, image_processing
    ├── video/                player, frames, metadata, processing, export
    ├── ml/                   model_manager, inference_service, model_registry
    └── database/             database_service (was library_store), migrations/
```

`shared/app_background.dart` (`AppBackground`, `AppScaffold`) gives every screen the same light page background (the fresh green is only the header/app bar), and the scan results screen uses `AppBackground` too; `shared/app_bar_title.dart` (`AppBarTitle`) puts each screen's own icon in the header (the logo only appears on the home screen); new screens should use `AppScaffold`, not `Scaffold`. `shared/app_back_button.dart` is the white round back button used by every app bar; app bar colours come from `AppBarTheme` in `main.dart` (set from `AppColors`).

The scan-finished popup is queued by `_showResultPopup` and opened by `_flushPopup` once the scan configuration screen has closed itself (opening it earlier would be closed by that pop). Result cards are named "Group N · count · time" (best shot) or "Moment N · kind · time" (best moments) by `_groupName`.

The results screen is a stack of white cards: a summary card (headline, numbers, Clean up all / Review all), the share card, a scope strip (folder, date range, photos scanned, scan menu) right above the group cards. The documents setting leaves out pages of text and files named like screenshots (`looksLikeScreenshotFile`); photos of a screen or slide cannot be told from other photos without an object-recognition model.

The "which photos to include" setting (`ContentFilter`) runs ML Kit image labelling (`_labelContent` in the folder scanner) only on photos with no faces, and `isPeopleOrScenery` in `shared/photo_content.dart` decides what is left out. Unknown or failed labelling keeps the photo. A face only counts when it fills at least 0.2% of the picture (`prominentFaceArea`), so a distant presenter does not turn a photo of a slide into a people photo, and the labeller's people/scenery labels must be about as sure as its screen/object labels. Clutter has a "Screens & objects" kind (`ClutterKind.screenOrObject`) that uses the same labels. Every screen except Home has the three-dot `AppMenuButton` (Settings, Privacy); Home registers its actions in `AppMenuActions`.

Rules: `core/` and `shared/` never import `features/`. Imports use `package:pictoiq_mobile/...`.

## Where the old files went

| Before | Now |
|---|---|
| photo_asset.dart | core/media/media_asset.dart (adds `MediaKind`) |
| scan_image_processing.dart | core/media/image_processing.dart |
| library_store.dart | core/database/database_service.dart |
| event_grouping.dart, similarity_grouping.dart, shot_ranking.dart | shared/ |
| selection_policy.dart | features/photos/best_shot/ |
| moment_selection.dart | features/photos/best_moments/ |
| folder_duplicate_scanner.dart | features/photos/duplicates/ |
| album_contents_page, album_picker_page, scanned_files_page, photo_viewer_page | features/photos/library/ |
| app_settings.dart, settings_page.dart | features/settings/ |

File moves only: no class was renamed or changed. `features/photos/library/` and `features/settings/` are additions to the plan.

## Video status

The home screen has a Photos | Videos switch with four video tiles. **Exact Duplicates is built** (`features/videos/duplicates/`); the other three are "Coming soon". Under `core/video/`, `core/media/` and `features/videos/domain/models` there are still only interfaces and one model. Build order:

1. Exact duplicate videos (file fingerprints only; no frames). **Done.** `video_duplicates.dart` lists video albums with `photo_manager`, narrows candidates to videos with the same length and picture size, then streams a SHA-256 of only those and groups identical size+hash. `video_duplicates_page.dart` is the review screen. Logic is tested in `test/video_duplicates_test.dart`. Reading a video through `photo_manager` can make a temporary copy on Android 10+, so the scan clears that cache afterwards. Videos in a folder picked with Android's folder picker (SAF) are supported too: they are matched by file size, hashed from the SAF stream, shown without thumbnails and deleted through SAF. `features/videos/library/video_album_picker_page.dart` is the album picker (tapping an album opens `video_album_contents_page.dart`, a scrollable grid with lengths, and `video_player_page.dart` plays a video) (cover and count per album, "Other folder…", and messages for denied, limited or empty access).
2. Video list and player.
3. Similar videos (frame sampling plus `shared/similarity_grouping.dart`).
4. Moments inside a video, then enhancement and export.

## Clutter (photos)

`features/photos/clutter/` holds `clutter_classifier.dart` (pure Dart, tested in `test/clutter_classifier_test.dart`) and `clutter_page.dart`. The Clutter tile runs `FolderDuplicateScanner.scanUri(bestShotsScan: true, groupShots: false)`, which analyses every photo but skips grouping, then `findClutter` assigns each photo at most one `ClutterKind` and the page shows them for review. Deletion goes through `FolderDuplicateScanner.deleteFiles`, so Android confirms once for the whole batch.

## Settings next to the results

`features/settings/category_settings.dart` holds the controls for each tool (`SettingsCategory`, `settingsChildrenFor`) so the same widgets are used by the Settings page, by a tool's Find screen (`ScanConfigurationPage.settingsPanel`, collapsible, above the date range) and above results (`CollapsiblePanel` in the scope strip of the similar-photo results, and in `ClutterPage` / `VideoDuplicatesPage` via `settingsPanel`). Every change goes through `_updateSettings`, so it is saved at once and used by the next Find. Result screens also have a search icon (`onFind`) that opens the tool's Find screen. Scan buttons are labelled "Find …". Tested in `test/category_settings_test.dart`.

Browse and results screens have no back arrow: `AppHomeButton` (shared/app_back_button.dart) sits left of the ⋮ menu and returns to the home screen (`popUntil(isFirst)`, or `_showResultsPage = false` for the inline results). `AppMenuActions.goHome` (set by `LibraryPage`) closes all routes above the home screen and hides the results page, so Home always lands on the home screen even when a Find screen was opened from the results. The Android back gesture still goes back one screen.

After a scan, results that were found open directly with no pop-up; only "nothing found" shows a short notice that closes itself after four seconds. Every results screen (best moments, best shot, exact duplicates, clutter, exact duplicate videos) starts with `ScanScopeCard`: a two-line header (folder · short range, counts), the filters as chips, and a "Filters" control that opens the scan's facts and the editable filters; after a filter differs from the one used for the scan it offers "Find again with these filters" (opens the Find screen). The Find screens' filter panel is titled "Update … Filter" with its chevron at the right. The home header shows Photos, Videos (when videos are enabled) and Albums totals, with "100% on device" as a line below them.

## Feature flags

`core/config/feature_flags.dart` (`FeatureFlags.current.videoEnabled`, from `--dart-define=PICTOIQ_VIDEO`). `main.dart` reads it to show or hide the Photos | Videos switch, `SettingsPage(showVideoSettings:)` hides the Videos section, and `FolderDuplicateScanner.requestMediaAccess` asks for photo access only when videos are off. Video code is not otherwise touched; it is simply never reached.

## Photo reels

`features/videos/export/reel_configuration_page.dart` is the editor (title, title style, audio, drag to reorder; the whole page scrolls and the photo grid auto-scrolls while dragging). `core/video/video_reel_service.dart` talks to Android over the `com.pictoiq.app/video_reel` channels; `PhotoReelEncoder.kt` draws each frame (1080x1920, 30 fps, H.264), re-encodes the chosen audio to AAC, trims it to the reel length and muxes both into one MP4. Old reels are deleted from the cache before a new one is made.
