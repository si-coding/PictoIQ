# PictoIQ: Play Store listing and form answers (drafts)

Edit freely. Keep every claim true.

## Store listing

**App name:** PictoIQ (max 30 characters)

**Short description (max 80):**
Collect memories, not clutter. Find your best photos and share them.

**Full description (max 4000):**
Collect memories, not clutter. PictoIQ looks through an album you choose, finds your best photos and moments, and helps you share them with family and friends or clear out copies.

- Best moments: groups photos into events and moments, then shows the best 1 to 3 of each, picked for quality and variety (not three near-identical shots). Select photos, preview them, remove any you do not want to send, and share to WhatsApp, Instagram or Facebook. Nothing is deleted. Choose how long a moment lasts, how many photos to show, and whether smiles or candid shots count more.
- Photo reels: turn your selected best photos into a short vertical video reel with a title and your own music, built on your phone and ready to share.
- Choose which photos to include: all photos, or people and scenery only (an on-device model leaves out documents, screens, food and objects).
- Best shot suggestions: compares sharpness, exposure, resolution and faces (eyes open, smiles) and explains the pick. Keep a single best shot, or switch in Settings to keep several photos from each group.
- Group by what is in the picture: same scene, same people, similar pose. Not by when a file was copied.
- You stay in control: tap any photo to enlarge it, pick the one to keep, skip any group, or review one by one.
- Exact duplicates: finds identical copies and keeps the oldest. Works for photos and for videos.
- Clutter: finds screenshots, documents, blank or dark, blurry and tiny photos so you can clear them out in one go.
- Choose how strict the matching is, and limit a scan to a date range or custom dates.
- Private by design: your photos are analysed on your phone and never uploaded. No account. No ads.

In Best shot, Exact duplicates and Clutter, photos and videos are deleted only after you confirm, and deleted photos cannot be restored by the app, so check the list before you confirm.

**Category:** Photography (or Tools). **Tags:** photo cleaner, duplicate photos, best shot.

**Graphics needed:** icon 512x512 PNG (`assets/brand/pictoiq-icon.png` is a start; check it is 512x512 with no transparency issues), feature graphic 1024x500, 2 to 8 phone screenshots.

## Data safety form (draft: verify before submitting)

- Does the app collect or share required user data types? **Yes** (because of ML Kit diagnostics). Photos and videos: **not collected** (processed on device only, never leave the device).
- Data collected, as disclosed by Google ML Kit (bundled face detection and image labelling):
  - **App info and performance: Diagnostics** (performance metrics, API configuration, error codes). Purpose: App functionality / Analytics. Not shared with third parties (Google says ML Kit does not pass this data on).
  - **App info and performance: Other app performance data** and **Device or other IDs** (per-installation identifier). Purpose: Analytics.
- Is all of the data encrypted in transit? **Yes** (HTTPS).
- Can users request data deletion? Not applicable for ML Kit diagnostics; say so as the form asks.
- Always check [Google's ML Kit data disclosure](https://developers.google.com/ml-kit/android-data-disclosure) and the Play Console help for the data types, and answer for what your final build actually contains. You are responsible for the answers.

## Other declarations

- **Ads:** No ads.
- **Target audience:** 18 and over (or "not for children").
- **App access:** all functionality available without login.
- **Content rating:** answer the questionnaire honestly (no violence, no user-generated content shared with others, no location). Expect an "Everyone" rating.
- **Photo and video permissions policy (important).** The app requests READ_MEDIA_IMAGES and READ_MEDIA_VIDEO (and READ_EXTERNAL_STORAGE up to Android 12) to list albums and scan the one you pick; videos are only read to find exact duplicate copies and to let the user play a video before choosing it. Reels use the Android file picker for optional music, so no audio permission is requested. Google limits this permission to apps whose core purpose needs broad photo access, and you complete a declaration form in Play Console before release. Suggested wording: "PictoIQ is a photo-management app. Its core purpose is to scan a user-selected album of the device's photos, group near-duplicate shots, and let the user delete the ones they do not want. This needs read access to the photo library; the system photo picker cannot list albums or scan every photo in one."
  - If Google rejects the declaration, the fallback is to remove the album screen and use only the folder picker (no permission needed). Keep that option in mind before the closed test: the permission must be declared in every track.
  - The Data safety form should still say photos are not collected or shared; they are processed on the device.
- **Government/financial/health declarations:** not applicable.
