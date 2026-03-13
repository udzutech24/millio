# TestFlight release automation

## Что добавлено

- `fastlane` lane `ios release_testflight` для сборки и загрузки в TestFlight
- `scripts/release_testflight.sh` как одна команда для локального запуска
- `make testflight` как короткий alias

## Что нужно настроить один раз

### 1. Ruby gems

```bash
bundle install
```

### 2. App Store Connect API key

Создай API key в App Store Connect с доступом к `Developer` или выше и выставь переменные окружения:

```bash
export APP_STORE_CONNECT_API_KEY_ID=YOUR_KEY_ID
export APP_STORE_CONNECT_ISSUER_ID=YOUR_ISSUER_ID
export APP_STORE_CONNECT_API_KEY_PATH=/absolute/path/to/AuthKey_XXXXXX.p8
```

Альтернатива: вместо `APP_STORE_CONNECT_API_KEY_PATH` можно задать `APP_STORE_CONNECT_API_KEY_CONTENT`.
Если ключ передается в base64, добавь:

```bash
export APP_STORE_CONNECT_API_KEY_BASE64=1
```

### 3. Signing

Сейчас проект использует `Automatic Signing`. Это может работать локально, если на машине уже есть корректные сертификаты и provisioning profiles для:

- `com.millio.app`
- `com.millio.app.currencywidget`

Если хочешь нормальный воспроизводимый pipeline, подключай `match` и запускай так:

```bash
USE_MATCH=1 ./scripts/release_testflight.sh
```

По умолчанию `match` работает в `readonly` режиме. Для первичной генерации профилей:

```bash
USE_MATCH=1 READONLY_SIGNING=0 ./scripts/release_testflight.sh
```

## Запуск

Основная команда:

```bash
./scripts/release_testflight.sh
```

Или через `make`:

```bash
make testflight
```

С changelog:

```bash
TESTFLIGHT_CHANGELOG="Bug fixes and onboarding polish" ./scripts/release_testflight.sh
```

## Что делает lane

1. Пытается взять последний build number из App Store Connect для текущей версии
2. Если App Store Connect недоступен, использует локальный build number из проекта
3. Увеличивает `CURRENT_PROJECT_VERSION`
4. Делает `Release` archive и экспорт `app-store`
5. Загружает `build/testflight/millio.ipa` в TestFlight

## Где это ломается

- Нет API key: загрузка не стартует
- Не настроен signing: archive/export развалится
- Не выкачена CloudKit schema в production: сборка загрузится, но backup/restore в TestFlight упадет
- Локальный `CURRENT_PROJECT_VERSION` изменяется в `millio.xcodeproj/project.pbxproj`, это ожидаемо
