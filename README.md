# Millio — offline-first iOS приложение

Millio — iOS-приложение с локальным хранением данных (SwiftData) и резервным копированием в CloudKit.

> Статус: ядро функционально, есть компромиссы — см. `docs/CORE_STATUS.md`.

## Документация

- `docs/CORE_RULES.md` — архитектурные принципы
- `docs/CORE_STATUS.md` — текущее состояние и компромиссы
- `docs/CURRENCY_POLICY.md` — правила основной/избранных валют
- `docs/BACKUP_RESTORE_SCHEMA.md` — backup/restore
- `docs/SMART_DATA_RESET.md` — гибкая очистка данных
- `docs/FINANCE_DATA_STORAGE.md` — хранение данных по финансам
- `CLAUDE.md` — проектные правила для ассистента

## Ключевые принципы

- **Offline-first:** SwiftData — единственный источник истины
- **CloudKit только для backup/restore**
- **Snapshot-restore:** без merge, восстановление полностью заменяет локальные данные
- **AppState/AppRouter:** предсказуемая навигация и состояние
- **Swift Concurrency:** `async/await`, без GCD
- **Dark Mode only**
- **Локализация:** все строки в `.xcstrings`
- **Настройки:** в профиле выбираются язык, основная валюта и избранные валюты
- **Курсы валют:** по умолчанию используется ERAPI; выбор источника в конвертере — локальная настройка

## Backup/Restore — фактическое поведение

- Backup запускается **автоматически** при уходе приложения в фон, если включен в профиле
- Backup хранится в **CloudKit Private DB** (`AppBackup` / `latest_backup`) внутри iCloud-аккаунта пользователя, а не в публичном хранилище Millio
- В профиле доступен экран управления backup (включение/статус/создание backup/выбор и удаление версий)
- В профиле доступна «Умная очистка данных» (выбор периода и типов данных для удаления)
- Restore запускается **вручную** из профиля (`RestoreView`)
- Шифрование backup поддерживает **keychain-mode** (device-only, ключ остается в iOS Keychain на этом устройстве) и **passphrase-mode** (переносимо, кодовая фраза не хранится в Millio); режим выбирается в экране управления backup
- В `RestoreView` есть поле для ввода парольной фразы (нужно для passphrase-mode)
- Restore полностью заменяет локальные данные (snapshot)
- Автоматические backup продолжают сохранять последнюю историю по retention, а вручную сохраненные версии помечаются как закрепленные и не удаляются автоматически
- В Release ошибки backup/restore отправляются как non-fatal в Crashlytics через `CrashReporting.record(error:)`
- Сжатие LZFSE применяется только если уменьшает размер; ошибки сжатия/упаковки считаются критическими для операции backup/restore

Подробнее: `docs/BACKUP_RESTORE_SCHEMA.md`.

## Структура проекта

```
millio/
├── Core/
│   ├── AppState/          # Управление состоянием приложения
│   ├── Backup/            # Backup/Restore через CloudKit
│   ├── DI/                # Dependency Injection Container
│   ├── Environment/       # Environment keys для SwiftUI
│   ├── Error/             # Обработка ошибок и recovery стратегии
│   ├── Events/            # Event Bus для слабой связанности
│   ├── Features/          # Регистрация feature модулей
│   ├── Language/          # Мультиязычность
│   ├── Logging/           # Логирование через OSLog
│   ├── Navigation/        # Навигационное ядро
│   ├── Network/           # Retry механизм для сетевых операций
│   ├── Repository/        # Абстракции для SwiftData
│   ├── Schema/            # Схема SwiftData (AppSchema)
│   ├── Security/          # Шифрование backup (Keychain)
│   ├── Settings/          # Управление настройками
│   ├── UseCases/          # Бизнес-логика ядра
│   └── ViewModels/        # Базовые ViewModels для MVVM
├── UI/
│   ├── Onboarding/        # Онбординг
│   ├── Launching/         # Экран загрузки
│   ├── Main/              # Главный экран
│   ├── Profile/           # Профиль и настройки
│   ├── Restore/           # Экран восстановления
│   ├── Error/             # Экран ошибок
│   ├── Subscription/      # Экран подписки PRO
│   ├── Services/          # Экраны сервисов
│   ├── Shared/            # Общие UI компоненты
│   └── Design/            # Дизайн-токены
├── Assets.xcassets
├── Localizable.xcstrings
└── LaunchScreen.storyboard
```

