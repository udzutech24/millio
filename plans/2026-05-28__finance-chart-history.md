# План: Finance Chart History — корректная история портфеля

**Статус:** НЕ НАЧАТ  
**Создан:** 2026-05-28  
**Размер:** L  
**Бранч:** `feature/finance-chart-history`

---

## Root cause (итог анализа)

**Bug 1 — Reconcile слишком широкий** (`FinanceDynamicsViewModel`, ~стр. 1857–1878)

`date.addingTimeInterval(1) >= liveStateEffectiveDate`, где `liveStateEffectiveDate = max(lastTrackedCardChangeDate, card.updatedAt)`. При архивировании счёта `updatedAt = now` → reconcile применяется ко всем сегодняшним точкам → аномальный скачок.

**Trigger:** пользователь заархивировал счёт → `card.updatedAt = now` → все точки дня «снэпятся» к live-балансу, хотя transaction replay без reconcile даёт корректные исторические значения.

**Системная проблема:** `calculateBalanceAtDate` — гибридная функция (replay + reconcile + conversion). Reconcile компенсирует неполную историю (ручная правка баланса без balanceAdjustment), но делает это неточно по дате. При масштабировании функция становится ненадёжной и медленной.

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
