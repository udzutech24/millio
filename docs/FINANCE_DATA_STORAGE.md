# Хранение данных групп и счетов в финансах

## Контекст экранов

Кредиты, карты и инвестиции создаются **только** в сервисе «Финансы». Отдельные сервисные экраны для них удалены, данные остаются частью финансового контура.

### UI-особенности создания

- Поле «последние 4 цифры карты» опционально.
- В форме создания кредита поддерживаются поля:
  - остаток долга;
  - платеж в месяц;
  - режим даты платежа (`dayOfMonth` / `nextDate`);
  - напоминание (вкл/выкл, за N дней, время уведомления).
- Для кредита влияние на «Итого» фиксировано как «Уменьшает», в расчете участвует `remainingAmount` как отрицательное значение.
- Для инвестиций в категориях `stocks` и `crypto` используется специализированная форма:
  - поиск тикера/пары через bottom-sheet;
  - ввод количества;
  - автоматический расчет «Итого позиции».

### Инвестиции: рыночные активы (stocks/crypto)

`Investment` остается единой сущностью для всех активов. Для рыночных активов (акции/криптовалюта)
добавлены поля:

- `marketSymbol: String?` — тикер/пара (`AAPL`, `BTCUSD`)
- `marketExchange: String?` — биржа/площадка
- `marketCurrency: String?` — валюта котировки
- `marketQuantity: Double?` — количество инструмента
- `lastKnownUnitPrice: Double?` — последняя известная цена за единицу
- `averagePurchaseUnitPrice: Double?` — средняя цена покупки за единицу (cost basis)
- `totalPurchaseCost: Double?` — суммарная стоимость покупки текущей позиции
- `lastKnownPriceUpdatedAt: Date?` — время последнего обновления цены
- `marketProviderRaw: String?` — идентификатор источника цены (например, `market-backend`)

Вычисляемые свойства:

- `isMarketPriced` — актив относится к `stocks` или `crypto`
- `positionTotal` — `marketQuantity * lastKnownUnitPrice`

Правило расчета:

- при наличии `quantity + unitPrice` итог позиции пересчитывается в `Investment.amount`;
- при операции покупки средняя цена покупки пересчитывается как взвешенная средняя;
- при продаже уменьшается `marketQuantity` и пропорционально уменьшается `totalPurchaseCost`;
- `amount` остается базовым числом для текущих итогов, динамики и конвертации валют.

Offline-first поведение:

- если цена недоступна (нет сети/ошибка API), сохранение актива не блокируется;
- `lastKnownUnitPrice` может остаться `nil`, а UI показывает `—` для цены/итога.
- Локальный каталог поиска включает расширенный набор глобальных blue-chip тикеров и ETF по США, Европе,
  Великобритании, Японии, Корее, Тайваню, Гонконгу, Индии, Бразилии, Ближнему Востоку и MOEX:
  даже если backend не вернул котировку, пользователь все равно может выбрать инструмент и вручную
  задать цену/среднюю цену покупки.

### Массовый импорт акций

- В настройках финансов доступен массовый импорт акций из текста или скриншотов.
- Для OCR используется `Vision` в режиме `accurate`, без language correction, с языками:
  `en-US`, `ru-RU`, `es-ES`, `zh-Hans`, `ar`.
- Поддерживаемые форматы тикеров:
  - `NASDAQ: AAPL`, `NYSE-AAPL`;
  - `AAPL.US`, `SBER.MOEX`;
  - одиночный токен `AAPL` / `MSFT7` с фильтрацией шумовых слов.
- `quantity` и `buyPrice` ищутся в текущей и соседних строках (`±1`), поддерживаются шаблоны
  `12 шт по 76.01`, `12 @ 76.01`, `Qty 12 / Price 76.01`.
- Для совпадений сначала используется локальный каталог уже известных stock-инструментов,
  затем remote search через backend market API (до 30 уникальных тикеров за импорт), после чего выполняется рематч.
- В импорт попадают только строки с валидным инструментом, `quantity > 0` и распарсенным `buyPrice`
  (значение `0` допустимо).
- Дубликаты внутри импорта склеиваются по ключу `market|ticker`:
  `quantity` суммируется, `buyPrice` берется из первой валидной строки.
- Сохраняемая позиция всегда нормализуется в `USD`:
  - `Investment.currency = USD`;
  - `Investment.marketCurrency = USD`;
  - `Investment.marketSymbol = MARKET:TICKER`, если рынок известен;
  - `Investment.amount = quantity * currentPrice`, fallback `quantity * buyPrice`.
- Для запроса котировок legacy-символы из импорта дополнительно нормализуются:
  - `US:SPY` -> `SPY.US`;
  - `NASDAQ:AAPL` -> `AAPL`.
- В превью массового импорта header показывает только тикер, а имя инструмента выводится отдельной строкой.
- Каждую строку в превью можно удалить до сохранения; если включен merge дублей, удаление убирает весь
  объединенный блок, а не только первую исходную строку.
- Если такая stock-позиция уже существует в активных инвестициях, импорт не создает дубль, а
  увеличивает существующую позицию и обновляет cost basis.

Кэшфлоу-история:

