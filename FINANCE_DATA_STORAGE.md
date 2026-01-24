# Хранение данных групп и счетов в финансах

## Где хранятся данные

Данные хранятся в **SwiftData** (который использует SQLite под капотом). Физически данные находятся в директории **Application Support** приложения.

Конфигурация происходит в [`millioApp.swift`](millio/millioApp.swift:42):
- `ModelConfiguration` с `isStoredInMemoryOnly: false` - означает постоянное хранение на диске
- По умолчанию SwiftData создает SQLite файл в Application Support директории

## Формат хранения

### SwiftData (SQLite)

Данные хранятся в SQLite базе данных через SwiftData framework. Используются две основные модели:

- [`FinanceGroup`](millio/UI/Services/Finances/FinanceGroup.swift) - группы счетов
- [`FinanceAccount`](millio/UI/Services/Finances/FinanceAccount.swift) - связи между группами и счетами

### Структура FinanceGroup

```swift
@Model
final class FinanceGroup {
    var name: String                    // Название группы
    var colorHex: String                // Цвет в hex формате (например "#FF5733")
    var createdAt: Date                // Дата создания
    var updatedAt: Date                 // Дата обновления
    var order: Int                     // Порядок сортировки
    var isFavorite: Bool               // Избранная группа
    var priorityRaw: String            // Приоритет ("normal", "high", "low")
    var displayCurrency: String?       // Валюта отображения (опционально)
    @Relationship var accounts: [FinanceAccount]?  // Связанные счета
}
```

**Поля:**
- `name` - название группы (String)
- `colorHex` - цвет группы в формате hex строки, например "#FF5733" (String)
- `createdAt` - дата создания (Date)
- `updatedAt` - дата последнего обновления (Date)
- `order` - порядок сортировки (Int)
- `isFavorite` - флаг избранной группы (Bool)
- `priorityRaw` - приоритет группы в виде строки: "normal", "high", "low" (String)
- `displayCurrency` - валюта отображения суммы группы, nil означает использование общей валюты (String?)
- `accounts` - массив связанных счетов через отношение `@Relationship(deleteRule: .nullify)` ([FinanceAccount]?)

**Вычисляемые свойства:**
- `priority` - возвращает `GroupPriority` enum на основе `priorityRaw`
- `color` - возвращает SwiftUI `Color` на основе `colorHex`
- `groupUniqueID` - уникальный идентификатор группы: `"\(name)|\(colorHex)|\(createdAt.timeIntervalSince1970)"`

### Структура FinanceAccount

```swift
@Model
final class FinanceAccount {
    var accountTypeRaw: String          // Тип: "card", "credit", "investment"
    var accountID: String               // ID счета (cardUniqueID, creditUniqueID или investmentUniqueID)
    var group: FinanceGroup?            // Связь с группой
    var createdAt: Date                // Дата создания
    var updatedAt: Date                 // Дата обновления
}
```

**Поля:**
- `accountTypeRaw` - тип счета в виде строки: "card", "credit", "investment" (String)
- `accountID` - уникальный идентификатор счета, который ссылается на:
  - `cardUniqueID` для карт
  - `creditUniqueID` для кредитов
  - `investmentUniqueID` для инвестиций (String)
- `group` - опциональная связь с группой через `@Relationship` (FinanceGroup?)
- `createdAt` - дата создания (Date)
- `updatedAt` - дата последнего обновления (Date)

**Вычисляемые свойства:**
- `accountType` - возвращает `FinanceAccountType` enum на основе `accountTypeRaw`
- `accountUniqueID` - уникальный идентификатор счета: `"\(accountTypeRaw)|\(accountID)|\(createdAt.timeIntervalSince1970)"`

**Типы счетов (FinanceAccountType):**
- `card` - карта
- `credit` - кредит
- `investment` - актив/инвестиция

## Как загружаются данные

Данные загружаются через `ModelContext` с использованием `FetchDescriptor`:

### Загрузка групп

В [`FinanceViewModel.swift`](millio/UI/Services/Finances/FinanceViewModel.swift:414):

```swift
private func loadGroups() {
    let descriptor = FetchDescriptor<FinanceGroup>()
    if let groups = try? modelContext.fetch(descriptor) {
        // Сортируем: сначала избранные, потом по приоритету, потом по дате создания
        state.groups = groups.sorted { group1, group2 in
            // Сначала избранные
            if group1.isFavorite != group2.isFavorite {
                return group1.isFavorite
            }
            // Потом по приоритету
            if group1.priority.sortOrder != group2.priority.sortOrder {
                return group1.priority.sortOrder < group2.priority.sortOrder
            }
            // Потом по дате создания
            return group1.createdAt < group2.createdAt
        }
    }
}
```

