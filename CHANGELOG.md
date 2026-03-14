# Changelog

All notable changes to SqueezeClip should be tracked here instead of relying on telepathy.

This project follows a simple Keep a Changelog style and semantic-ish version tags.

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
