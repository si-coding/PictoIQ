# PictoIQ: Google Play release checklist

Work through this top to bottom. Items marked (you) need your accounts or devices.

## 1. Create the upload key (you, once)

Run in `mobile/android` (Windows PowerShell shown; use the JDK that ships with Android Studio):

```
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- Keep `upload-keystore.jks` and its passwords somewhere safe (password manager plus an offline backup). Both are git-ignored.
- Copy `key.properties.example` to `key.properties` and fill it in. The Gradle file reads it automatically.
- When you create the app in Play Console, keep **Play App Signing** on (the default). The key above is only your *upload* key, so it can be reset if you lose it.

## 2. Build the bundle

```
cd mobile
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release --obfuscate --split-debug-info=build/symbols
```

Output: `build/app/outputs/bundle/release/app-release.aab`.

Check the build is really signed with your key: the build must not warn about debug signing, and Play Console will reject a debug-signed bundle.

## 3. Check what the bundle declares

- **Target API level.** New apps and updates must target API 36 or higher from 31 August 2026. Look in the merged manifest (`build/app/intermediates/merged_manifests/release/`) for `targetSdkVersion`. If it is lower, upgrade Flutter (`flutter upgrade`) and rebuild.
- **16 KB page size.** Upload the bundle to an internal test track and read Play Console's warnings, or check the `.so` files in Android Studio (Build > Analyze APK). The ML Kit face-detection and image-labelling plugins have native libraries; update them if flagged. Image labelling bundles its model, so the app grows by a few MB: check the size on the Play Console download-size report.
- **Theme.** The look is one build setting, `PICTOIQ_THEME` (`fresh` default, `forest`, `classic`; see `lib/core/config/README.md`). Pick one before building the release bundle, e.g. `flutter build appbundle --release --dart-define=PICTOIQ_THEME=fresh`, and take the store screenshots from that build.
- **Video switch (the first release is photo-only).** Videos are controlled by one flag, `PICTOIQ_VIDEO` (default off, see `lib/core/config/feature_flags.dart`, so a plain `flutter build appbundle --release` is photo-only; `--dart-define=PICTOIQ_VIDEO=true` turns videos on): the Photos | Videos switch, the video tools and the Videos settings disappear, and only photo access is requested. The flag does not edit the manifest, so the READ_MEDIA_VIDEO line in `AndroidManifest.xml` is commented out for this release, or Play will still ask for the video permission declaration. To bring videos back in a later release: remove the comment, build with `--dart-define=PICTOIQ_VIDEO=true` (or change the default), and restore the video wording in the listing and privacy policy (the removed text is in `docs/video-release-text.md`).
- **Permissions.** The merged manifest should contain READ_MEDIA_IMAGES and READ_EXTERNAL_STORAGE (maxSdkVersion 32) and must not contain READ_MEDIA_VIDEO (photo-only release) or MANAGE_EXTERNAL_STORAGE. Check with `aapt2 dump permissions app-release.apk`. ML Kit also adds ACCESS_NETWORK_STATE, WAKE_LOCK and com.google.android.c2dm.permission.RECEIVE; they are normal install-time permissions and match the Data safety answers. Play requires you to fill in the Photo and video permissions declaration (see `play-store-listing.md`). ML Kit adds INTERNET (it sends diagnostics to Google); the app itself works offline.
- **Application ID.** `com.pictoiq.app` cannot change after publishing.

## 4. Test the release build on a real phone (you)

`flutter install --release` (or install the bundle with `bundletool`). Scan a real folder, delete a test photo, open the settings, cancel a scan, open the collapsible settings panel on a Find screen and on the results and change a setting, tap Back and the search icon on a results screen (both open the Find screen), share photos from the preview screen (try more than 9 to see the warning), make a reel and cancel it, use the Home icon on the Share and Create reel screens, open Settings and Privacy from the menu at the top right of Home, and check the opening sequence (Android's launch screen with the logo, then the animated "picto" + "iq" under it) and the pop-up shown after a scan. Release builds can behave differently from debug builds (code shrinking, plugins).

## 5. Play Console setup (you)

1. Developer account ($25 once) and identity verification.
2. Create the app: name, default language, free, app (not game).
3. Privacy policy: host `docs/privacy-policy.md` as a public web page (GitHub Pages, a Google Site or any host), fill in the contact email, and paste the URL.
4. Data safety form: use `docs/play-store-listing.md`, section "Data safety". Double-check it against the current ML Kit disclosure; you are responsible for the answers.
5. Content rating questionnaire, target audience (18+ or "not designed for children" is simplest), ads (none), app category (Photography or Tools).
6. Store listing: copy from `docs/play-store-listing.md`, add the 512x512 icon, a 1024x500 feature graphic and at least 2 phone screenshots.

## 6. Closed test (new personal accounts only)

If your personal developer account was created after 13 November 2023:

1. Create a **closed testing** track and upload the `.aab`.
2. Add at least **12 testers** by email (Google account) or through a Google Group. Each must opt in using the test link and stay opted in for **14 continuous days**.
3. Gather feedback and fix crashes. Update the bundle on the same track if needed (the 14 days do not restart for testers who stay opted in).
4. In the Dashboard, apply for **production access**, answering the questions about the test and the app.
5. After approval, create the production release and submit for review.

Organisation accounts (with a D-U-N-S number) skip the 12-tester rule.

## 7. Keep it true

- The listing says photos stay on the device. Do not add analytics, ads or uploads without updating the privacy policy and the Data safety form first.
- If you re-enable the Library tab (copies photos into the app's private storage) or add anything that stores or sends data, update the policy and the form.

- **Content filter.** Best moments, Best shots and Exact duplicates share the "Change filter" settings (People, Scenery, documents and screenshots; People and scenery is the default). Scan a folder that has screenshots, documents, food, slides and photos where people are blurred, and confirm they are left out or listed under Clutter. Tune the label lists in `lib/shared/photo_content.dart` and the unclear-people limits in `lib/features/photos/clutter/clutter_classifier.dart` on real photos; use the "Why is this here?" button to see why a photo was judged.
- **Footer and menu.** Home's footer is the Photos | Videos switch only when videos are on (no footer when they are off); Settings and Privacy are in the menu at the top right of Home only. The results screen shows only Share and Create reel in the footer. Browse, Choose an album and results screens have a back arrow and a centred title; Share, Create reel and the review screens have a Home icon at the top right. There is no three-dot menu outside Home.
- **Owner limits.** `lib/core/config/app_limits.dart` sets 9 photos to share, 9 in a reel and 500 photos per scan. They are not in Settings. Change them there before a release if you want different numbers, and update the listing text that says 9 and 500.
- **Sensitive photos.** There is no automatic sensitive-picture check in this release (`flutter_nsfw_detector` was removed because its model did not work), and the enlarged-photo viewer in scan results no longer has a lock (private) button. The person reviews photos on the share and reel preview screens and can remove any. The listing and privacy policy say so; do not claim automatic detection or private marks. A working detector can be added later at `_sensitiveDetector` in `lib/main.dart`.
- **Free storage figure.** It uses a small Android call (`StatFs`, no permission). Check it shows on a real phone and that its absence does not break the home screen.
- **Launch screen.** `res/drawable-nodpi/pictoiq_splash.png` (logo only) is the pre-Android 12 launch image; `values-v31` and `values-night-v31` style the Android 12+ system splash (icon only). The animated wordmark is drawn by the app itself (`lib/features/splash/splash_page.dart`, same background colour and logo size), so it looks the same on every Android version. Reinstall after changing the native files, because Android caches launch screens.

## Version, copyright and contact

- **Version and build number.** The `version:` line in `pubspec.yaml` (now `1.0.0+1`: version 1.0.0, build 1). Every Play upload needs a higher build number than the last, even for the same version, so raise the number after the `+` each time. The app shows both in Privacy.
- **Copyright.** See `docs/copyright-and-protection.md`; `LICENSE`, the notice in the Privacy dialog and the Open-source licences page are in the app. Edit `lib/core/config/app_info.dart` to change the owner name or contact email.
- **Contact email.** pictoiq@gmail.com in the privacy policy, the app and the store listing (Play Console, Store settings > Store listing contact details).
- **Installing for tests.** Install the normal APK (`flutter build apk --release --split-per-abi`, then the arm64 one) on a phone. The `.aab` cannot be installed directly; it is only uploaded to Play.

- **Release build and ML Kit.** Release builds shrink Android code (R8). `android/app/proguard-rules.pro` keeps the ML Kit classes. Always test the face check and the object filter in a **release** build: open a photo, tap the info button, and make sure no line says a check "failed". If one does, the line shows the error.
