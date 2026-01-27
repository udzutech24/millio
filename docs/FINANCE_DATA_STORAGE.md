# Хранение данных групп и счетов в финансах

## Контекст экранов

Кредиты, карты и инвестиции создаются **только** в сервисе «Финансы». Отдельные сервисные экраны для них удалены, данные остаются частью финансового контура.

## Где хранятся данные

Данные хранятся в **SwiftData** (SQLite под капотом). Физически файл базы находится в директории **Application Support** приложения.

Конфигурация задается в `millio/millioApp.swift`:
- `ModelConfiguration(schema: ..., isStoredInMemoryOnly: false)` — хранение на диске
- директория Application Support создается перед инициализацией `ModelContainer`

## Формат хранения

### SwiftData (SQLite)

Используются две основные модели:

- `millio/UI/Services/Finances/FinanceGroup.swift` — группы счетов
- `millio/UI/Services/Finances/FinanceAccount.swift` — связи между группами и счетами

### Структура FinanceGroup

```swift
@Model
final class FinanceGroup {
    var name: String
    var colorHex: String
    var createdAt: Date
    var updatedAt: Date
    var order: Int
    var isFavorite: Bool
    var priorityRaw: String
    var displayCurrency: String?
    @Relationship var accounts: [FinanceAccount]?
}
```

**Поля:**
- `name` — название группы
- `colorHex` — цвет группы в hex, например "#FF5733"
- `createdAt` — дата создания
- `updatedAt` — дата обновления
- `order` — порядок сортировки
- `isFavorite` — избранная группа
- `priorityRaw` — приоритет ("normal", "high", "low")
- `displayCurrency` — валюта отображения (опционально)
- `accounts` — связанные счета (`@Relationship(deleteRule: .nullify)`)

**Вычисляемые свойства:**
- `priority` — `GroupPriority` на основе `priorityRaw`
- `color` — `Color` из `colorHex`
- `groupUniqueID` — уникальный ID группы: `"\(name)|\(colorHex)|\(createdAt.timeIntervalSince1970)"`

### Структура FinanceAccount

```swift
@Model
final class FinanceAccount {
    var accountTypeRaw: String
    var accountID: String
    var group: FinanceGroup?
    var createdAt: Date
    var updatedAt: Date
}
```

**Поля:**
- `accountTypeRaw` — тип счета: `card`, `credit`, `investment`
- `accountID` — ID счета (cardUniqueID / creditUniqueID / investmentUniqueID)
- `group` — ссылка на группу
- `createdAt` — дата создания
- `updatedAt` — дата обновления

**Вычисляемые свойства:**
- `accountType` — `FinanceAccountType`
- `accountUniqueID` — `"\(accountTypeRaw)|\(accountID)|\(createdAt.timeIntervalSince1970)"`

## Как загружаются данные

Загрузка происходит через `ModelContext` и `FetchDescriptor` в `FinanceViewModel`:

```swift
private func loadGroups() {
    let descriptor = FetchDescriptor<FinanceGroup>()
    if let groups = try? modelContext.fetch(descriptor) {
        state.groups = groups.sorted { group1, group2 in
            if group1.isFavorite != group2.isFavorite { return group1.isFavorite }
            if group1.priority.sortOrder != group2.priority.sortOrder {
                return group1.priority.sortOrder < group2.priority.sortOrder
            }
            return group1.createdAt < group2.createdAt
        }
    }
}
```

```swift
private func loadAccounts() {
    let cardDescriptor = FetchDescriptor<Card>()
    state.availableCards = (try? modelContext.fetch(cardDescriptor)) ?? []

    let creditDescriptor = FetchDescriptor<Credit>()
    state.availableCredits = (try? modelContext.fetch(creditDescriptor)) ?? []

    let investmentDescriptor = FetchDescriptor<Investment>()
    state.availableInvestments = (try? modelContext.fetch(investmentDescriptor)) ?? []
}
```

## Сохранение данных

Изменения сохраняются через `modelContext.save()`:

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
- При удалении группы счета остаются, но отвязываются от группы
- `FinanceAccount.accountID` указывает на уникальный ID счета:
  - `cardUniqueID` (Card)
  - `creditUniqueID` (Credit)
  - `investmentUniqueID` (Investment)

## Целостность связей (практика)

- `FinanceAccount` хранит ссылку на счет по `accountID`, без прямой связи на модель.
- При загрузке данных `FinanceViewModel` очищает:
  - связи без группы (`group == nil`);
  - связи на несуществующие счета.
- Для поиска счетов используются кэши по ID (O(1)) вместо линейного прохода.

## Экспорт и импорт данных

Обе модели поддерживают экспорт/импорт для резервного копирования.

### FinanceGroup экспорт (модель)

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

### FinanceAccount экспорт (модель)

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

### Важные детали backup/restore

- При экспорте `DataRepository` **добавляет `groupUniqueID`** к `FinanceAccount` (если есть группа), чтобы восстановить связь.
- При импорте `DataRepository` сначала импортирует `FinanceGroup`, строит маппинг `groupUniqueID → FinanceGroup`, затем импортирует `FinanceAccount` и восстанавливает связи.
