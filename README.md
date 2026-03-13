# SqueezeClip

SqueezeClip is a Flutter + Android Media3 app for shrinking phone videos without turning the workflow into a circus.

Core idea:
- show recent videos from `DCIM/Camera`;
- compress selected clips locally on-device;
- save `*_tg.mp4` next to the original;
- open or share the result immediately;
- keep the UI fast and obvious instead of path-driven garbage.

## Current feature set

- recent camera feed with previews
- video-only picker
- quality presets
- live progress and speed
- open original / open compressed
- size before/after
- mark compressed results and share them
- direct share to Telegram plus normal Android share sheet

## Build

```bash
flutter pub get
flutter analyze
flutter build apk --debug
```

Install on a connected device:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -W -n com.tema.videocompress/.MainActivity
```

## Publishing notes

F-Droid prep files live here:

- `fastlane/metadata/android/en-US/`
- `docs/FDROID_RELEASE.md`
- `IMPLEMENTATION_PLAN.md`

Before publishing, finish the remaining roadmap items in `IMPLEMENTATION_PLAN.md`, especially queue handling, clearer per-file statuses, and background notifications.
