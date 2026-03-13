# F-Droid Release Prep

This project is being prepared for eventual F-Droid publication under the user-facing name **SqueezeClip**.

## Current package identity

- App name: `SqueezeClip`
- Android application id: `com.tema.videocompress`

The application id is still generic enough to keep for now. Renaming it later is possible, but it would reset app identity for installed users, so do not change it casually.

## What is already prepared

- launcher label switched away from Telegram-specific branding
- README rewritten to describe the real app instead of Flutter boilerplate trash
- fastlane metadata skeleton added
- roadmap/handoff document maintained in `IMPLEMENTATION_PLAN.md`
- non-default launcher/adaptive icon added
- starter screenshots and feature graphic generated
- release APK and release AAB both build locally
- release manifest cleaned of `ACCESS_NETWORK_STATE` and `WAKE_LOCK`
- release signing infrastructure prepared via `android/key.properties.example`

## What should be completed before a real F-Droid submission

1. Finish Phase 2 and Phase 4 in `IMPLEMENTATION_PLAN.md`
2. Add proper release screenshots
3. Keep the current custom launcher/adaptive icon and only replace it if branding changes
4. Decide whether to keep `com.tema.videocompress` or migrate to a final stable id
5. Keep the existing MIT license in sync with public distribution
6. Host privacy policy publicly and lock support contact
7. Verify reproducibility constraints

## Local release sanity checklist

```bash
flutter pub get
flutter analyze
flutter build apk --debug
```

Optional device smoke test:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -W -n com.tema.videocompress/.MainActivity
```

## Metadata location

F-Droid/App metadata files live in:

`fastlane/metadata/android/en-US/`

Store checklists and privacy draft:

- `docs/STORE_PUBLISHING_PLAYBOOK.md`
- `docs/PLAY_CONSOLE_CHECKLIST.md`
- `docs/APPGALLERY_CHECKLIST.md`
- `docs/FDROID_SUBMISSION_CHECKLIST.md`
- `docs/PRIVACY_POLICY.md`

## Recommended upstream update hygiene

If you want F-Droid maintainers to have the best chance of enabling painless update checks later, stop shipping chaos:

- keep `pubspec.yaml` version aligned with actual releases
- use annotated git tags like `v0.1.0`, `v0.1.1`, `v0.2.0`
- update `CHANGELOG.md` on every release
- keep release builds reproducible from tagged source
- avoid rewriting history on released tags unless you enjoy self-inflicted pain

There is also a ready-to-copy starter metadata file for maintainers here:

- `docs/fdroid/com.tema.videocompress.yml`
