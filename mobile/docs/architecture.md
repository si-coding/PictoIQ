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
│   shared/brand_wordmark.dart  Brand colours, tagline style (Poppins Medium Italic) and the tinted wordmark images
│   └── videos/               Planned; interfaces and folders only
│       ├── library/  duplicates/  similarity/  moments/
│       ├── enhancement/  player/  export/
│       ├── domain/           models, repositories, use_cases
│       ├── data/             repositories, sources
│       └── application/      controllers, providers
├── shared/                   Photo and video engines that know no screen
│   ├── event_grouping.dart
│   ├── similarity_grouping.dart
│   └── shot_ranking.dart
└── core/                     Device services (depends on nothing above it)
    ├── media/                media_asset, image_processing
    ├── video/                video_reel_service
    └── database/             database_service (was library_store), migrations/
```

`shared/app_background.dart` (`AppBackground`, `AppScaffold`) gives every screen the same light page background (the fresh green is only the header/app bar), and the scan results screen uses `AppBackground` too; `shared/app_bar_title.dart` (`AppBarTitle`) puts each screen's own icon in the header (the logo only appears on the home screen); new screens should use `AppScaffold`, not `Scaffold`. `shared/app_back_button.dart` is the white round back button used by every app bar; app bar colours come from `AppBarTheme` in `main.dart` (set from `AppColors`).

The scan-finished popup is queued by `_showResultPopup` and opened by `_flushPopup` once the scan configuration screen has closed itself (opening it earlier would be closed by that pop). Result cards are named "Group N · Pair/Trio/Solo/Family or group/Scene · N similar shots" (best shots, `_peopleKind`) or "Moment N · kind · time" (best moments) by `_groupName`; View scanned files uses the same numbers (`_shownGroupLabels`).

The results screen is a stack of white cards: a summary card (headline, numbers, Clean up all / Review all), the share card, a scope strip (folder, date range, photos scanned, scan menu) right above the group cards. The documents setting leaves out pages of text and files named like screenshots (`looksLikeScreenshotFile`); photos of a screen or slide cannot be told from other photos without an object-recognition model.

The "which photos to include" setting (`ContentFilter`) runs ML Kit image labelling (`_labelContent` in the folder scanner) only on photos with no faces, and `isPeopleOrScenery` in `shared/photo_content.dart` decides what is left out. Unknown or failed labelling keeps the photo. A face only counts when it fills at least 0.2% of the picture (`prominentFaceArea`), so a distant presenter does not turn a photo of a slide into a people photo, and the labeller's people/scenery labels must be about as sure as its screen/object labels. Clutter has a "Screens & objects" kind (`ClutterKind.screenOrObject`) that uses the same labels. Home, the Find screens, Choose an album and the results screens have no three-dot menu; Settings and Privacy are reached from Home (`AppMenuActions`).

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

The home screen has a Photos | Videos switch with four video tiles. **Exact videos is built** (`features/videos/duplicates/`); the other three are "Coming soon". The other video tools have no code yet (the unused interface stubs under `core/video`, `core/media`, `core/ml` were deleted on 21 Nov; add them back when a tool needs them). Build order:

1. Exact duplicate videos (file fingerprints only; no frames). **Done.** `video_duplicates.dart` lists video albums with `photo_manager`, narrows candidates to videos with the same length and picture size, then streams a SHA-256 of only those and groups identical size+hash. `video_duplicates_page.dart` is the review screen. Logic is tested in `test/video_duplicates_test.dart`. Reading a video through `photo_manager` can make a temporary copy on Android 10+, so the scan clears that cache afterwards. Videos in a folder picked with Android's folder picker (SAF) are supported too: they are matched by file size, hashed from the SAF stream, shown without thumbnails and deleted through SAF. `features/videos/library/video_album_picker_page.dart` is the album picker (tapping an album opens `video_album_contents_page.dart`, a scrollable grid with lengths, and `video_player_page.dart` plays a video) (cover and count per album, "Other folder…", and messages for denied, limited or empty access).
2. Video list and player.
3. Similar videos (frame sampling plus `shared/similarity_grouping.dart`).
4. Moments inside a video, then enhancement and export.

## Clutter (photos)

`features/photos/clutter/` holds `clutter_classifier.dart` (pure Dart, tested in `test/clutter_classifier_test.dart`) and `clutter_page.dart`. The Clutter tile runs `FolderDuplicateScanner.scanUri(bestShotsScan: true, groupShots: false)`, which analyses every photo but skips grouping, then `findClutter` assigns each photo at most one `ClutterKind` and the page shows them for review. Deletion goes through `FolderDuplicateScanner.deleteFiles`, so Android confirms once for the whole batch.

## Settings next to the results

`features/settings/category_settings.dart` holds the controls for each tool (`SettingsCategory`, `settingsChildrenFor`) so the same widgets are used by the Settings page, by a tool's Find screen (`ScanConfigurationPage.settingsPanel`, collapsible, above the date range) and above results (`CollapsiblePanel` in the scope strip of the similar-photo results, and in `ClutterPage` / `VideoDuplicatesPage` via `settingsPanel`). Every change goes through `_updateSettings`, so it is saved at once and used by the next Find. Result screens also have a search icon (`onFind`) that opens the tool's Find screen. Scan buttons are labelled "Find …". Tested in `test/category_settings_test.dart`.

Browse, Choose an album and results screens have a round back arrow at the top left (`AppBackButton`, shared/app_back_button.dart) and a centred title. On the results screens the back arrow opens the tool's Find screen again, after a "Leave these results?" question when there are groups to lose (`_leaveResults`, then `_backToBrowse`; the same question appears for the search icon, "Change filter" and the system Back, which `PopScope` in `_LibraryPageState.build` intercepts while results are shown; results cannot be reopened, a new scan is needed; Gallery cleanup uses `onFind`) and the search icon at the top right does the same; Share, Create reel and the review screens have a Home icon at the top right instead of a menu. Until PictoIQ can see the photos, Home shows a "Your memories are waiting." banner (`_howItWorks`) in place of the library numbers, and the privacy line sits below it (`popUntil(isFirst)`, or `_showResultsPage = false` for the inline results). `AppMenuActions.goHome` (set by `LibraryPage`) closes all routes above the home screen and hides the results page, so Home always lands on the home screen even when a Find screen was opened from the results. The Android back gesture still goes back one screen.

After a scan, results that were found open directly with no pop-up; only "nothing found" shows a short notice that closes itself after four seconds. Every results screen (best moments, best shot, exact duplicates, clutter, exact duplicate videos) starts with `ScanScopeCard` ("Selected filter"): a short header (folder · range, counts) that expands to the filters that were used, as chips only, and a "Change filter" button that returns to the Find screen with its Change filter panel open (`_backToBrowse(expandFilters: true)`). There are no "Find again" buttons. The home header shows Photos, Videos (when videos are enabled) and Albums totals, with "100% on device" as a line below them.

## Feature flags

`core/config/feature_flags.dart` (`FeatureFlags.current.videoEnabled`, from `--dart-define=PICTOIQ_VIDEO`). `main.dart` reads it to show or hide the Photos | Videos switch, `SettingsPage(showVideoSettings:)` hides the Videos section, and `FolderDuplicateScanner.requestMediaAccess` asks for photo access only when videos are off. Video code is not otherwise touched; it is simply never reached.

## Photo reels

`features/videos/export/reel_configuration_page.dart` is the editor (title, title style, audio, drag to reorder; the whole page scrolls and the photo grid auto-scrolls while dragging). `core/video/video_reel_service.dart` talks to Android over the `com.pictoiq.app/video_reel` channels; `PhotoReelEncoder.kt` draws each frame (1080x1920, 30 fps, H.264), re-encodes the chosen audio to AAC, trims it to the reel length and muxes both into one MP4. Old reels are deleted from the cache before a new one is made.

## People-first Best Moments and Best Shots

Best Moments (the best shot of each event) and Best Shots (the best of several
similar clicks) are the core of the app, so the ranking is built around the
person in the photo and asks nothing extra of the user.

- **Face focus** (`shared/shot_ranking.dart`): when two or more photos in a
  group show a face, the sharpness of the largest face itself is compared
  (`regionSharpness`, measured in the scanner next to face detection). A face
  far softer than the best face is a fault ("the face is out of focus"), so a
  crisp background can no longer carry a blurry person. Without face
  measurements the ranking is exactly as before.
- **Unclear people photos** (`clutter_classifier.dart`): a new clutter kind for
  a clear, prominent face that is soft in absolute terms, or much softer than
  a picture that is otherwise in focus. Tiny distant faces are not judged. The
  thresholds are `ClutterThresholds.unclear*` and need tuning on real photos
  with the "Why is this here?" panel.
- **People only filter** (`ContentFilter.peopleOnly`, `isAboutPeople`): a clear
  face, or a confident people label at least as strong as any object label.
  Scenery alone does not count. Unknown (labeller failed) is kept.
- **Favourites** (`FolderScanPhoto.isFavorite`, from the gallery's own star):
  always kept in a group (`_decisionFor` in `main.dart`), never listed as
  clutter. If a favourite was not the ranked pick, the group needs review and
  is skipped by bulk cleanup.
- **Why is this here?** (`library/photo_explain.dart`): an info button in the
  photo viewer and the clutter preview lists what the face detector and the
  labeller saw (faces, face sharpness, labels and confidences) and the ranking
  notes. Computed on the phone, nothing is sent anywhere.

### One set of photo filters for every tool

Best Moments, Best Shots and Duplicate photos share the same two choices
(`sharedPhotoSettings` in `features/settings/category_settings.dart`):

- **Which photos to include**: People and Scenery chips that can be switched on
  together (`ContentFilter.fromChoice`). Both on is the default
  (`peopleAndScenery`); neither on means every photo. `peopleOnly` and
  `sceneryOnly` use the same on-device labeller; a photo whose main person is
  out of focus is also left out whenever people are wanted.
- **Documents and screenshots of pages**: unchanged.

Best Moments does not use this filter. It always scans with
`peopleAndScenery` (`_momentContentFilter` in `main.dart`), whatever Best shots
and Exact photos are set to, and then lists a moment only when its best photo
passes `isMeaningfulMoment` in `shared/shot_ranking.dart`: a clearly visible,
in-focus person (the largest face fills at least 0.6% of the picture for one
person, 0.4% for two or more) and no quality problems, even for a lone photo.
Scenery is never a best moment. Its Settings panel shows an information panel,
"Always about people" (`momentPeopleNote`, not a chip, so it does not look like a
control), and only the Documents and screenshots choice. The old
"Show moments with no people" switch is gone and the stored `momentShowScenes`
value is no longer used. `momentProblems` gives the plain-language reasons shown
under "Why this photo is not grouped".

### Results page layout

The "N best moments found" section holds a small ⋮ menu (view scanned files, about this
scan) and the scan's facts as plain text (folder and dates, photos scanned, the
settings used). Below it, "Selected filter" is a single collapsible panel
(`ScanScopeCard(showScanDetails: false)`) with a Change filter button. When new results appear, the page
glides down to the first photos (`_scrollToResults`).

### Home storage figure

The Home header shows free space next to Photos, Videos and Albums. It comes
from `DeviceStorage` (`core/device/device_storage.dart`), a method channel
answered by `StatFs` in `MainActivity.kt`. No permission is needed and nothing
leaves the phone.

### Bottom bar and scrolling

The bottom bar depends on the screen. On the results screen it is just Share and
Create reel, in bold forest green (the top bar has Home), and there is no separate
"Share your memories" card on the page. On the home screen it is a light Photos / Videos switch when videos are on, and there is no footer when they are off; Settings and Privacy are in the menu at the top right of
the home header (`_homeMenu`). The Share screen shows the photos in the same large two-column preview grid as Create reel (long-press and drag to reorder, ✕ to remove), and both screens have a draggable scroll bar and a Back to top button (`ScrollWithTopButton`). While a reel is made, Cancel reel sits under
the progress bar, as Cancel scan does under the scan progress. Scans analyse several photos at once
(`defaultScanConcurrency`: 3 to 6 by CPU cores). Long result lists have a draggable scroll bar
and a back-to-top button (`_withScrollAids` in `main.dart`).

### Sensitive pictures

There is no automatic sensitive-picture check in this release (see
"Sensitive-picture check" below). Before anything is shared or put in a reel
(`_screenForSharing` in `main.dart`), `screenForSharing`
(`features/photos/share/share_guard.dart`) removes photos in `PrivatePhotoStore`
(marks already saved on the phone; the enlarged-photo viewer in scan results no
longer has a lock button, so nothing new is marked there) and photos a
`SensitiveContentDetector` scores at or above `sensitiveThreshold`. The current
detector is `NoSensitiveDetector`, so only stored private marks apply. The share
and reel preview screens let the person remove any photo before it is sent. In
scan results the info button is in the enlarged photo (top right) and opens the "Why
is this here?" panel; thumbnails have none.

### Lone photos

A photo with nothing similar to it becomes a group of one when it is clearly
good (`isClearlyGood` in `shared/shot_ranking.dart`: sharp, well exposed, and
for a person open eyes, nothing cut off, in focus, facing the camera). It
passes the same filters as other photos. The minimum sharpness is
`loneShotMinSharpness` (60, untuned). Such groups show a "Single photo" chip and
are listed after groups of two or more when sharing.

### Same moment, people in different places

For Best Moments, photos with a trusted camera time within 3 minutes get slack
in two places (`similarity_grouping.dart`): the clothing-colour check allows
1.6 times the usual difference (people swap places, or a balloon covers their
clothes), and a photo that is alike at least 3 photos of a group stays in it
even when that is under the usual share of a big group (`minLinks` in
`_splitLooseChain`). Both limits are untuned; check them on real photos.

### Owner limits

`lib/core/config/app_limits.dart` holds limits only the owner changes (edit,
then release; they are not in Settings): `shareMaxPhotos` 9, `reelMaxPhotos` 9
and `scanMaxPhotos` 500. A scan looks at the newest 500 photos and the results
say how many older ones were not scanned. The share screen lists every best
shot or moment with a warning when there are more than 9; the top 9 are sent,
and the person can remove photos or drag them into order. The reel editor does
the same. The old "Maximum photos in a reel" setting was removed.

### Sensitive-picture check

There is no automatic detector in the app. `flutter_nsfw_detector` 0.0.5 was
tried and removed: its model returns 5 values per picture but the plugin reads
2 (`PlatformException(SCAN_FAILED, Cannot copy from a TensorFlowLite tensor
(Identity) with shape [1, 5] to a Java object with shape [1, 2]`). Only photos
the person marks private are kept out of shares and reels. The scanner already
accepts a `sensitiveScorer` and the results lock and blur photos scoring at or
above `sensitiveThreshold`, so a working detector that implements
`SensitiveContentDetector` can be put at `_sensitiveDetector` in `main.dart`.

## Screen text conventions

Tool names use sentence case: Best moments, Best shots, Exact photos, Clutter;
videos: Exact videos, Similar videos, Video best moments, Video enhance. The
panel above results is "Selected filter" (button: Change filter); the Find screens have "Change filter". Counts are pluralised (1
moment, 2 moments). Error text shown to people is plain; technical detail
(`runtimeType`, stack) is only printed with `debugPrint`, or shown in the album
picker in debug builds only. The info button is at the top right of the enlarged photo (not on thumbnails).

Home screen (photos): header with the logo; "Your photo library" totals (shown
once photo access is granted, so after the first scan or earlier if already
granted; until then a drawn "Your memories are waiting." welcome banner) and a
small shield-tick line "100% - Your photos stay on your device"; then
"Explore & Create" with a sparkle; four tool cards (Best moments, Exact photos, Best shots, Gallery
cleanup; the label chips are pinned to the bottom of the card so they line up);
and a philosophy card ("The Best moments deserve to be cherished forever.").
The Videos tab keeps its own headline. The fourth tool, "Gallery cleanup", is
the clutter scan; its button reads "Find unwanted photos".
