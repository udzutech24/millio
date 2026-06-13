# План: Finance Chart History — корректная история портфеля

**Статус:** В РАБОТЕ
**Создан:** 2026-05-28  
**Размер:** L  
**Бранч:** `feature/finance-chart-history`

---

## Root cause (итог анализа, верифицировано 2026-05-31)

### Данные целы — проблема в scope фильтрации

`calculateBalanceAtDate` через replay транзакций корректно восстанавливает прошлые значения и **не зависит от архивации**. История не потеряна.

**Настоящий root cause:** `updateChartDataAsync:1239` фильтрует счета до visible-набора (`filter по isArchived=false`, строка ~935) → для архивного счёта `calculateBalanceAtDate` вообще не вызывается → все исторические точки = 0.

Тот же эффект: `archivedAccountRows` показывает текущий баланс (0 после архивации), а не баланс на момент `archivedAt`.

**Архитектурный конфликт:** история строится из *текущего состояния* счетов, а не хранится иммутабельно. Поэтому «исторический scope (включать архивные)» и «visible scope (только активные для header/breakdown)» — взаимоисключающи в одном проходе.

---

### Развилка: Вариант A vs Вариант B

**Вариант A — быстрый scope-фикс (hotfix, S) — реализован 2026-06-10 в `plans/2026-06-07__finance-balance-contract.md` Phase 5**
- Объём: ~3 строки + тест, 0.5 дня
- `updateChartDataAsync` → `getAccountsForCalculation(scope: .historicalInterval(period))` только для chart series; header/breakdown остаются `.currentVisible`
- Восстановлен тест неизменности истории после архивации в `FinanceDynamicsViewModelTests.swift`: `testAggregatedChartUsesHistoricalAccountsWhileHeaderAndBreakdownStayVisible`
- **Даёт:** прошлые точки графика возвращаются
- **Known issue:** chart с архивным счётом показывает суммарный баланс выше, чем breakdown (visible-only) — «деньги визуально не сходятся». Решается маркировкой архивных строк серым + сноска «счёт в архиве»
- **Не решает:** список архивных всё ещё показывает текущий 0

**Вариант B — иммутабельные снэпшоты (Phase 1, L)**
- Объём: 10+ файлов, новая модель + миграция, ~2-3 недели
- `PortfolioSnapshot` (SwiftData) — пишется при каждом значимом изменении; история = чтение снимков, а не replay
- Решает всё: архивация физически не может изменить прошлый снимок; chart/header/breakdown единый источник → всегда согласованы; архивный показывает баланс на `archivedAt`
- Риск: бэкофилл у живых пользователей

**Рекомендация:** Вариант A сейчас (снять острую боль), Phase 1 — плановая работа. Расхождение chart↔breakdown — явный known issue до перехода на снимки.

---

**Bug 1 (устаревший анализ, для истории)** — Reconcile слишком широкий (`FinanceDynamicsViewModel`, ~стр. 1857–1878): `date.addingTimeInterval(1) >= liveStateEffectiveDate` → при архивации `updatedAt = now` → reconcile на всех точках дня. Этот эффект реален, но вторичен относительно scope-фильтра выше.

---

## Acceptance criteria

| # | Критерий | Фаза |
|---|----------|------|
| AC1 | Исторические точки графика не скачут после архивирования счёта | Phase 0 |
| AC2 | Точка «сегодня» на графике совпадает с дашбордом | Phase 0 |
| AC3 | Архивированные счета включаются в историю до `archivedAt` | Phase 0 подтвердить, Phase 3 гарантировать |
| AC4 | Rebuild истории O(days + transactions + accounts), не O(days × accumulated tx) | Phase 1 |
| AC5 | Снэпшоты иммутабельны, не зависят от текущего состояния счетов | Phase 2 |
| AC6 | Chart корректен для режимов: весь портфель / группа / один счёт | Phase 2 |
| AC7 | Инвалидация при любом изменении источника данных | Phase 3 |
| AC8 | После restore снэпшоты очищаются и пересобираются | Phase 3 |
| AC9 | SchemaV4 migration не теряет данные | Phase 2 |
| AC10 | Cashflow агрегат считается в исторических курсах | Phase 0.5 |

