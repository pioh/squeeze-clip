# Google Play Checklist

Используй это перед реальным релизом в Google Play, а не когда консоль уже орёт красным.

## Console setup

- `[ ]` создать app в Play Console
- `[ ]` подтвердить package id `com.tema.videocompress`
- `[ ]` включить Play App Signing
- `[ ]` загрузить release `AAB`, не debug apk

## Store listing

- `[ ]` app name / title
- `[ ]` short description
- `[ ]` full description
- `[ ]` app icon `512x512`
- `[ ]` feature graphic
- `[ ]` phone screenshots
- `[ ]` support email
- `[ ]` privacy policy URL

## App content

- `[ ]` Data safety form
- `[ ]` content rating questionnaire
- `[ ]` ads declaration
- `[ ]` target audience declaration
- `[ ]` news / government / health / finance declarations if they ever become relevant

## Release quality

- `[ ]` release signing config
- `[ ]` versionCode bump strategy
- `[ ]` target API still compliant at release time
- `[ ]` changelog / release notes
- `[ ]` smoke test on physical device
- `[ ]` verify runtime permission flow

## SqueezeClip-specific checks

- `[x]` `INTERNET` does not ship in release manifest
- `[x]` `ACCESS_NETWORK_STATE` does not ship in release manifest
- `[x]` `WAKE_LOCK` does not ship in release manifest
- `[ ]` privacy policy wording matches actual shipped manifest
- `[ ]` screenshots show Camera feed, compare sheet, queue, and share flow
