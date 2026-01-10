# Millio - iOS Core Framework

Чистое, offline-first iOS-ядро приложения с поддержкой резервного копирования через CloudKit.

> ✅ **Ядро готово к использованию.** Все архитектурные улучшения реализованы.  
> См. `CORE_STATUS.md` для детального анализа статуса ядра.

## Архитектура

- **MVVM + Clean Core (ports & adapters)**
- **Offline-first** - SwiftData как единственный источник истины
- **CloudKit** - только для backup/restore, не участвует в runtime-логике
- **SwiftUI** - декларативный UI
- **Swift Concurrency** - современная конкурентность

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
│   ├── Features/           # Регистрация feature модулей
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
│   ├── Onboarding/        # Экран онбординга
│   ├── Restore/           # Экран восстановления
│   ├── Main/              # Главный экран
│   ├── Launching/         # Экран загрузки (SwiftUI)
│   ├── Error/             # Экран ошибок
│   ├── Services/          # Экраны сервисов (8 экранов)
│   ├── Profile/           # Экран профиля с настройками
│   ├── Notifications/     # Экран уведомлений
│   ├── Subscription/      # Экран подписки PRO
│   ├── Shared/            # Общие UI компоненты
│   └── Design/            # Система дизайна (цвета, токены)
├── LaunchScreen.storyboard # Launch Screen (статический экран до загрузки)
└── Localizable.xcstrings  # String Catalog для локализации
```

## Основные компоненты

### AppState
Единое состояние приложения:
- `AppLifecycleState` - состояния жизненного цикла
- `AppState` - наблюдаемое состояние через `@Observable`

### BackupManager
Сервис резервного копирования:
- Автоматический backup при уходе в background
- Ручной backup
- Restore из iCloud
- Проверка доступности iCloud

### DataRepository
Абстракция для работы с SwiftData:
- Экспорт всех данных
- Импорт данных
- Очистка хранилища

### Протоколы
- `Exportable` - экспорт данных модели
- `Importable` - импорт данных модели
- `Persistable` - комбинация Exportable + Importable + PersistentModel
- `ModelImporter` - импорт моделей из backup
- `BackupEncryptionProtocol` - шифрование backup
- `ErrorRecoveryStrategy` - стратегии восстановления от ошибок
- `FeatureModule` - регистрация feature модулей

### DIContainer
Централизованное управление зависимостями:
- Создание всех зависимостей в одном месте
- Упрощает тестирование
- Используется в `millioApp` для инициализации

### ModelTypeRegistry
Регистрация типов моделей для экспорта/импорта:
- Фичи регистрируют свои модели самостоятельно
- Ядро не знает конкретные типы
- Поддержка импортеров для восстановления данных

### AppSchema
Динамическая сборка схемы SwiftData:
- Базовые типы ядра
- Типы из ModelTypeRegistry
- Не требует изменения `millioApp` при добавлении фич

## Настройка

### 1. CloudKit Capability
В Xcode:
1. Выберите проект → Target → Signing & Capabilities
2. Добавьте CloudKit capability
3. Настройте Container (по умолчанию используется `.default()`)

### 2. Info.plist
Темная тема настроена через `Info.plist`:
```xml
<key>UIUserInterfaceStyle</key>
<string>Dark</string>
```

### 3. Минимальная версия iOS
iOS 18+ (настроено в проекте)

## Использование

### Добавление новой модели данных

Модель должна соответствовать протоколу `Persistable`:

```swift
@Model
final class MyModel: Persistable {
    var name: String
    
    func export() throws -> Data {
        // Реализация экспорта
    }
    
    static func `import`(_ data: Data) throws {
        // Реализация импорта
    }
}
```

### Работа с AppState

```swift
@Environment(AppState.self) var appState

// Изменение состояния
appState.lifecycle = .ready
appState.isICloudAvailable = true
```

### Ручной backup

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
// 1. Создайте модель, реализующую Persistable
@Model
final class MyModel: Persistable {
    // ...
}

// 2. Создайте импортер
struct MyModelImporter: ModelImporter {
    static func importType() -> String { "MyModel" }
    static func `import`(from data: [String: Any], context: ModelContext) throws {
        // Реализация импорта
    }
}

// 3. Зарегистрируйте в FeatureRegistry или напрямую
ModelTypeRegistry.shared.register(MyModel.self, typeName: "MyModel")
ModelTypeRegistry.shared.registerImporter(MyModelImporter.self)
```

## Тестирование