---

## Phase 0 — Hotfix (неделя 1) → TestFlight

**Принцип:** хирургический. Только то, что вызывает видимый баг на скриншоте.

### 0.1 — Fix reconcile condition

**Файл:** `FinanceDynamicsViewModel.swift` (~стр. 1857–1878)

```swift
// БЫЛО
let liveStateEffectiveDate = max(lastTrackedCardChangeDate, card.updatedAt)
if date.addingTimeInterval(1) >= liveStateEffectiveDate {
    let deltaToActual = actualCurrentValue - accountBalance
    if abs(deltaToActual) > 0.01 { accountBalance += deltaToActual }
}

// СТАЛО — reconcile только для точки «сегодня»
if Calendar.current.isDateInToday(date) {
    let deltaToActual = actualCurrentValue - accountBalance
    if abs(deltaToActual) > 0.01 { accountBalance += deltaToActual }
}
```

**Проверить:** аналогичный reconcile-блок есть для Credit и Investment — исправить там же.

**Не трогать:** сам механизм reconcile (компенсирует ручную правку баланса без транзакции) — просто сузить его до today.

**Edge cases:**
- Полночь UTC vs локальное время → `Calendar.current` привязан к устройству, это правильно
- Несколько часовых поясов у разных устройств → снэпшоты локальные, не синхронизируются, проблемы нет

### 0.2 — Live курс для точки «сегодня»

Только если тест докажет расхождение с дашбордом после 0.1. Если после фикса reconcile точки совпадают — 0.2 не нужна.

Проверить: `currencyService.forceRefreshRates()` уже вызывается перед построением today-точки → historical store деградирует на live для today → расхождения может и не быть.

### 0.3 — Тесты Phase 0

- Тест: reconcile не срабатывает для точек вчера и раньше
- Тест: reconcile срабатывает только для точек с `isDateInToday`
- Тест: после архивирования счёта исторические точки до `archivedAt` содержат баланс этого счёта

**Gate:** тесты зелёные → коммит → TestFlight.

### Журнал 2026-05-30 — current visible scope

