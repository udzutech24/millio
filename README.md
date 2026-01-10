# Millio - iOS Core Framework

Чистое, offline-first iOS-ядро приложения с поддержкой резервного копирования через CloudKit.

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
│   ├── Environment/        # Environment keys для SwiftUI
│   ├── Language/          # Мультиязычность
│   ├── Logging/           # Логирование через OSLog
│   ├── Navigation/        # Навигационное ядро
│   ├── Repository/        # Абстракции для SwiftData
│   ├── Settings/           # Управление настройками
│   └── UseCases/          # Бизнес-логика ядра
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
let backupManager = BackupManager(dataRepository: dataRepository)
try await backupManager.backupNow()
```

### Restore

```swift
try await backupManager.restoreLatest()
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