Unit-тесты для Core компонентов:
- `BackupManagerTests` - тесты backup/restore
- `AppStateTests` - тесты состояния
- `AppErrorTests` - тесты ошибок

Используется новый Swift Testing framework.

## Логирование

Все логи через OSLog:
```swift
AppLogger.log(.info, category: "MyCategory", "Message")
```

## Мультиязычность

Строки через String Catalog (`Localizable.xcstrings`):
```swift
Text("welcome", bundle: .main)
```

Язык управляется через `LanguageManager`:
```swift
LanguageManager.shared.setLanguage(.russian)
```

## UI Компоненты

### Главный экран
Главный экран (`MainAppView`) предоставляет:
- Доступ к 8 сервисам (Финансы, Курсы, Кешбэк, Кредиты, Вода, Привычки, Картотека, Игры)
- Быстрые действия (Расход/Доход)
- Навигацию к профилю, уведомлениям и подписке
- Единый градиентный фон для всех экранов

### Экраны сервисов
Все экраны сервисов пустые и готовы к наполнению бизнес-логикой:
- `FinancesView` - Финансы
- `CoursesView` - Курсы
- `CashbackView` - Кешбэк
- `CreditsView` - Кредиты
- `WaterView` - Вода
- `HabitsView` - Привычки
- `CardIndexView` - Картотека
- `GamesView` - Игры

### Дополнительные экраны
- `ProfileView` - Профиль с настройками (включая настройки backup)
- `NotificationsView` - Уведомления
- `SubscriptionView` - Подписка PRO

### Общие компоненты
- `GradientBackground` - Градиентный фон для всех экранов
- `ServiceButton` - Кнопка сервиса с градиентной обводкой
- `ActionButton` - Кнопка действия (Расход/Доход)

### Система дизайна
- `AppColors` - Централизованная палитра цветов приложения
  - Градиенты фона
  - Цвета текста (primary, secondary, tertiary)
  - Градиенты для сервисов и действий
  - UI элементы (иконки, бейджи, ошибки)

Подробнее см. `DESIGN_SYSTEM.md`

### ViewModels
- `BaseViewModel` - базовый протокол для ViewModels
- `MainAppViewModel` - ViewModel для главного экрана
- Следует принципам MVVM

### Дополнительные компоненты
- `DIContainer` - Dependency Injection Container
- `AppSchema` - динамическая сборка схемы SwiftData
- `ModelTypeRegistry` - регистрация типов моделей и импортеров
- `ErrorRecoveryManager` - стратегии восстановления от ошибок
- `RetryPolicy` - политика повторов для сетевых операций
- `BackupMonitor` - мониторинг состояния backup
- `KeychainBackupEncryption` - шифрование backup через Keychain
- `EventBus` - система событий для слабой связанности
- `FeatureRegistry` - регистрация feature модулей

### Launch Screen
Приложение использует двухуровневый подход к splash screen:

1. **LaunchScreen.storyboard** - Статический экран, показывается до загрузки SwiftUI
   - Градиентный фон (темно-синий)
   - Логотип "millio" и слоган
   - Настроен через `INFOPLIST_KEY_UILaunchStoryboardName`

2. **LaunchingView** - SwiftUI экран во время инициализации приложения
   - Градиентный фон (`GradientBackground`)
   - Анимированный логотип с плавным появлением
   - Индикатор загрузки
   - Показывается во время `AppLifecycleState.launching`

## Архитектурные улучшения

Все улучшения из `ARCHITECTURE_IMPROVEMENTS.md` реализованы:
- ✅ DI Container
- ✅ Вынос схемы SwiftData
- ✅ Устранение fatalError
- ✅ ModelTypeRegistry в DataRepository
- ✅ ViewModel слой
- ✅ Error Recovery
- ✅ Retry механизм
- ✅ Мониторинг backup
- ✅ Шифрование backup
- ✅ Сжатие backup
- ✅ Event Bus
- ✅ Feature Registry

Подробнее см. `CORE_STATUS.md`

## Ограничения ядра

Ядро **НЕ** содержит:
- Бизнес-логику фич (курсы, финансы и т.д.)
- Сетевые клиенты для бизнес-данных
- Монетизацию
- Публичные данные других пользователей

## Definition of Done

✅ Приложение работает полностью offline  
✅ Удаление + установка → успешный restore  
✅ iCloud выключен → приложение стабильно  
✅ Смена языка применяется глобально  
✅ Нет светлой темы нигде  

## Лицензия

MIT
