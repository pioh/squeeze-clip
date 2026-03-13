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

## What should be completed before a real F-Droid submission

1. Finish Phase 2 and Phase 4 in `IMPLEMENTATION_PLAN.md`
2. Add proper release screenshots
3. Add a real launcher/adaptive icon instead of the default Flutter one
4. Decide whether to keep `com.tema.videocompress` or migrate to a final stable id
5. Add a license file if publication target requires explicit packaging clarity
6. Build a release APK / App Bundle and verify reproducibility constraints

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
