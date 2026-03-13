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
- source switcher for Camera / Telegram / Downloads
- video-only picker
- quality presets plus custom target height
- reorderable compression queue
- live progress and speed
- ETA for current file and queue
- open original / open compressed
- A/B compare inside the app
- size, fps, bitrate and savings before/after
- mark compressed results and share them
- direct share to Telegram plus normal Android share sheet
- configurable output suffix and overwrite behavior
- privacy dialog inside the app

## Build

```bash
flutter pub get
flutter analyze
flutter build apk --debug
```

Release artifacts:

```bash
flutter build apk --release
flutter build appbundle --release
```

For proper store signing, copy `android/key.properties.example` to `android/key.properties` and point it at a real upload keystore instead of acting surprised later.

Install on a connected device:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -W -n com.tema.videocompress/.MainActivity
```

## Publishing notes

F-Droid prep files live here:

- `fastlane/metadata/android/en-US/`
- `docs/FDROID_RELEASE.md`
- `docs/STORE_PUBLISHING_PLAYBOOK.md`
- `docs/PRIVACY_POLICY.md`
- `IMPLEMENTATION_PLAN.md`

Before publishing, use the per-store checklists and stop pretending screenshots, signing, license, and privacy URLs will materialize by telepathy.