### Загрузка счетов

В [`FinanceViewModel.swift`](millio/UI/Services/Finances/FinanceViewModel.swift:436):

```swift
private func loadAccounts() {
    // Загружаем карты, кредиты и активы
    let cardDescriptor = FetchDescriptor<Card>()
    state.availableCards = (try? modelContext.fetch(cardDescriptor)) ?? []
    
    let creditDescriptor = FetchDescriptor<Credit>()
    state.availableCredits = (try? modelContext.fetch(creditDescriptor)) ?? []
    
    let investmentDescriptor = FetchDescriptor<Investment>()
    state.availableInvestments = (try? modelContext.fetch(investmentDescriptor)) ?? []
    
    // Обновляем менеджеры
    CardManager.shared.setup(modelContext: modelContext)
    CreditManager.shared.setup(modelContext: modelContext)
    InvestmentManager.shared.setup(modelContext: modelContext)
}
```

## Сохранение данных

Данные сохраняются автоматически при вызове `modelContext.save()` после изменений:

```swift
do {
    try modelContext.save()
    loadGroups()
} catch {
    AppLogger.log(.error, category: "Finance", "Failed to save group: \(error.localizedDescription)")
}
```

## Связи между моделями

- `FinanceGroup` имеет отношение `@Relationship(deleteRule: .nullify)` к `FinanceAccount`
- При удалении группы, связанные счета не удаляются, а просто отвязываются от группы (`group = nil`)
- `FinanceAccount` ссылается на конкретные счета через `accountID`, который может быть:
  - `cardUniqueID` для карт (модель `Card`)
  - `creditUniqueID` для кредитов (модель `Credit`)
  - `investmentUniqueID` для инвестиций (модель `Investment`)

## Экспорт и импорт данных

Обе модели поддерживают экспорт/импорт для резервного копирования:

### FinanceGroup экспорт

```swift
func export() throws -> Data {
    var dict: [String: Any] = [
        "type": "FinanceGroup",
        "name": name,
        "colorHex": colorHex,
        "createdAt": createdAt.timeIntervalSince1970,
        "updatedAt": updatedAt.timeIntervalSince1970,
        "order": order,
        "isFavorite": isFavorite,
        "priorityRaw": priorityRaw,
        "groupUniqueID": groupUniqueID
    ]
    if let displayCurrency = displayCurrency {
        dict["displayCurrency"] = displayCurrency
    }
    return try JSONSerialization.data(withJSONObject: dict)
}
```

### FinanceAccount экспорт

```swift
func export() throws -> Data {
    let dict: [String: Any] = [
        "type": "FinanceAccount",
        "accountTypeRaw": accountTypeRaw,
        "accountID": accountID,
        "createdAt": createdAt.timeIntervalSince1970,
        "updatedAt": updatedAt.timeIntervalSince1970,
        "accountUniqueID": accountUniqueID
    ]
    return try JSONSerialization.data(withJSONObject: dict)
}
```

Импорт происходит через `FinanceGroupImporter` и `FinanceAccountImporter` в [`FinanceFeatureRegistration.swift`](millio/UI/Services/Finances/FinanceFeatureRegistration.swift).

## Регистрация в схеме

Модели регистрируются в схеме SwiftData через [`AppSchema.swift`](millio/Core/Schema/AppSchema.swift:74-82):

```swift
// Явно добавляем модели FinanceGroup
if !modelTypes.contains(where: { $0 == FinanceGroup.self }) {
    modelTypes.append(FinanceGroup.self)
}

// Явно добавляем модели FinanceAccount
if !modelTypes.contains(where: { $0 == FinanceAccount.self }) {
    modelTypes.append(FinanceAccount.self)
}
```

## Резюме

- **Хранилище**: SwiftData (SQLite)
- **Расположение**: Application Support директория приложения
- **Формат**: SQLite база данных (бинарный формат)
- **Модели**: `FinanceGroup` и `FinanceAccount` с отношениями через `@Relationship`
- **Доступ**: через `ModelContext` и `FetchDescriptor` запросы
- **Сохранение**: автоматически при вызове `modelContext.save()`
