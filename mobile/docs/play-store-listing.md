# PictoIQ: Play Store listing and form answers (drafts)

Edit freely. Keep every claim true.

## Store listing

**App name:** PictoIQ (max 30 characters)

**Short description (max 80):**
Collect memories, not clutter. Find your best photos and share them.

**Full description (max 4000):**
Collect memories, not clutter. PictoIQ looks through an album you choose, finds your best photos and moments, and helps you share them with family and friends or clear out copies.

- Best moments: finds the best shots of the same moment or event, picked for quality and variety (not three near-identical shots), every best moment needs a clearly visible, in-focus person, so scenery and photos where nobody can be seen clearly are not shown. Photos where a person is out of focus, or where the focus landed on something else, are not chosen. Choose how long a moment lasts, how many photos to show and whether smiles or candid shots count more.
- Best shots: keeps the best of similar clicks and explains the pick. Faces in focus, open eyes and smiles count most, then sharpness, exposure and resolution.
- One set of filters for Best shots and Exact photos: include people, scenery or both (Best moments always needs a clearly visible person), and decide what happens with documents and screenshots.
- Share and reels: pick up to 9 best shots or moments, preview them, remove any you do not want to send and put them in the order you like. Share to WhatsApp, Instagram or Facebook, or turn them into a short vertical reel with a title and your own music, built on your phone.
- Review before sharing: see every photo on a preview screen first, remove any you do not want to send, and choose the order.
- Favourites are protected: photos you starred in your gallery are never suggested for clean-up.
- "Why is this here?": tap the info button on a photo to see how PictoIQ judged it.
- Exact photos: finds identical photo copies and keeps the oldest.
- Gallery cleanup (clutter): finds screenshots, documents, slides and objects, blank or dark, unclear people photos, blurry and tiny photos so you can clear them out in one go.
- Scans look at up to 500 photos at a time (the newest in your chosen album and dates). The home screen shows how much storage is free.
- Private by design: your photos are analysed on your phone and never uploaded. Nothing is shared until you review it on the preview screen, where you can remove any photo. No account. No ads.

Do not promise that sensitive or illegal pictures are found: the app has no automatic sensitive-picture check; you review what is shared on the preview screen. In Best shots, Exact photos and Gallery cleanup, photos are deleted only after you confirm, and deleted photos cannot be restored by the app, so check the list before you confirm.

**Category:** Photography (or Tools). **Tags:** photo cleaner, duplicate photos, best shot.

**Graphics needed:** icon 512x512 PNG (`assets/brand/pictoiq-icon.png` is a start; check it is 512x512 with no transparency issues), feature graphic 1024x500, 2 to 8 phone screenshots.

## Data safety form (draft: verify before submitting)

- Does the app collect or share required user data types? **Yes** (because of ML Kit diagnostics). Photos: **not collected** (processed on device only, never leave the device).
- Data collected, as disclosed by Google ML Kit (bundled face detection and image labelling):
  - **App info and performance: Diagnostics** (performance metrics, API configuration, error codes). Purpose: App functionality / Analytics. Not shared with third parties (Google says ML Kit does not pass this data on).
  - **App info and performance: Other app performance data** and **Device or other IDs** (per-installation identifier). Purpose: Analytics.
- Checked on 16 Nov 2026 against Google's ML Kit disclosure: for all features ML Kit collects device information (manufacturer, model, OS version, ML accelerators), app information (package name and version), per-installation identifiers (bundled features use only those, not a device ID), performance metrics, API configuration (image format and resolution), event types and error codes, for diagnostics and analytics. Google says ML Kit does not pass this data to third parties. The page does not state retention. Nothing else leaves the phone, so the answers stay: photos not collected; data collected: diagnostics, other app performance data and device or other IDs (per-installation); encrypted in transit; not shared.
- Is all of the data encrypted in transit? **Yes** (HTTPS).
- Can users request data deletion? Not applicable for ML Kit diagnostics; say so as the form asks.
- Always check [Google's ML Kit data disclosure](https://developers.google.com/ml-kit/android-data-disclosure) and the Play Console help for the data types, and answer for what your final build actually contains. You are responsible for the answers.

## Other declarations

- **Ads:** No ads.
- **Target audience:** 18 and over (or "not for children").
- **App access:** all functionality available without login.
- **Content rating:** answer the questionnaire honestly (no violence, no user-generated content shared with others, no location). Expect an "Everyone" rating.
- **Photo and video permissions policy (important).** The first release is photo-only: it requests READ_MEDIA_IMAGES (and READ_EXTERNAL_STORAGE up to Android 12) to list albums and scan the one you pick, and does not request READ_MEDIA_VIDEO, so in the declaration say the app does not access videos. Reels are made from photos and use the Android file picker for optional music, so no audio permission is requested. Google limits this permission to apps whose core purpose needs broad photo access, and you complete a declaration form in Play Console before release. Suggested wording: "PictoIQ is a photo-management app. Its core purpose is to scan a user-selected album of the device's photos, group near-duplicate shots, and let the user delete the ones they do not want. This needs read access to the photo library; the system photo picker cannot list albums or scan every photo in one."
  - If Google rejects the declaration, the fallback is to remove the album screen and use only the folder picker (no permission needed). Keep that option in mind before the closed test: the permission must be declared in every track.
  - The Data safety form should still say photos are not collected or shared; they are processed on the device.
- **Government/financial/health declarations:** not applicable.