## Основные компоненты

- **AppState / AppLifecycleUseCase** — жизненный цикл и глобальное состояние
- **BackupManager / CloudBackupStore** — резервное копирование и restore
- **DataRepository** — экспорт/импорт/очистка данных SwiftData
- **ModelTypeRegistry** — регистрация моделей и импортеров
- **DIContainer** — централизованное создание зависимостей
- **AppSchema** — динамическая схема SwiftData

## Экраны сервисов

В проекте реализованы экраны:
- Финансы, Кэшфлоу, Курсы валют, Кэшбэк
- В форме создания кэшбэка поддержан импорт категорий и процентов со скриншота (OCR): распознаются строки вида `5% Категория` и `5% Category`, а также автосопоставление очевидных RU/EN названий в системные категории.
- В пользовательских категориях кэшбэка доступен расширенный стандартный каталог: большой список SF Symbols и базовые emoji, включая быстрый поиск по символам.
- На экране «Избранные категории» и в редакторе кэшбэка у пользовательских категорий есть явная кнопка редактирования (pencil), через которую можно быстро поменять название, emoji или SF Symbol; удаление также доступно из контекстного меню.
- Home Screen Widget: конвертер валют (доступен всем пользователям; данные берутся из App Group `group.com.millio.app`)

Кредиты, карты и инвестиции создаются внутри сервиса «Финансы». Отдельные сервисные экраны для них удалены.
Инвестиции поддерживают рыночные активы: акции и криптовалюты с поиском тикера/пары и расчетом позиции.
Список карт в форме создания транзакции Кэшфлоу обновляется при появлении экрана и перед открытием редактора.
В форме создания карты последние 4 цифры опциональны. В форме создания кредита не вводятся дата окончания и ежемесячный платеж — значения рассчитываются автоматически.
В Кэшфлоу удалена пользовательская логика «Обмен валют».

## Использование

### Локальная backend-конфигурация

- Локальный файл: `millio/Config/Secrets.local`
- Пример: `millio/Config/Secrets.local.example`
- Формат:

```xcconfig
AUTH_BASE_URL =
AUTH_BASE_SCHEME = http
AUTH_BASE_HOST = localhost
AUTH_BASE_PORT = 3000
AUTH_BASE_PATH = /api/v1
```

`Secrets.local` подключается из `Debug.xcconfig` и `Release.xcconfig` через `#include?`, поэтому файл можно не коммитить.

### Ручной backup (из кода)

```swift
// Через DIContainer
let diContainer = DIContainer.create(appState: appState, modelContainer: modelContainer)
try await diContainer.backupManager.backupNow()

// Или напрямую
let backupManager = BackupManager(dataRepository: dataRepository)
try await backupManager.backupNow()
```

### Restore

```swift
try await backupManager.restoreLatest()
```

### Регистрация новой модели

```swift
// 1. Модель, реализующая Persistable
@Model
final class MyModel: Persistable {
    // ...
}

// 2. Импортер
struct MyModelImporter: ModelImporter {
    static func importType() -> String { "MyModel" }
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        // Реализация импорта
    }
}

// 3. Регистрация
ModelTypeRegistry.shared.register(MyModel.self, typeName: "MyModel")
ModelTypeRegistry.shared.registerImporter(MyModelImporter.self)
```

## Настройка проекта

- **CloudKit capability** подключается в Xcode → Target → Signing & Capabilities
- **Container ID**: `iCloud.com.millio.app`
- После добавления новых `CKRecord` типов или полей schema нужно вручную выкатить из CloudKit `Development` в `Production`, иначе в TestFlight/App Store backup упадет с ошибкой `Cannot create new type ... in production schema`
- **Минимальная версия iOS**: 18.6 (см. настройки проекта)
- **Темная тема** принудительная (Dark Mode only)
- **Локализация** через `Localizable.xcstrings`
- **Конвертер** использует ключи локализации с префиксом `converter.*` (RU/EN), включая тексты отправки и шаринга
- **Главный экран** использует ключи локализации с префиксом `main.*` (RU/EN): быстрые действия, названия мини‑приложений, accessibility

## Тестирование

Unit-тесты для Core компонентов:
- `BackupManagerTests`
- `AppStateTests`
- `AppErrorTests`

Используется Swift Testing framework.

## Лицензия

MIT
