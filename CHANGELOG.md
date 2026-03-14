# Changelog

All notable changes to SqueezeClip should be tracked here instead of relying on telepathy.

This project follows a simple Keep a Changelog style and semantic-ish version tags.

## [0.1.7] - 2026-03-14

F-Droid quality hardening release.

### Changed
- removed INTERNET permission inherited from video_player plugin (app is fully offline)
- disabled PNG cruncher for reproducible resource processing
- disabled AGP VCS info embedding for reproducible builds

## [0.1.6] - 2026-03-14

F-Droid APK hygiene release.

### Changed
- disabled Gradle dependency metadata embedding in APK/AAB outputs so F-Droid's APK scanner stops flagging an extra signing block

## [0.1.5] - 2026-03-14

F-Droid submodule sanity release.

### Changed
- replaced the fake Flutter bootstrap metadata hack with a real submodule prepare step that fetches the pinned Flutter tag and restores a local `stable` branch for detached builders
- removed duplicate F-Droid description text so maintainers pull fastlane metadata from the repo instead of stale copy-paste sludge
- aligned starter metadata, docs, and CI with the new submodule prepare flow

## [0.1.4] - 2026-03-14

F-Droid execution-mode fix release.

### Changed
- switched bootstrap invocation to `bash ./scripts/bootstrap_flutter.sh` so detached builders do not depend on executable file mode
- carried the same launcher fix into F-Droid metadata, CI, and docs

## [0.1.3] - 2026-03-14

F-Droid reproducibility cleanup release.

### Changed
- added `scripts/bootstrap_flutter.sh` so vendored Flutter reports the pinned version in detached submodule builds
- aligned F-Droid metadata and GitHub Actions release flow with the bootstrap step
- excluded vendored Flutter sources from local analyzer noise

## [0.1.2] - 2026-03-14

F-Droid build hygiene release.

### Changed
- bundled Flutter as a pinned git submodule under `third_party/flutter`
- aligned local build and CI workflows around the bundled Flutter toolchain
- tightened F-Droid metadata for direct `fdroiddata` submission
- started publishing release digests next to APK and AAB artifacts

## [0.1.1] - 2026-03-14

Package identity cleanup release.

### Changed
- switched Android application id to `io.github.pioh.squeezeclip`
- removed remaining `com.tema` namespace leftovers from code and docs
- aligned F-Droid starter metadata and store docs with the stable package id

## [0.1.0] - 2026-03-13

Initial public release candidate.

### Added
- recent video feed for Camera, Telegram, and Downloads
- video-only picker
- local on-device compression using Android Media3
- output saved next to original with configurable suffix
- progress, speed, and ETA for current file and queue
- reorderable queue with cancel and stop-after-current
- before/after metrics including size, bitrate, fps, and savings
- direct open, compare, and share flows
- direct Telegram sharing
- privacy dialog and publication assets for app stores

### Release notes
- package id: `io.github.pioh.squeezeclip`
- first public tag intended for store and F-Droid onboarding
