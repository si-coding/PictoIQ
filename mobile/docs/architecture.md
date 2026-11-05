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

1. Exact duplicate videos (file fingerprints only; no frames). **Done.** `video_duplicates.dart` lists video albums with `photo_manager`, narrows candidates to videos with the same length and picture size, then streams a SHA-256 of only those and groups identical size+hash. `video_duplicates_page.dart` is the review screen. Logic is tested in `test/video_duplicates_test.dart`. Reading a video through `photo_manager` can make a temporary copy on Android 10+, so the scan clears that cache afterwards. Folder (SAF) videos are not supported yet, only media-library albums.
2. Video list and player.
3. Similar videos (frame sampling plus `shared/similarity_grouping.dart`).
4. Moments inside a video, then enhancement and export.

## Clutter (photos)

`features/photos/clutter/` holds `clutter_classifier.dart` (pure Dart, tested in `test/clutter_classifier_test.dart`) and `clutter_page.dart`. The Clutter tile runs `FolderDuplicateScanner.scanUri(bestShotsScan: true, groupShots: false)`, which analyses every photo but skips grouping, then `findClutter` assigns each photo at most one `ClutterKind` and the page shows them for review. Deletion goes through `FolderDuplicateScanner.deleteFiles`, so Android confirms once for the whole batch.
