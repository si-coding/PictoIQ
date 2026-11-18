# Copyright and protecting PictoIQ

This is practical guidance, not legal advice. Ask a lawyer (or the Intellectual
Property Office of New Zealand) about anything important, such as a trademark.

## What you already have

- **Copyright is automatic.** The code, text, layout and graphics you create are
  yours the moment they are written; no registration is needed in New Zealand
  or most countries. The notice (`© 2026 Raj Kumar. All rights reserved.`) is
  not required, but it removes any excuse. It is in `LICENSE`, in the app
  (Privacy dialog) and in `lib/core/config/app_info.dart`.
- Parts you did not write keep their own licences (Flutter, ML Kit, the
  and so on). Their licences
  usually require the notice to be shipped with the app: the app's
  "Open-source licences" page (Privacy dialog) does that automatically.
- Check that images, fonts and music inside the app are yours or licensed for
  commercial use.

## What copyright cannot do

Nothing stops someone copying the idea or the look of an app, and nothing makes
an app impossible to copy. Anyone can download the installed app. The aims are
to make copying hard and to be able to act when it happens.

## What to do

1. **Keep the source private.** Keep the GitHub repository private, and do not
   commit the keystore, passwords or API keys.
2. **Make the app harder to read.** Build releases with
   `flutter build appbundle --release --obfuscate --split-debug-info=build/symbols`
   and keep the `build/symbols` folder safe (you need it to read crash reports;
   never publish it). Android's code shrinker (R8) already shortens Java and
   Kotlin names in release builds.
3. **Let Google sign and deliver it.** Use Play App Signing. People get the app
   only from Play, so copies elsewhere are clearly not yours.
4. **Own the name.** Search for "PictoIQ" in the Play Store, Google, the app
   stores and the NZ and other trademark registers before you launch. If it is
   free and you plan to grow, consider registering the name (and logo) as a
   trademark; it is what lets you have a copycat's app taken down fast.
5. **Keep proof.** Keep dated copies of the source, the build and the first
   release (the private repository history does this) so you can show you
   made it first.
6. **If someone copies it.** Report it to Google Play (the "Report" link, or
   the Play copyright and impersonation forms) with your Play listing and
   dates. Play removes copycat apps that clearly copy another developer's work.
7. **Do not put secrets in the app.** Anything inside the app can be extracted.
   PictoIQ has no server, accounts or keys, so there is nothing to steal.

## Version and build number

The version is the `version:` line in `pubspec.yaml`: `1.0.0+1` means version
1.0.0, build 1. Play needs a higher build number (the part after the `+`) for
every upload, even for the same version. The app shows both under Privacy.
