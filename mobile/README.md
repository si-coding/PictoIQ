# PictoIQ mobile

Local-first Android photo review and best-shot recommendations.

## Folder scan performance

- Visual-analysis SAF streams use `BytesBuilder` instead of growable integer lists. Exact duplicate SHA-256 is streamed without buffering the entire file.
- Best-shot analysis does not compute SHA-256. Similar groups use a member URI as their local group ID; exact groups retain the content hash.
- Decode, orientation normalization, resizing, visual hashing, technical scoring, and JPEG encoding run in `Isolate.run`, one image at a time. Native face detection remains on the plugin's platform channel.
- JPEG decoding uses subsampling when appropriate. Analysis and ML Kit input images are capped at 1024 pixels on the longest edge, preserving aspect ratio and never upscaling small images.
- Previews have a maximum edge of 360 pixels for best shots and 480 for exact duplicates. Face detection receives raw pixels (at most 1024 px on the longest edge) directly, with no temporary file.
- Visual analysis rejects encoded files over 64 MiB, JPEG sources over 67,108,864 pixels, and other formats over 25,165,824 pixels before decoding pixel data. Other formats still require full-frame decoding inside the worker before resizing. These safeguards do not guarantee a particular peak-memory footprint.
- Failed or unsupported best-shot files increment the existing skipped count and cannot become deletion candidates. Exact duplicates can still be detected by streaming SHA-256 if their previews exceed these limits.

Downscaling can change quality signals and hide small faces. Recommendations remain advisory; evaluate grouping and ranking against representative burst photos before release.

### Focused validation

```powershell
flutter analyze lib\folder_duplicate_scanner.dart lib\scan_image_processing.dart test\scan_image_processing_test.dart test\folder_scanner_performance_test.dart
flutter test test\scan_image_processing_test.dart test\folder_scanner_performance_test.dart
```

Tests cover typed byte collection, encoded memory limits, image dimensions, EXIF preservation/orientation, exact hashes, best-shot grouping without content hashes, skipped inputs, temporary-file cleanup, and bounded face-detector input. The native detector is mocked; its real latency and accuracy are not measured here.

For device profiling, run `flutter run --profile` on a physical Android device and compare the same large folder before/after with DevTools CPU, memory, and frame timelines. Record peak memory, scan duration, skipped count, and frames over the device frame budget. Synthetic timings are diagnostics, not device performance guarantees.

## Similar-photo grouping

