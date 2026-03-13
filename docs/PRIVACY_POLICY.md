# Privacy Policy Draft for SqueezeClip

Это рабочий черновик privacy policy. Его ещё надо будет разместить по публичному URL перед публикацией в сторы.

## 1. What SqueezeClip does

SqueezeClip is an on-device video compression app. It helps users pick videos from their device, compress them locally, save the output next to the original, and optionally open or share the result.

## 2. Data the app accesses

The app may access:
- videos that the user explicitly selects or views from device storage;
- thumbnails generated from selected videos;
- video metadata such as file name, relative path, duration, resolution, bitrate, frame rate, and file size;
- compressed output files created by the app.

## 3. How data is used

This data is used only to:
- show recent videos and previews;
- compress selected videos on-device;
- save compressed files next to the originals;
- open or share files when the user explicitly requests it.

## 4. Data sharing

SqueezeClip does not upload user videos for cloud compression by design.

The app only shares files when the user explicitly chooses to:
- open a video in another app;
- share a compressed video through Android share sheet;
- send a compressed video to Telegram.

## 5. Accounts, ads, analytics

At the current design level, SqueezeClip does not include:
- user accounts;
- advertising SDKs;
- analytics SDKs;
- in-app purchases.

## 6. Permissions

Depending on Android version, the app may request or declare permissions related to:
- reading videos and media on the device;
- posting notifications for compression progress and completion;
- legacy storage compatibility on older Android versions.

Any final store submission must be checked against the exact shipped manifest.

## 7. Data retention

The app does not maintain a remote user database.

Files remain on the user’s device until the user deletes them. Compressed videos are saved next to the originals using the configured suffix.

## 8. User control

Users control:
- which videos are selected;
- whether files are compressed;
- whether existing outputs are overwritten;
- whether compressed files are shared;
- whether output suffix is changed.

## 9. Contact

Before publication, replace this section with a real support contact and public policy URL.
