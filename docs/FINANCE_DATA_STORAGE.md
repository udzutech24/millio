# Хранение данных групп и счетов в финансах

## Контекст экранов

Кредиты, карты и инвестиции создаются **только** в сервисе «Финансы». Отдельные сервисные экраны для них удалены, данные остаются частью финансового контура.

### UI-особенности создания

- Поле «последние 4 цифры карты» опционально.
- В форме создания кредита не вводятся дата окончания и ежемесячный платеж — используются дефолты.

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

### Кэшфлоу и список доступных карт

- `CashflowViewModel` использует `state.availableCards` для формы создания транзакций и истории операций.
- Чтобы список не устаревал после создания/удаления карт в «Финансах», обновление выполняется:
  - при каждом появлении экрана «Кэшфлоу»;
  - перед открытием редактора транзакции (создание/редактирование).
- Дополнительно используется `EventBus`: `CardViewModel` публикует событие `FinanceEvent.cardsUpdated`,
  а `CashflowViewModel` подписывается и обновляет список в реальном времени.
- При изменении остатка долга кредита публикуется `FinanceEvent.creditsUpdated` —
  `FinanceViewModel` пересчитывает суммы групп, а экран динамики обновляет данные через `loadData()`.
- В кэшфлоу график удален: отображается только текстовая сводка по выбранному периоду.
- Для выбора произвольного периода в кэшфлоу используется `CalendarRangeMonthView`.
- Кнопки «Доход/Расход/Перевод» в кэшфлоу — иконки в одном ряду без текста.
- Выбор валюты отображения и история операций в кэшфлоу находятся в хедере справа (иконки).
- Быстрый доступ к истории операций также доступен с главного экрана через иконку в хедере.
- Логика пользовательского обмена валют удалена.
- В форме операции расход/перевод нельзя превысить доступный баланс карты-источника; показывается доступная сумма.
- В переводах нельзя выбрать одну и ту же карту как источник и получатель.

### Транзакции корректировки баланса/долга

- Быстрое редактирование суммы карты создаёт транзакцию типа `cardBalanceAdjustment`.
- Быстрое редактирование долга (кредитная карта/кредит) создаёт транзакцию типа `creditDebtAdjustment`.
- Редактирование баланса карты или остатка долга через форму также создаёт соответствующую транзакцию.

### Ручная корректировка остатка долга кредита

- Для кредита хранится поле `remainingAmountAdjustment` — ручная поправка к расчетному остатку.
- При быстром редактировании или изменении долга через форму сохраняется новая сумма и вычисляется поправка.
- Автоматический пересчёт остатка долга учитывает эту поправку, поэтому ручные корректировки не затираются.
- В динамике, если корректировка была сделана без транзакций, актуальный остаток подставляется по `remainingAmount`.
- Если история транзакций неполная, динамика фиксирует актуальный остаток на дату последнего изменения кредита.

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

---

## Экран динамики финансов

### Обзор

Экран динамики (`FinanceDynamicsView`) отображает историю изменения балансов счетов в виде интерактивного графика.

### UI-компоненты

#### FinanceChartContainerView

Переиспользуемый компонент графика (`UI/Shared/FinanceChartContainerView.swift`):

- **AreaMark + LineMark** с градиентной заливкой и плавной интерполяцией (Catmull-Rom)
- **Интерактивный выбор точки** — drag gesture с bubble-аннотацией
- **Автоматическая шкала Y** — `NiceYScale` рассчитывает красивые значения для осей
- **Компактное форматирование** — суммы отображаются как "1.5 млн", "500 тыс"

```swift
FinanceChartContainerView(
    points: chartData,
    selectedPoint: selectedPoint,
    seriesColor: .orange,
    niceY: NiceYScale.make(values: values),
    xDomain: startDate...endDate,
    xAxisStride: .day,
    xAxisCount: 7,
    currencyCode: "RUB",
    onSelectPoint: { point in ... }
)
```

#### CalendarRangeMonthView

Компонент выбора диапазона дат (`UI/Shared/CalendarRangeMonthView.swift`):

- Визуальное выделение выбранного диапазона
- Навигация по месяцам
- Блокировка будущих дат
- Градиентная подсветка начала/конца периода

```swift
CalendarRangeMonthView(startDate: $start, endDate: $end)
```

### Функциональность

#### Периоды

- **1W** — последние 7 дней
- **1M** — последние 30 дней
- **1Y** — последние 365 дней
- **All** — с самой ранней даты создания счета/транзакции
- **Custom** — произвольный диапазон через календарь

#### Фильтрация

- По группам счетов
- По отдельным счетам внутри групп
- По валюте отображения (конвертация через CurrencyRateService)

#### Режимы просмотра списка

- **Группы** — динамика по группам счетов
- **Счета** — динамика по каждому счету отдельно

### Collapsing Header

При прокрутке график плавно сворачивается:

```swift
.onPreferenceChange(ScrollOffsetKey.self) { y in
    let threshold: CGFloat = 140
    let p = min(max(-y / threshold, 0), 1)
    collapseProgress = p
}
```

### Кэширование

`FinanceDynamicsViewModel` использует несколько уровней кэшей для оптимизации:

- `cardsCache`, `creditsCache`, `investmentsCache` — O(1) поиск по ID
- `transactionsByCardCache` — транзакции сгруппированы по карте
- `balanceCache` — результаты расчета баланса на дату
- `initialBalancesCache` — начальные балансы счетов

---

## Архивация счетов (Card/Credit/Investment)

Удаление счетов переведено в **архивирование**:
- В моделях `Card`, `Credit`, `Investment` используется поле `archivedAt`.
- Текущие списки и итоги показывают **только активные** счета (`archivedAt == nil`).
- История и динамика учитывают архивные счета до даты `archivedAt` включительно.
- При удалении счета из группы (отвязке) связанный счет тоже архивируется.
- При удалении группы все привязанные к ней счета архивируются.
- В форме «Новый продукт» доступно восстановление счета из архива и добавление в группу.
- Семантика `archivedAt`:
  - при восстановлении из архива `archivedAt` сбрасывается в `nil`;
  - при повторной архивации выставляется новая дата (архивный счет учитывается в динамике до этой даты).

Это позволяет сохранить прошлую историю без искажения “Итого (сегодня)”.

---

## Исторические курсы валют

Добавлена модель `HistoricalRate` для хранения курсов на конкретные даты:
- `baseCurrency`, `quoteCurrency`
- `rate`
- `rateDate` (дневная гранулярность, локальная таймзона пользователя)
- `source`, `fetchedAt`

Использование:
- Исторические вычисления (Cashflow, Finance Dynamics) берут курс **на дату операции**.
- Если исторический курс недоступен, используется фоллбек (последний известный → текущий курс).
