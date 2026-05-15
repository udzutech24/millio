fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios release_testflight

```sh
[bundle exec] fastlane ios release_testflight
```

Build and upload the app to TestFlight

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Генерирует сырые App Store скриншоты через Screenshot Mode + fastlane snapshot.
  После захвата: cd Маркетинг/screenshots-remotion && npm run render — финальные карточки.
  Запуск: bundle exec fastlane screenshots

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Загружает скриншоты App Store из fastlane/screenshots/ (EN + RU, iPhone67Display).
  Запуск: bundle exec fastlane upload_screenshots

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Загружает метаданные App Store (описания, ключевые слова, release notes) из fastlane/metadata/ без бинарника.
  Запуск: bundle exec fastlane upload_metadata
  Флаги: skip_screenshots:true (по умолчанию), force:true — без подтверждения

### ios distribute

```sh
[bundle exec] fastlane ios distribute
```

Distribute already-uploaded build to internal testers (millio group)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
