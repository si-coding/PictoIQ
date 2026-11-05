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
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`.

Check the build is really signed with your key: the build must not warn about debug signing, and Play Console will reject a debug-signed bundle.

## 3. Check what the bundle declares

- **Target API level.** New apps and updates must target API 36 or higher from 31 August 2026. Look in the merged manifest (`build/app/intermediates/merged_manifests/release/`) for `targetSdkVersion`. If it is lower, upgrade Flutter (`flutter upgrade`) and rebuild.
- **16 KB page size.** Upload the bundle to an internal test track and read Play Console's warnings, or check the `.so` files in Android Studio (Build > Analyze APK). The ML Kit face-detection plugin has native libraries; update it if it is flagged.
- **Permissions.** The merged manifest should contain READ_MEDIA_IMAGES, READ_MEDIA_VIDEO and READ_EXTERNAL_STORAGE (maxSdkVersion 32), and must not contain MANAGE_EXTERNAL_STORAGE. Play requires you to fill in the Photo and video permissions declaration (see `play-store-listing.md`). ML Kit adds INTERNET (it sends diagnostics to Google); the app itself works offline.
- **Application ID.** `com.pictoiq.app` cannot change after publishing.

## 4. Test the release build on a real phone (you)

`flutter install --release` (or install the bundle with `bundletool`). Scan a real folder, delete a test photo, open the settings, cancel a scan. Release builds can behave differently from debug builds (code shrinking, plugins).

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
