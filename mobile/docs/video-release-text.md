# Video wording for a later release

The first Play release is photo-only, so these lines were removed from the store listing, the Data safety draft, the permission declaration and the privacy policy. Put them back when a release includes videos (build with `PICTOIQ_VIDEO=true`, or change the default, and restore the READ_MEDIA_VIDEO line in `AndroidManifest.xml`).

## privacy-policy.md

- Intro: "remove exact duplicate photos and videos" (the photo-only text says "exact duplicate photos").
- In "What the app does with your photos", add: "Videos are read only to find exact duplicate copies (their length, picture size and a fingerprint of the file). PictoIQ does not watch, analyse or upload your videos. You can play a video from the album screen so you can see it before choosing."
- Deletion bullet: "It deletes a photo or video **only** after you confirm in the app, and Android may ask you to confirm again. Deleted photos are removed from your phone's photo library or from the folder you chose."

## play-store-listing.md

- Exact duplicates: "finds identical copies and keeps the oldest. Works for photos and for videos."
- "In Best shot, Exact duplicates and Clutter, photos and videos are deleted only after you confirm, ..."
- Data safety: "Photos and videos: **not collected** (processed on device only, never leave the device)."
- Permission declaration: "The app requests READ_MEDIA_IMAGES and READ_MEDIA_VIDEO (and READ_EXTERNAL_STORAGE up to Android 12) to list albums and scan the one you pick; videos are only read to find exact duplicate copies and to let the user play a video before choosing it."
