# Millio — offline-first iOS приложение

Millio — iOS-приложение с локальным хранением данных (SwiftData) и резервным копированием в CloudKit.

> Статус: ядро функционально, есть компромиссы — см. `docs/CORE_STATUS.md`.

## Документация

- `docs/CORE_RULES.md` — архитектурные принципы
- `docs/CORE_STATUS.md` — текущее состояние и компромиссы
- `docs/BACKUP_RESTORE_SCHEMA.md` — backup/restore
- `docs/FINANCE_DATA_STORAGE.md` — хранение данных по финансам
- `docs/FINANCE_HISTORY_PLAN.md` — план исторических курсов и архивных счетов
- `CLAUDE.md` — проектные правила для ассистента

## Ключевые принципы

- **Offline-first:** SwiftData — единственный источник истины
- **CloudKit только для backup/restore**
- **Snapshot-restore:** без merge, восстановление полностью заменяет локальные данные
- **AppState/AppRouter:** предсказуемая навигация и состояние
- **Swift Concurrency:** `async/await`, без GCD
- **Dark Mode only**
- **Локализация:** все строки в `.xcstrings`

## Backup/Restore — фактическое поведение

- Backup запускается **автоматически** при уходе приложения в фон, если включен в профиле
- Backup хранится в **CloudKit Private DB** (`AppBackup` / `latest_backup`)
- UI для **ручного backup** сейчас отсутствует (доступно только через код)
- Restore запускается **вручную** из профиля (`RestoreView`)
- Шифрование backup есть, но **UI-тоггла нет** (`SettingsManager.isEncryptionEnabled`)
- Restore полностью заменяет локальные данные (snapshot)

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

Кредиты, карты и инвестиции создаются внутри сервиса «Финансы». Отдельные сервисные экраны для них удалены.
Список карт в форме создания транзакции Кэшфлоу обновляется при появлении экрана и перед открытием редактора.
В форме создания карты последние 4 цифры опциональны. В форме создания кредита не вводятся дата окончания и ежемесячный платеж — значения рассчитываются автоматически.
В Кэшфлоу удалена пользовательская логика «Обмен валют».

## Использование

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
- **Минимальная версия iOS**: 18.6 (см. настройки проекта)
- **Темная тема** принудительная (Dark Mode only)
- **Локализация** через `Localizable.xcstrings`

## Тестирование

Unit-тесты для Core компонентов:
- `BackupManagerTests`
- `AppStateTests`
- `AppErrorTests`

Используется Swift Testing framework.

## Лицензия

MIT