- Similar photos are grouped by a 64-bit difference hash plus capture time (EXIF time when present, file time otherwise; the two are never compared). They are kept separate from exact duplicates and are never described as guaranteed duplicates.
- Photos taken within 8 seconds of each other are also linked when their colours match (or their hashes differ by up to 14 bits), because small camera movement changes the structure hash a lot while barely changing colours. Such groups are Medium at best, and Low when the colours differ noticeably. If a photo does not belong (for example a different person in the same spot), open Compare and tap "Not the same scene"; nothing is deleted.
- Capture time comes from EXIF, else the file's modified time. If the file name carries a date (`IMG-20221109-WA0007`, `IMG_20221109_123456`, `PXL_...`) and the modified time is more than two days away from it (bulk copy or download), the name wins. Date-only names (WhatsApp) mean photos from different days never group, and same-day ones need the strict hash match.
- **Grouping looks at the picture, not the clock.** Files get copied between folders and devices, so file dates say little about a scene. The scan now compares every photo with every other by (1) who is in it, as far as we can tell without face recognition (face counts; a count difference of 2 or more never groups), (2) where it is: a structure hash plus a 6x6 colour layout that captures the background, and only then (3) time, which is used for nothing but event headings. A pair links when the hash is close (10 bits) and the colour layout matches (10%), or when the layout matches very closely (7%) despite shifted framing (hash up to 20). High needs hash <= 4 and layout <= 4%; Low when any pair in the group is far apart. All numbers are untuned: run `tool/evaluate_similarity.dart` on a labelled folder (its last section sweeps them). The old time-window rules are still in the code for the evaluation tool but the scan no longer uses them, and the "same session" setting was removed.
- **No chains.** Pairwise links are kept, and a group is trimmed so each photo is directly alike at least half of the photos already in it. A beach day of single shots, couples and family poses therefore falls apart into small groups of the same people and pose instead of one 30-photo group. The colour-only match also needs the same number of faces.
- **Custom date range.** Besides Today / Last 7 days / Last 30 days, "Custom range" asks for a from and to date (both days included). The scan lists the folder first, so progress reads "N of M photos", then analyses three photos at a time. A close button on each similar-photo card skips that group without deleting anything (Undo is offered).
- **Same people, same clothes.** The clothing colours under each of the four largest faces are compared: everyone in the photo with fewer people must match someone in the other photo (an extra stranger is allowed). Balanced allows a colour distance of 0.18, Strict 0.12, Loose 0.32; these are untuned. Tapping a photo opens the original decoded to about 2048 px (the small scan preview shows first). The scan shows two progress bars: finding photos, then analysing them 0-100 %.
- **Settings (all apply to the next scan).** Match level Strict / Balanced / Loose scales the limits above. "Also use time taken": Ignore, Hint (default: see above), Moment (about 30 s, with the quick-shot colour rule) or Session (10 min, never rated High); time modes use camera time, else a date in the file name, else the file date, so copied files may group less. "Keep different numbers of people apart" turns the face-count rule on or off. "Show event headings" hides or shows the Event > Scene headings.
- **Moved people, zoom, and the time hint.** Measured on a screenshot of 9 thumbnails, the structure hash changes a lot when people turn or move (28-33 of 64 bits) while the colours barely change. So a pair also links when its position-free colour profile (distance <= 0.03 / 0.05 / 0.08) and colour layout (<= 0.07 / 0.10 / 0.13) match, with a hash up to 32 (Strict / Balanced / Loose). With "Also use time taken: Hint" (default for new installs), two photos whose camera time is reliable (EXIF, or a time in the file name such as `20261004_133012.jpg`; never the file's modified date) and within 10 s also link when their colour profiles are within 0.15 / 0.25 / 0.30. A time written in a file name now beats the modified time. These numbers come from about nine thumbnails: tune them with `tool/evaluate_similarity.dart` on a labelled folder.
- **Time hint is stricter.** A reliable-time pair (within 10 s) must also have colour layouts within 0.10 / 0.16 / 0.22 (Strict / Balanced / Loose), so two different places saved in the same second (an Instagram or WhatsApp export stamps its own save time in the file name) do not link. Sharpness is now measured on the sharpest quarter of a 6x6 tile grid instead of the whole frame, so a crisp subject with a blurred portrait-mode background is not ranked as soft; a photo that is soft everywhere still is.
- **Results screen.** One compact header: folder name, New scan, a ⋮ menu (scanned files, about this scan) and a big "X can be freed" figure, the size of every photo that would go if each group kept only its top pick (or your pick), with a one-line status of how much is ready for bulk cleanup. Filter chips scroll in one row. Each group is a photo-first card: large side-by-side thumbnails, the photo to keep outlined in green with a "Best"/"Your pick" badge, short badges on the others ("Softer", "Eyes closed", "Blurry"...), a round button on each photo to keep that one instead (one keeper per group), tap a picture to enlarge it, a one-line title ("3 photos · frees 76 KB"), a neutral status chip (Same shot / Similar / Check), and a short action ("Keep best · free 76 KB"; outlined when the group needs a look). The match notes, ranking headline, file names and per-photo reasons are behind the ⓘ button. Within each event, safer groups come first. Thumbs up/down remain in the Library list only.
- **Progress and review mode.** The header keeps a running "Freed so far: X MB (N photos)" for the current scan, and shows "X MB freed" with an all-done message when nothing is left. "Review one by one (N)" opens a full-screen review of the groups in the current filter, safest first: big photos, tap the round button to choose the keeper, then "Keep this · free X" or "Skip" (Back undoes the last step). Nothing is deleted while reviewing; at the end one confirmation lists the photos that will go for all the groups you kept. Closing early deletes nothing and keeps your choices on the group cards.
- **Documents.** Images that are almost all white or grey (pages, receipts, forms) are detected by a simple colour test and, if no face is found in them, treated as documents. Default "Leave out": they are not grouped or offered for deletion, and the scan message says how many were left out. "Compare strictly": they group only with a near-identical copy (hash within 4 bits and a 24x24 brightness grid within 2%), are never rated High, and never link to photos. Untuned; a pale photo (snow, white wall) could be mistaken for a document, which only means it is left alone.
- **Different people.** The scan cannot recognise faces. As a rough stand-in, "Keep different people apart" compares the colours below the largest face (clothing) between two photos and refuses to group them when they differ by more than 18% / 25% / 40% (Strict / Balanced / Loose), on top of the face-count rule. It only works when face detection is on and a face was found in both photos; two people in similar clothes still group.
- **Scene and event.** A scene is a group of look-alike photos; ranking and "delete lower-ranked" only work inside a scene, and an unmatched photo is always kept. Event headings (Event > Scene in the results) use only times that describe the picture: camera time (EXIF) or a date in the file name. A file's modified time only says when it was copied, so those photos get no heading. Events never recommend deletion. Not done: events by GPS, and recognising the same people across scenes (needs opt-in on-device face recognition).
- Each group shows a High, Medium or Low match label with the facts behind it (hash spread, time span, time source). A chain of look-alikes whose ends differ a lot is marked Low.
- Default selection is conservative: every thumbs-up photo is kept; otherwise the top-ranked photo is suggested. Bulk deletion only touches groups that are High match with a clear top photo, or groups where you chose.
- Thresholds are starting points. Measure them on your own photos with `dart run tool/evaluate_similarity.dart <folder> <labels.csv>`; `test/similarity_evaluation_test.dart` is a synthetic regression set, not a measurement.

## Best-shot ranking and review

- Within each similar-photo group, photos are ranked on sharpness (Laplacian variance at a fixed 512 px size, compared with the group's sharpest photo), exposure (brightness plus blown highlights and crushed shadows) and resolution. Scores are relative to the group, not an absolute photo rating.
- When every photo in a group was analysed and a face exists, eye-open and smile signals from ML Kit face detection add up to 30% of the score. They can be switched off in Settings (faster scans, nothing else changes).
- Compare opens every photo in a group side by side with its score, strengths, concerns and measurements. "Keep this one" records your pick; "Reset my choices" returns the group to PictoIQ's suggestion.
- "I choose which photos to keep" in Settings stops PictoIQ from selecting anything in similar-photo groups until you give a thumbs-up.
- A photo is ruled out as a top pick when someone's eyes look closed, a face is cut off at the edge, someone is looking well away from the camera, or it is badly blurred or washed out. Ruled-out photos lose points and are never chosen over a clean photo. Up to three close, clean photos are shown as the Top pick and Finalists, and Compare can show finalists only.
- "Group photos from the same session" in Settings also groups the same scene taken up to 10 minutes apart with different poses. These groups are labelled "Same session", are never rated High, and are never part of a bulk clean-up. The distance limits are untuned; check them with `tool/evaluate_similarity.dart`.
- Face signals have not been benchmarked against alternative models. To do that, collect 50+ burst sets with blinks, compare the ranking with and without face signals (Settings switch) against your own pick, and time scans on a mid-range device.

## Home screen

- Two tabs: **Scan** (folder, scan buttons, results) and **Library** (photos you imported into PictoIQ and the duplicates among them). Library counters say "saved photos" so they are not confused with folder-scan results.
- "Find the best shots" is the primary action. After a scan the folder form collapses to one line ("New scan") so results sit near the top. If both scan types have results, a switch shows one at a time.
- Similar-photo results can be filtered: All, Ready to clean, Needs review.
- A running scan can be cancelled; cancelling changes nothing. Deleting photos updates the results on screen without scanning the folder again.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
