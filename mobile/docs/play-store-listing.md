# PictoIQ: Play Store listing and form answers (drafts)

Edit freely. Keep every claim true.

## Store listing

**App name:** PictoIQ (max 30 characters)

**Short description (max 80):**
Find the best shot in a folder of look-alikes and clear exact copies.

**Full description (max 4000):**
Too many near-identical photos? PictoIQ groups similar shots from a folder you choose, suggests the best one, and shows how much space you can free.

- Best shot suggestions: compares sharpness, exposure, resolution and faces (eyes open, smiles) and explains the pick.
- Group by what is in the picture: same scene, same people, similar pose. Not by when a file was copied.
- You stay in control: tap any photo to enlarge it, pick the one to keep, skip any group, or review one by one.
- Exact duplicates: finds identical copies and keeps the oldest.
- Choose how strict the matching is, and limit a scan to a date range or custom dates.
- Private by design: your photos are analysed on your phone and never uploaded. No account. No ads.

Photos are deleted only after you confirm, and deleted photos cannot be restored by the app, so check the list before you confirm.

**Category:** Photography (or Tools). **Tags:** photo cleaner, duplicate photos, best shot.

**Graphics needed:** icon 512x512 PNG (`assets/brand/pictoiq-icon.png` is a start; check it is 512x512 with no transparency issues), feature graphic 1024x500, 2 to 8 phone screenshots.

## Data safety form (draft: verify before submitting)

- Does the app collect or share required user data types? **Yes** (because of ML Kit diagnostics). Photos and videos: **not collected** (processed on device only, never leave the device).
- Data collected, as disclosed by Google ML Kit (bundled face detection):
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
- **Photo and video permissions policy:** the app does not request READ_MEDIA_IMAGES or similar. It uses the system folder picker, so no permission declaration is needed.
- **Government/financial/health declarations:** not applicable.
