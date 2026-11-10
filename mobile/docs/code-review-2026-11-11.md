# Code review, 11 Nov 2026 (HEAD 186d8a3)

Static review only: nothing here was compiled or run on a device. Priorities: **P1** fix before Play release, **P2** should fix, **P3** nice to have.

## 1. Dependencies

| Package | Used in | Verdict |
|---|---|---|
| cupertino_icons | nowhere | **Removed** from `pubspec.yaml` (unused template dependency) |
| crypto, image, path, path_provider, photo_manager, saf, share_plus, sqflite, video_player, google_mlkit_face_detection | lib/ | in use |
| image_picker | `main.dart`, `core/database/database_service.dart` | in use (Library import) |

Repo hygiene (cannot be done from a zip; run in the repo root):

```
git rm --cached -r .dart_tool
git rm mobile/analyze.txt pubspec.yaml pubspec.lock
```

- `.dart_tool/` is tracked although `.gitignore` in `mobile/` ignores it; the **root** `.gitignore` is the .NET one and does not. Add `.dart_tool/` there.
- `mobile/analyze.txt` is a UTF-16 analyzer dump from a broken state (stale, misleading).
- Root `pubspec.yaml`/`pubspec.lock` are an older copy of `mobile/pubspec.yaml` (no share_plus, no video_player) at the .NET project root. Nothing builds from them.
- `android/gradle.properties` carries `android.newDsl=false` and `android.builtInKotlin=false`. They work with AGP 9.1 but are temporary opt-outs; expect to migrate before AGP 10 (P3).

## 2. Dead code

Removed from `lib/main.dart` (about 290 lines, no references left after the new design): `_scanCard`, `_dateChips`, `_dateChip`, `_mainScanLabel`, `_mainScanAction`. Nothing else in `lib/` is unreferenced; the new `_homeFeatureSelector`, `ScanConfigurationPage`, and the helpers they use are untouched.

Still large: `main.dart` is about 5,000 lines in one `State` class. Splitting results rendering (`_resultsHeader`, `_folderDuplicateCard`, review mode) into `features/photos/...` widgets would make the next feature safer (P3).

## 3. Reel feature review

**Works as designed (read through):** H.264 1080x1920 at 30 fps through an EGL input surface, letterboxed photos with EXIF rotation, crossfades, optional title, audio decoded to PCM, trimmed to the reel length, re-encoded to AAC and muxed; progress, cancel, and cleanup of the intermediate files in `finally`. Argument validation exists on both the Dart and native side. No microphone or audio permission is needed because the file comes from `ACTION_OPEN_DOCUMENT`.

**Fixed in this update**
- (P2) `MainActivity.onDestroy` did not cancel an encode in progress; the worker kept encoding and later answered a dead channel. It now sets the cancel flag first.
- (P2) Finished reels (`pictoiq_best_moments_*.mp4`, up to tens of MB each) stayed in the cache forever. `VideoReelService.createReel` now deletes earlier ones first (best effort).

**Open findings**
- (P1, product) Default reel is 15 photos x 3 s = 45 s. WhatsApp Status is limited to about 30 s and its size cap is small; at 12 Mbit/s a 45 s reel is about 65 MB. Suggest default 10 photos, and `BIT_RATE` 6 to 8 Mbit/s (a still-photo slideshow does not need 12). Test the result in WhatsApp and Instagram.
- (P2) Speed: every frame is redrawn on a software `Canvas` and uploaded as a full 1080x1920 texture, including the frames where nothing changes (only the first `fadeFrames` of each photo change). Upload and draw only when the picture changes and re-draw the same texture otherwise; this should cut encoding time a lot on mid-range phones. Measure first with a 15-photo reel on a mid-range device.
- (P2) `onActivityResult` copies the chosen audio file into the cache on the **main thread** with no size limit. A large file can freeze the UI (ANR risk) and fill storage. Copy on the executor and reject files over about 50 MB.
- (P2) Native audio errors ("Choose a mono or stereo audio file", "This audio format cannot be converted") are swallowed: the page always shows "Could not create the reel. Please try again." Catch `PlatformException` in `_createReel` and show `error.message` for `reel_creation_failed`.
- (P2) After a failed or finished reel the chosen audio is discarded, so the next attempt needs the file picked again. Keep it after a failure.
- (P3) Audio shorter than the reel simply ends (silence for the rest). Loop it, or tell the user.
- (P3) HE-AAC or other files whose decoded sample rate differs from the declared one are rejected by design.
- (P3) Dragging swaps two photos rather than moving one into a position; inserting is what most people expect.
- (P3) Test on at least three devices (Samsung, Pixel, a low-end phone): `createEncoderByType`, `EGL_RECORDABLE_ANDROID` and the AAC encoder behave differently across vendors. There are no native tests; `video_reel_service_test.dart` only mocks the channel.

**Reel screen scrolling (requested):** the photo grid was a fixed 370 px window with its own scroll inside the page. It is now part of the page scroll (`SliverGrid`), the page has a visible scrollbar, and dragging a photo near the top or bottom edge scrolls the page automatically so a photo can be moved past what is on screen. The widget test was updated to scroll to the 15th photo.

## 4. Google Play readiness

Done: package id `com.pictoiq.app`, upload-key signing via `key.properties`, privacy policy draft, Data safety draft, permission declaration wording, closed-test checklist.

**Fixed in this update**
- `requestLegacyExternalStorage` removed from the manifest (ignored when targeting API 30+, and Play reviewers flag it).
- Privacy policy and store listing now describe videos, Clutter, reels, music and the temporary cache (they described only photos and exact duplicates, which would make the Data safety and the permission declaration inaccurate).

**Before submitting**
- (P1) Fill `[DATE]` and `[CONTACT EMAIL]` in the privacy policy and host it at a public URL.
- (P1) Complete the **Photo and video permissions declaration**. READ_MEDIA_VIDEO is justified only by exact duplicate videos plus playback; if videos are not part of the first release, build with `--dart-define=PICTOIQ_VIDEO=false` **and** delete the READ_MEDIA_VIDEO line, as the checklist explains.
- (P1) Build a signed release bundle and test it, not only debug: R8 shrinking is on by default for Flutter release builds and ML Kit, `photo_manager` and the reel channels need to be exercised (scan, delete, reel with audio, cancel).
- (P1) Check targetSdk (36 required for new apps from 31 Aug 2026) in the merged manifest, and the 16 KB page size warning for the ML Kit native libraries.
- (P2) Screenshots: the new home screen, a results screen and the reel editor; a 1024x500 feature graphic.
- (P2) `android:taskAffinity=""` and `singleTop` are fine; confirm back-button behaviour on the reel editor while a reel is being made (the page blocks back via `PopScope`, which is intended).
- (P2) Deleting uses the system delete request, so Android confirms once; keep the wording "cannot be restored by the app" in the listing.
- (P3) Version `1.0.0+1`: bump `+N` for every upload.
