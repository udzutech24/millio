# Firebase Crashlytics (iOS)

## Цели
- Автоматический сбор crash-отчётов на iOS.
- Отправка non-fatal ошибок через `record(error:)`.
- Поддержка custom logs и custom keys для ускорения диагностики.
- Минимальное влияние на производительность: отключение в Debug и при unit tests.

## Текущая интеграция в проекте
- Dependency manager: Swift Package Manager (Firebase iOS SDK).
- Версия Firebase SDK фиксируется через `Package.resolved`.
- `GoogleService-Info.plist` лежит в корне проекта и добавлен в Resources.

## Инициализация
- Инициализация Firebase и Crashlytics выполняется при старте приложения через `UIApplicationDelegateAdaptor`.
- Политика включения:
  - Debug: Crashlytics выключен.
  - Unit tests: Crashlytics выключен.
  - Release: Crashlytics включен.
  - Override: переменная окружения `MILLIO_CRASHLYTICS_ENABLED` (`true/false/1/0`).

## API для использования в коде
Используйте фасад:
- `CrashReporting.log(_:)` — добавить строку в crash-log.
- `CrashReporting.setCustomValue(_:forKey:)` — добавить кастомный ключ/значение.
- `CrashReporting.record(error:)` — отправить non-fatal ошибку.

Также `.warning/.error` сообщения из `AppLogger` автоматически дублируются в Crashlytics.
Ошибки backup/restore (например, `AppError.restoreFailed`) также отправляются как non-fatal через `CrashReporting.record(error:)`.

## Символикация (dSYM) и деплой
Crashlytics требует dSYM для читаемых stack traces. Для этого добавлен Build Phase “Firebase Crashlytics” со скриптом `Crashlytics/run`.

Проверка:
1) Собрать Release на устройстве/симуляторе.
2) Убедиться, что Build Phase выполняется без ошибок.
3) В Firebase Console → Crashlytics убедиться, что новые отчёты приходят со символами.

## Обновление Firebase SDK
1) В Xcode → Package Dependencies обновить `firebase-ios-sdk` (up to next major).
2) Прогнать `xcodebuild test`.
3) После обновления проверить:
   - сборку Release,
   - выполнение Crashlytics run script,
   - поступление crash-отчётов в консоль.

## Примечания по безопасности
- Не отправляйте в custom logs/keys PII (персональные данные, финансовые значения, токены, ключи).
- Логи уровня `.warning/.error` помечены как private для OSLog и должны быть очищены от PII до логирования.