- для обычного ручного изменения суммы сохраняется `CashflowTransaction.balanceAdjustment`;
- для market-обновлений (stocks/crypto) обновление `amount` и market-полей выполняется без создания
  `CashflowTransaction`, чтобы не засорять историю автообновлениями цены.
- settlement-транзакции market buy/sell, которые двигают деньги между картой/счётом и активом,
  сохраняются в истории для аудита баланса, но помечаются как `affectsCashflowTotals = false` и не
  попадают в доходы/расходы `Cashflow`.

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
    var usesManualAccountOrdering: Bool
    var displayCurrency: String?
    @Relationship var accounts: [FinanceAccount]?
}
```

**Поля:**
- `name` — название группы
- `colorHex` — цвет группы в hex, например "#FF5733"
- `createdAt` — дата создания
- `updatedAt` — дата обновления
- `order` — ручной порядок групп в списке
- `usesManualAccountOrdering` — включён ли ручной порядок счетов внутри группы
- `displayCurrency` — валюта отображения (опционально)
- `accounts` — связанные счета (`@Relationship(deleteRule: .nullify)`)

**Вычисляемые свойства:**
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
    var order: Int
}
```

**Поля:**
- `accountTypeRaw` — тип счета: `card`, `credit`, `investment`
- `accountID` — ID счета (cardUniqueID / creditUniqueID / investmentUniqueID)
- `group` — ссылка на группу
- `createdAt` — дата создания
- `updatedAt` — дата обновления
- `order` — ручной порядок внутри группы

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
            if group1.order != group2.order {
                return group1.order < group2.order
            }
            return group1.createdAt < group2.createdAt
        }
    }
}
```

По умолчанию счета внутри группы сортируются по сумме по убыванию. После первого ручного drag-and-drop группа переключается на сохранённый пользовательский порядок.

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

### Стартовый warmup финансовых API-данных

Чтобы экран финансов и динамика открывались без ожидания первого запроса, при запуске приложения
используется `FinanceStartupWarmupUseCase`:

- use case запускает `FinanceViewModel.warmupRemoteDataForStartup()`;
- прогрев подтягивает валютные курсы и рыночные цены акций в мягком режиме (без `force`);
- частота ограничена cooldown `FinanceStartupWarmupUseCase.minimumWarmupInterval` (сейчас 3 часа);
- timestamp последнего прогона хранится в `UserDefaults` по ключу `finance.startup_warmup.last_run_at`.

Ручное обновление из UI (`refresh_quotes`/`refresh_stocks`) остается принудительным (`force`).

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

### Кастомные категории в операции кэшфлоу

- Для доходов и расходов поддержаны пользовательские категории (`CashflowCustomCategory`).
- Тип категории хранится в `kindRaw` (`income`/`expense`), а связь в транзакции хранится через raw-ключ:
  `CashflowTransaction.incomeCategoryRaw` / `expenseCategoryRaw`.
- Для пользовательских категорий используется префикс `custom:` + `categoryID`.
- При удалении пользовательской категории связанные транзакции безопасно мигрируют в системную категорию `other`.
- При переименовании в имя системной категории выполняется merge: транзакции мигрируют в системную категорию, пользовательская удаляется.
- Для системных категорий поддержаны override-настройки (`CashflowSystemCategoryOverride`): можно менять имя/иконку и скрывать категорию из списка выбора.
- Системные расходные категории описываются через единый `ExpenseCategoryCatalog`: у каждой категории есть стабильный key, UI-имя, и alias-слой для массового импорта и распознавания.
- Скрытая системная категория не считается удаленной: если она встречается в ручной операции или массовом импорте со скриншота, она автоматически возвращается в общий список.
- Удаление системной категории работает как soft-delete: категория скрывается в UI, а связанные транзакции мигрируют в `other`.
- Fallback-категория `other` не удаляется, но поддерживает редактирование имени и иконки.

### Ежемесячный автоповтор доходов/расходов

- Для `CashflowTransaction` добавлены поля:
  - `recurrenceRuleRaw` (`none`/`monthly`);
  - `recurrenceSeriesID` (ID серии автоповтора).
- Шаблоном серии считается транзакция с `recurrenceRuleRaw != none`.
- Автосозданные операции хранят `recurrenceSeriesID` той же серии, но всегда имеют `recurrenceRuleRaw = none`.
- При загрузке данных `CashflowViewModel` достраивает пропущенные месяцы до текущей даты:
  - защита от дублей по `recurrenceSeriesID` + месяц;
  - для 29/30/31 числа используется кламп в последний день месяца.
- Шаблоны автоповтора (`recurrenceRuleRaw != none`) не списывают баланс карты в момент создания:
  - списание/зачисление происходит только для автосгенерированных фактических операций за наступившие даты.

### Запланированные одноразовые операции

- Одноразовая операция с датой в будущем считается запланированной.
- В операции есть тумблер автосписания по дате:
  - включен: операция автоматически меняет баланс в дату операции;
  - выключен: операция остаётся полностью ручной (только план/история).
- Запланированные операции не изменяют текущий баланс карты в момент создания/редактирования.
- Для запланированных и регулярных операций автоматически ставятся локальные напоминания (горизонт планирования до 45 дней).

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
