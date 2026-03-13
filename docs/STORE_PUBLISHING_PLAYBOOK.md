# Store Publishing Playbook

Этот файл не для красоты. Он нужен, чтобы выпуск `SqueezeClip` в F-Droid, Google Play и Huawei AppGallery не превратился в унылый цирк с повторным сбором требований.

Репозиторий:
- `git@github.com:pioh/squeeze-clip.git`

Текущая identity:
- app name: `SqueezeClip`
- application id: `com.tema.videocompress`
- minSdk: `24`
- targetSdk: `36`
- versionName: `1.0.0`
- versionCode: `1`

Проверено локально по apk:
- targetSdkVersion: `36`
- permissions in shipped debug apk:
  - `POST_NOTIFICATIONS`
  - `READ_MEDIA_VIDEO`
  - `READ_MEDIA_IMAGES`
  - `READ_EXTERNAL_STORAGE` up to API 32
  - `WRITE_EXTERNAL_STORAGE` up to API 29
  - `INTERNET`
  - `ACCESS_NETWORK_STATE`
  - `WAKE_LOCK`

## 1. Общие best practices перед любым стором

Сделать обязательно:
- release signing вместо debug signing;
- нормальная лицензия в корне репы;
- публичная privacy policy по URL, а не только файлик в репе;
- реальные release screenshots;
- нормальная launcher/adaptive icon вместо дефолтной flutter-плашки;
- release notes / changelog;
- smoke test на чистом устройстве;
- удалить всё, что случайно тянет лишние permissions или SDK, если они не нужны.

Сделать желательно:
- отдельный release checklist;
- выделенный package id, если захочешь когда-нибудь ребренд, иначе этот оставлять и не дёргаться;
- versioning strategy до первого стора, чтобы потом не городить хаос.

## 2. Google Play

Официальные требования, которые надо учитывать:
- store listing требует app details, contact details, privacy policy и graphic assets;
- app content требует заполнить Data safety, ads, content rating, target audience и прочие декларации;
- для новых app bundles в Google Play используется Play App Signing;
- целевой API должен соответствовать актуальным требованиям Google Play.

Официальные ссылки:
- Store listing: https://support.google.com/googleplay/android-developer/answer/9859152
- App content / declarations: https://support.google.com/googleplay/android-developer/answer/9859455
- Data safety: https://support.google.com/googleplay/android-developer/answer/10787469
- Content rating: https://support.google.com/googleplay/android-developer/answer/188189
- Target API policy: https://support.google.com/googleplay/android-developer/answer/11926878
- Play App Signing: https://support.google.com/googleplay/android-developer/answer/9842756

Что это значит для `SqueezeClip`:
- нужен полноценный store listing:
  - title
  - short description
  - full description
  - app icon
  - phone screenshots
  - feature graphic
- нужен privacy policy URL;
- нужно заполнить Data safety по фактическому manifest и runtime behavior;
- нужно заполнить content rating questionnaire;
- если приложение не показывает ads, это отдельно задекларировать;
- надо выпускать AAB для Play, а не жить вечно на debug apk.

Практический gap на сейчас:
- `[x]` название и базовые тексты уже есть;
- `[x]` есть feature graphic;
- `[x]` есть стартовые release screenshots;
- `[ ]` нет hosted privacy policy URL;
- `[x]` release signing infrastructure через `android/key.properties` уже добавлена;
- `[x]` release AAB pipeline уже проверен локально;
- `[x]` `ACCESS_NETWORK_STATE` и `WAKE_LOCK` вычищены из релизного manifest;
- `[x]` `INTERNET` не попадает в релизный manifest и остаётся только development-story.

## 3. F-Droid

Официальные ориентиры:
- inclusion и metadata: https://f-droid.org/docs/Inclusion_Policy/
- metadata tutorial: https://f-droid.org/docs/Build_Metadata_Reference/
- submitting apps: https://f-droid.org/en/packages/

Что F-Droid обычно хочет по сути:
- свободная лицензия;
- сборка из исходников;
- понятный source repo;
- воспроизводимая или хотя бы нормально документированная сборка;
- metadata, описание, иконка, screenshots;
- без проприетарных трэкерных SDK и мутных бинарных blobs.

Что это значит для `SqueezeClip`:
- нужен `LICENSE` в корне;
- нужен понятный release build process;
- желательно убрать или минимизировать всё, что выглядит как необязательная сеть;
- нужны metadata и media assets;
- репозиторий уже публичный, это хорошо, но этого самого по себе ни хера не достаточно.

Практический gap на сейчас:
- `[ ]` лицензии нет;
- `[ ]` release build process не оформлен до воспроизводимого уровня;
- `[x]` screenshots уже сняты;
- `[x]` иконка уже не дефолтная;
- `[ ]` надо прогнать app через F-Droid-minded sanity check на предмет лишних permissions и non-free зависимостей.

## 4. Huawei AppGallery

Официальные ориентиры:
- App information / listing: https://developer.huawei.com/consumer/en/doc/app/agc-help-appinfo-0000001105336838
- App release guide: https://developer.huawei.com/consumer/en/doc/app/agc-help-releaseapp-0000001146718717
- App bundle / app signing / phased release overview: https://developer.huawei.com/consumer/en/doc/app/agc-help-harmonyapp-release-0000001914293970

Что это значит практически:
- нужен app listing с описаниями и изображениями;
- нужна privacy policy;
- нужна возрастная/контентная классификация по их формам;
- нужен подписанный релизный пакет;
- надо быть готовым к review их консоли и дополнительным региональным требованиям.

Практический gap на сейчас:
- `[x]` стартовые screenshots / assets уже есть;
- `[ ]` нет hosted privacy policy URL;
- `[ ]` нет релизной подписи;
- `[ ]` нет отдельного AppGallery checklist;
- `[ ]` надо проверить, не нужны ли huawei-specific декларации только из-за share/video behavior.

## 5. Data safety / privacy reality check

Сейчас app по факту:
- читает видео и метаданные с устройства;
- пишет сжатые видео рядом с оригиналом;
- открывает/шарит файлы по явному действию пользователя;
- не имеет аккаунтов, рекламы, аналитики и облачного компресса по текущему дизайну.

Но в shipped manifest уже видны:
- `POST_NOTIFICATIONS`
- media/storage permissions

В debug-сборках ещё может присутствовать `INTERNET` для dev workflow Flutter.

Это значит:
- в сторах надо опираться на финальный release manifest, а не на debug-мусор;
- privacy и Data safety надо писать по релизному артефакту;
- при любом изменении зависимостей надо заново проверять badging release apk/aab.

## 6. Что надо добить в репе

Сделать в коде/проекте:
- `[ ]` release signing config и инструкция без debug keys
- `[x]` release signing infrastructure и пример `android/key.properties.example`
- `[x]` release build команды для `apk` и `aab`
- `[ ]` hosted privacy policy target URL strategy
- `[ ]` LICENSE
- `[x]` production app icon / adaptive icon
- `[x]` screenshots pipeline
- `[x]` feature graphic for Play
- `[ ]` release notes workflow

Сделать в документации:
- `[x]` F-Droid prep doc
- `[x]` store playbook
- `[x]` privacy policy draft
- `[x]` Play Console checklist
- `[x]` AppGallery checklist
- `[x]` F-Droid submission checklist

## 7. Recommended next order

1. Зафиксировать лицензию и privacy policy URL.
2. Сделать release signing и `flutter build appbundle`.
3. Подготовить icon + screenshots + feature graphic.
4. Зачистить или объяснить лишние permissions.
5. Оформить per-store checklists и release pipeline.