- [~] Current header переведён на visible-scope набор счетов, что и нижний breakdown.
- [ ] Исправить временный ряд: chart history должен включать архивные счета до `archivedAt`.
- [x] Заменить слишком грубый regression-тест на split-scope контракт: current header совпадает с breakdown, historical series сохраняет архив. (code review FIX #1/#2/#3/#5, тест зелёный)
- [ ] Пройти остальные пункты Phase 0 по reconcile today-only отдельно.

### `[ ]` Phase 0.4: Account lifecycle + split visible/historical scope

**Цель:** новые карты появляются сразу после сохранения, архивирование не
удаляет прошлое из графика.

**Research:** [`thoughts/research/2026-05-30-finance-account-lifecycle-history.md`](../thoughts/research/2026-05-30-finance-account-lifecycle-history.md)

**Файлы:**

- `millio/UI/Services/Finances/FinanceAccountService.swift`
- `millio/UI/Services/Finances/FinanceGroupService.swift`
- `millio/UI/Services/Finances/FinanceDynamicsViewModel.swift`
- `millioTests/UI/Services/Finances/FinanceViewModelTests.swift`
- `millioTests/UI/Services/Finances/FinanceDynamicsViewModelTests.swift`

**Шаги:**

1. `[ ]` TDD: новая карта видна в `FinanceViewModel` сразу после `.addAccountToGroup`, без ручного `.loadAccounts`.
2. `[ ]` После save в `addAccountToGroup()` обновить accounts cache и groups в безопасном порядке.
3. `[ ]` TDD: удаление группы архивирует underlying-счета, но сохраняет `FinanceAccount` links для истории.
4. `[ ]` В `deleteGroup()` не удалять links: отвязать их от удаляемой группы, затем дать cleanup перенести архивные links в системную группу.
5. `[~]` TDD: после архивации historical chart содержит баланс счёта до `archivedAt`, current header совпадает с visible breakdown. (тест `testAggregatedChartAndHeaderMatchVisibleBreakdownAfterArchivingAccount` зелёный; chart history до `archivedAt` — ещё открыт)
6. `[~]` Разделить scope: chart series использует historical accounts, current header/breakdown — visible accounts. (`updateDynamicsBreakdown` переведён на clamped `state.periodStartDate`/`periodEndDate` вместо `getPeriodDates()` — chart и breakdown теперь на одном интервале; полное split-scope разделение не завершено)
7. `[~]` Прогнать `FinanceViewModelTests` и `FinanceDynamicsViewModelTests` на `iPhone 17 Pro Max`. (FinanceDynamicsViewModelTests — TEST SUCCEEDED; FinanceViewModelTests — не прогонялись)

**Self-audit:**

- Новая карта появляется без закрытия/повторного открытия экрана.
- Архивный счёт не влияет на текущий итог после `archivedAt`.
- Архивный счёт влияет на исторические точки до `archivedAt`.
- Удаление группы не уничтожает link, нужный replay.

**Guard phrase для старта:** «Реализуй фазу 0.4 по плану».

---

## Phase 0.5 — Historical rate consistency (неделя 1, отдельный PR)

**Почему отдельно:** cashflow агрегат — другой путь в коде, может расползтись. Не блокирует видимый баг пользователя.

**Задача:** аудит Cashflow aggregate path. Найти `convertAmount` без контекста транзакции → заменить `CurrencyRateService.shared.convert(...)` на `historicalRateStore.getRate(on: periodEndDate)` с fallback на live.

**Передать `periodEndDate`** в метод (дата конца периода).

**Edge cases:**
- Период в будущем → live курс
- Исторических данных нет → fallback live + `estimated = true` в метаданных

**Gate:** тест агрегата использует исторический курс.

---

## Phase 1 — PortfolioSnapshotCalculator (неделя 2)

**Цель:** чистый инкрементальный calculator без SwiftData, без побочных эффектов.

**Ключевой инсайт:** не вызывать `calculateBalanceAtDate(for: date)` в цикле (это O(days × accumulated tx)). Вместо этого — один проход по всем событиям в хронологическом порядке.

```
Сортируем все события один раз → O(n log n)
Идём день за днём, применяем только новые события → O(days + transactions + accounts)
```

### 1.1 — Типы событий

```swift
enum PortfolioEvent: Comparable {
    case transactionAdded(date: Date, accountID: String, amount: Decimal, currency: String)
    case balanceAdjusted(date: Date, accountID: String, newBalance: Decimal, currency: String)
    case accountOpened(date: Date, accountID: String, initialBalance: Decimal, currency: String)
    case accountArchived(date: Date, accountID: String)
    case accountDeleted(date: Date, accountID: String)
    case currencyChanged(date: Date, accountID: String, from: String, to: String)
    case includeInTotalChanged(date: Date, accountID: String, included: Bool)
}
```

### 1.2 — Running state

```swift
struct AccountRunningState {
    let accountID: String
    var nativeBalance: Decimal
    var nativeCurrency: String
    var includeInTotal: Bool
    var archivedAt: Date?
    var groupID: String?
}

struct PortfolioRunningState {
    var accounts: [String: AccountRunningState]
    var currentDate: Date
}
```

### 1.3 — Calculator

```swift
struct PortfolioSnapshotCalculator {
    // Применить одно событие к текущему состоянию
    func apply(event: PortfolioEvent, to state: inout PortfolioRunningState)
    
    // Снэпшот на конец дня из текущего состояния
    func snapshotPayload(
        for day: Date,
        state: PortfolioRunningState,
        rates: RateResolver
    ) -> PortfolioSnapshotPayload
}
```

**`RateResolver`** — протокол, позволяющий подменить в тестах:
```swift
protocol RateResolver {
    func rate(from: String, to: String, on date: Date) -> RateResult
}
```

### 1.4 — Алгоритм rebuild

```swift
func rebuildAll(events: [PortfolioEvent], 
                days: [Date],
                rates: RateResolver) -> [PortfolioSnapshotPayload] {
    let sorted = events.sorted()          // O(n log n), один раз
    var state = PortfolioRunningState()
    var eventIdx = 0
    var results: [PortfolioSnapshotPayload] = []
    
    for day in days {                     // O(days)
        while eventIdx < sorted.count && sorted[eventIdx].date <= day {
            calculator.apply(event: sorted[eventIdx], to: &state)   // O(accounts per event)
            eventIdx += 1
        }
        results.append(calculator.snapshotPayload(for: day, state: state, rates: rates))
    }
    return results
}
```

**Сложность:** O(days + transactions + accounts) — линейная.

### 1.5 — Тесты Phase 1

- Тест: rebuild за 3 года (1095 дней, 10 000 транзакций) выполняется < 3 сек
- Тест: снэпшот на D содержит баланс архивированного счёта, если `archivedAt > D`
- Тест: снэпшот на D не содержит баланс счёта, если `archivedAt < D`
- Тест: rebuild детерминирован — два запуска дают одинаковый результат
- Тест: `RateResolver` mock — изолированный от HistoricalRateStore

---

## Phase 2 — SwiftData PortfolioSnapshot + Migration (неделя 3)

### 2.1 — Модель `PortfolioSnapshot`

```swift
@Model
final class PortfolioSnapshot {
    // Идентификация (уникальный ключ: date + displayCurrency + scopeKey + kind)
    var snapshotDate: Date           // полночь UTC
    var displayCurrency: String      // ISO 4217
    var scopeKey: String             // "all" / "group:<id>" / "account:<id>"
    var snapshotKind: SnapshotKind   // .daily / .weekly / .monthly

    // Данные
    var totalConverted: Decimal
    var accountBreakdownData: Data   // [AccountSnapshotEntry] JSON
    var ratesSnapshotData: Data      // [CurrencyPair: Decimal] JSON

    // Мета
    var isComplete: Bool             // false пока идёт построение
    var isEstimated: Bool            // true если хотя бы один курс — fallback
    var sourceHash: String           // хэш (transactionCount + latestTxDate + accountIDs) для инвалидации
    var schemaVersion: Int           // версия формата accountBreakdownData
    var builtAt: Date
}

enum SnapshotKind: String, Codable {
    case daily, weekly, monthly
}
```

```swift
struct AccountSnapshotEntry: Codable {
    let accountID: String            // стабильный UUID
    let accountType: String          // card / credit / investment
    let nativeBalance: Decimal
    let nativeCurrency: String
    let convertedBalance: Decimal
    let includeInTotal: Bool
    let archivedAt: Date?
    let isEstimated: Bool
    let rateSource: String           // "exact" / "nearest" / "live_fallback"
}
```

**Уникальность:** SwiftData не поддерживает составной unique — в `PortfolioSnapshotService` добавить guard на дубли перед записью.

### 2.2 — Migration AppSchemaV4

```swift
enum AppSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] = [
        // ... существующие модели ...
        PortfolioSnapshot.self
    ]
}

typealias AppSchemaCurrent = AppSchemaV4

// В AppMigrationPlan
static var schemas: [any VersionedSchema.Type] = [
    AppSchemaV1.self, AppSchemaV2.self, AppSchemaV3.self, AppSchemaV4.self
]

// Migration: lightweight (только добавляем таблицу, данных не трогаем)
MigrationStage.lightweight(
    fromVersion: AppSchemaV3.self,
    toVersion: AppSchemaV4.self
)
```

**Migration gates (обязательны):**
- `SchemaConsistencyTests`: все модели из `AppSchemaCurrent.models` имеют одинаковый `versionIdentifier`
- `SchemaMigrationTests`: открыть V3-стор с реальными Finance/Cashflow данными как V4 → данные не потеряны, `PortfolioSnapshot` таблица пуста
- `ModelContainerFactory` обновлён с `AppSchemaV4`

### 2.3 — `PortfolioSnapshotService`

```swift
actor PortfolioSnapshotService {
    func snapshot(for date: Date, scope: SnapshotScope, currency: String) async -> PortfolioSnapshot?
    func buildSnapshot(for date: Date, scope: SnapshotScope, currency: String) async throws -> PortfolioSnapshot
    func invalidate(from date: Date) async
    func invalidateAll() async
}
```

**Снэпшоты — локальный derived cache, не источник истины и не часть backup.**

Обоснование: снэпшоты детерминированы (транзакции + курсы → снэпшот), но `HistoricalRate` может иметь different fallback behavior на разных устройствах или в разные моменты. Экспорт в backup создаёт второй источник истины. После restore → `invalidateAll()` + rebuild — проще и надёжнее.

### 2.4 — `PortfolioSnapshotBuilder` (фоновый)

Использует `PortfolioSnapshotCalculator` из Phase 1 — строго инкрементальный.

```swift
actor PortfolioSnapshotBuilder {
    func rebuildAll() async          // с нуля
    func rebuildFrom(_ date: Date) async  // с даты
    var progress: AsyncStream<BuildProgress>
}
```

**Chunking:** 30 дней за задачу, `await Task.yield()` между chunk'ами → UI не блокируется.

### 2.5 — Chart читает снэпшоты

`FinanceDynamicsViewModel.buildTimeSeriesData()`:
- Точки `date < today` → `PortfolioSnapshotService.snapshot(for: date, scope: currentScope)`
- Снэпшот есть → `totalConverted` (O(1))
- Снэпшота нет → fallback на `calculateBalanceAtDate` (пока builder не закончил)
- Точка `today` → live calculation (AC2)

**Важно:** `calculateBalanceAtDate` для fallback вызывается без reconcile. Reconcile остаётся только для live/today path — в отдельном методе `liveBalance(for account:)`.

### 2.6 — Тесты Phase 2

- Migration тесты (см. 2.2)
- `PortfolioSnapshotServiceTests`: get → nil → build → get → hit
- `PortfolioSnapshotServiceTests`: scope "group:X" не возвращает снэпшот для scope "all"
- `PortfolioSnapshotServiceTests`: дубликат по (date, currency, scope, kind) не создаётся
- `ChartViewModelTests`: для исторических точек вызывается snapshot service, не calculateBalanceAtDate
- `ChartViewModelTests`: для today вызывается live path

---

## Phase 3 — Инвалидация + Restore (неделя 4)

### 3.1 — Полный список триггеров инвалидации

| Событие | Действие |
|---------|---------|
| Создание/редактирование/удаление транзакции на дату D | `invalidate(from: D)` |
| `Card.balance`, `Credit.remainingAmount`, `Investment.amount` изменены | `invalidate(from: updatedDate)` |
| Изменение `includeInTotal` | `invalidateAll()` |
| Архивирование счёта на дату D | `invalidate(from: D)` |
| Разархивирование счёта | `invalidateAll()` |
| Изменение валюты счёта | `invalidateAll()` |
| Изменение `displayCurrency` пользователем | `invalidateAll()` |
| Hard delete счёта (если введём) | `invalidateAll()` |
| Restore из backup | `invalidateAll()` + `rebuildAll()` |
| Изменение источника курсов / custom rate | `invalidateAll()` |

**Реализация:** SwiftData `ModelContext` notifications (`.NSManagedObjectContextDidSave`) → `PortfolioSnapshotService.invalidate(...)`.

**Debounce:** если за 5 секунд пришло несколько инвалидаций → одна перестройка с `min(dates)`.

### 3.2 — Rebuild после restore

В `BackupRestoreService` после успешного restore:
1. `PortfolioSnapshotService.invalidateAll()`
2. `PortfolioSnapshotBuilder.rebuildAll()` в detached Task
3. Прогресс через `AsyncStream<BuildProgress>` → UI показывает индикатор

### 3.3 — Progress UI

При незавершённом rebuild → chart показывает снэпшоты там, где они есть, и fallback (transaction replay) там, где нет. Никакого блокирующего лоадера.

---

## Phase 4 — Единый PortfolioCalculator + Scale (месяц 2)

**После стабилизации Phase 1–3 и наличия реальных метрик.**

### 4.1 — Единый `PortfolioCalculating` протокол

```swift
protocol PortfolioCalculating {
    func totalBalance(at date: Date, scope: SnapshotScope, currency: String) async -> BalanceResult
}
```

Dashboard и Chart-today → `LivePortfolioCalculator` (текущий `FinanceTotalsService`)  
Chart-history → `SnapshotPortfolioCalculator` (читает из PortfolioSnapshot)  
Cashflow aggregate → `SnapshotPortfolioCalculator` для даты конца периода

Один контракт, разные реализации. Устраняет архитектурное расхождение между экранами.

### 4.2 — Compression для старых данных

Только после метрик использования и жалоб на размер БД.

- Данные 1Y+: агрегировать по неделям
- Данные 3Y+: агрегировать по месяцам
- Дневные снэпшоты не удалять → `compressed = true` (нужны для fallback 1D диапазона)

### 4.3 — Pre-warm при старте

`PortfolioSnapshotService.ensureTodaySnapshot()` в background при запуске → к открытию Analytics снэпшот уже есть.

---

## Edge cases и тяжёлые сценарии

| Сценарий | Обработка |
|----------|-----------|
| App killed в момент записи снэпшота | `isComplete = false` → при следующем запуске rebuild этой даты |
| Нет исторических курсов (старый период) | `isEstimated = true` + ближайший курс, `rateSource = "nearest"` |
| 100+ счетов, 10+ лет | Rebuild O(days + tx + accounts) — линейный |
| Ретроактивный импорт транзакций | `invalidate(from: importStartDate)` → rebuild |
| Изменение displayCurrency | `invalidateAll()` → rebuild (курсы другие) |
| Разархивирование счёта | `invalidateAll()` (снэпшоты за всё время неверны) |
| Hard delete (будущее) | Снэпшоты сохраняют AccountSnapshot без живой ссылки на модель — история не теряется |
| Два устройства с разными курсами | Снэпшоты локальные, не синхронизируются — допустимо |
| SwiftData schema mismatch | VersionedSchema + lightweight migration обязательны |
| Timezone change | Снэпшоты в UTC, отображение в локальном времени — проблем нет |
| Backup restore на новом устройстве | Снэпшоты не в backup → rebuild из транзакций после restore |
| Большой rebuild блокирует UI | Task.yield() каждые 30 дней + AsyncStream прогресс |
| Ретроактивное редактирование 1000 транзакций подряд | Debounce 5s + rebuild от min(editedDates) |

---

## Порядок реализации

```
Phase 0:    Hotfix reconcile + тесты
            gate: тесты зелёные → commit → TestFlight

Phase 0.5:  Cashflow historical rate + тесты
            gate: агрегат тест → commit

Phase 1:    PortfolioSnapshotCalculator (pure, без SwiftData)
            gate: rebuild 3Y < 3 сек, детерминирован

Phase 2:    SwiftData PortfolioSnapshot + SchemaV4 migration
            gate: migration тесты (V3→V4 без потери данных)
            + Chart читает снэпшоты
            gate: visual QA 1D/1W/1M/1Y/All во всех режимах

Phase 3:    Инвалидация + restore rebuild + progress UI
            gate: все триггеры покрыты тестами

Phase 4:    PortfolioCalculating протокол + compression
            gate: только после метрик Phase 1–3
```

---

## Журнал изменений

| Дата | Что |
|------|-----|
| 2026-05-28 | v1: план создан |
| 2026-05-28 | v2: полный пересмотр по ревью. Исправлено: O(days×tx) → инкрементальный calculator; строгая модель снэпшота; Cashflow → Phase 0.5; reconcile не удаляется, сужается; полный список триггеров инвалидации; account-level breakdown; снэпшоты — local cache, не backup; explicit migration gates |
| 2026-05-31 | Попытка Phase 0.4 откатана после визуальной регрессии графика. Нельзя просто смешивать historical chart series с visible header/breakdown: перед повторной реализацией нужен доказанный UI-контракт и визуальная проверка графика. |
| 2026-06-01 | Phase 0.4: применены 5 исправлений code review. `updateDynamicsBreakdown` переведён на clamped `state.periodStartDate/periodEndDate` (chart и breakdown на одном интервале). Тест `testAggregatedChartAndHeaderMatchVisibleBreakdownAfterArchivingAccount` усилен (FIX #1 явный `archivedAt`, FIX #2 before-snapshot + assertions >1M, FIX #3 guard на непустой breakdown, FIX #5 порядок state-assignments) — TEST SUCCEEDED. Остаётся: chart history с архивом до `archivedAt`, полный split-scope, прогон FinanceViewModelTests, визуальная проверка графика. |
