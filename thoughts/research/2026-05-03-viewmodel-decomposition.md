# Research: Декомпозиция CashflowViewModel и FinanceViewModel

**Дата:** 2026-05-03
**Файлы исследования:**
- `millio/UI/Services/Cashflow/CashflowViewModel.swift` — 4598 строк
- `millio/UI/Services/Finances/FinanceViewModel.swift` — 2980 строк

---

## CashflowViewModel (4598 строк)

### Структура файла

Файл содержит не только сам класс, но и крупный блок вспомогательных типов (~445 строк до начала класса):

| Диапазон строк | Содержимое |
|---|---|
| 1–87 | Вспомогательные enum/struct: `CashflowScheduledEntry`, `ConversionError`, `CashflowBalanceUpdateError`, `CashflowAffectedAccountEvent` |
| 88–410 | `CashflowState` (struct ~320 строк) — весь Published-стейт |
| 411–444 | `CashflowAction` enum |
| 445–4598 | `CashflowViewModel` class (~4150 строк) |

### Группы методов внутри класса

| Группа | Примерный диапазон | Примерно строк | Зависимости |
|---|---|---|---|
| **Инициализация и подписки** | 471–901 | ~430 | `SettingsManager`, `EventBus`, `NotificationManager`, `HistoricalRateStore` |
| **Фильтрация и история** | 902–1103 | ~200 | `CashflowHistoryQuery`, `state.filteredTransactions` |
| **Аналитика / агрегация (ChartData)** | 1104–1767 | ~660 | `HistoricalRateStore`, `CurrencyRateService`, `BudgetPlan`, `BudgetCategoryLimit` |
| **Scheduled/Recurring транзакции** | 1768–2034 | ~270 | `CashflowTransaction.isRecurringTemplate`, `NotificationManager` |
| **Категории (CRUD + поиск + пины)** | 2035–3000 | ~965 | `CashflowCustomCategory`, `CashflowSystemCategoryOverride`, `CashflowCategoryPinPrefs`, `BudgetCategoryLimit` |
| **Валютная конвертация** | 3334–3410 | ~80 | `HistoricalRateStore`, `CurrencyRateService` |
| **Балансовые операции / CRUD транзакций** | 3410–3730 | ~320 | `Card`, `Investment`, `CashflowTransaction`, `HistoricalRateStore` |
| **Persistence (persistTransaction / updateTransactionAsync / deleteTransactionAsync)** | 3730–4050 | ~320 | Полный граф Card + Investment + CashflowTransaction |
| **Import/BulkExpense вспомогательные методы** | 1600–1770 | ~170 | `CashflowBulkExpenseMerchantCategoryPrefs` |
| **Миграция данных** | 4012–4100 | ~90 | SwiftData `FetchDescriptor`, `BudgetCategoryLimit` |
| **Прочее (helper функции)** | 4050–4598 | ~550 | Разные утилиты, deduplicate логика |

### Предлагаемые дочерние VM/Services

| Модуль | Ответственность | Примерно строк | Изоляция |
|---|---|---|---|
| `CashflowCategoryService` | CRUD кастомных категорий, системные переопределения, поиск, пины, bulk-миграция транзакций при удалении категории | ~965 | Высокая — зависит только от `ModelContext`, `CashflowCategoryPinPrefs`, `BudgetCategoryLimit` |
| `CashflowScheduledService` | Recurring templates, planned one-time, due auto-apply, scheduling | ~270 | Средняя — нужен `NotificationManager` + `ModelContext` |
| `CashflowAnalyticsService` | Расчёт ChartData (totalIncome/totalExpense, breakdown, chartPoints), assets snapshot | ~660 | Средняя — нужны `HistoricalRateStore` + `CurrencyRateService` + период из стейта |
| `CashflowHistoryService` | Фильтрация истории по query (typeFilter, searchText, dateRange, cardID, categoryRaw) | ~200 | Высокая — чистая функция поверх `[CashflowTransaction]` |
| `CashflowPersistenceService` | CRUD транзакций (create/update/delete + балансовые эффекты) | ~640 | Низкая (core) — связана со всем |
| `CashflowCurrencyService` | `convertAmountForTransaction`, `suggestedTransferExchangeInfo`, `markEstimatedRateWarning` | ~80 | Высокая — чистый async helper поверх `HistoricalRateStore` + `CurrencyRateService` |

**Остаётся в `CashflowViewModel`:** handle(_ action), loadTransactions, loadCards, subscribeToFinanceEvents, orchestration.

---

## FinanceViewModel (2980 строк)

### Структура файла

| Диапазон строк | Содержимое |
|---|---|
| 1–230 | `FinanceState` struct (~215 строк) |
| 231–291 | `FinanceAction` enum |
| 292–2980 | `FinanceViewModel` class (~2690 строк) |

### Группы методов внутри класса

| Группа | Примерный диапазон | Примерно строк | Зависимости |
|---|---|---|---|
| **Инициализация и фоновые задачи** | 350–596 | ~250 | `SettingsManager`, `EventBus`, `CurrencyRateService` |
| **CRUD групп** | 664–800, 2321–2460 | ~280 | `FinanceGroup`, `FinanceSystemGroups`, `ModelContext` |
| **CRUD счетов (card/credit/investment)** | 2466–2740 | ~275 | `Card`, `Credit`, `Investment`, `CardManager`, `CreditManager`, `InvestmentManager` |
| **Архивация и восстановление счетов** | 2516–2612 | ~100 | Card/Credit/Investment, EventBus |
| **Загрузка и нормализация** | 684–1050 | ~370 | SwiftData FetchDescriptor + `AssetCatalogStore` + кэши по ID |
| **Тотальные суммы и конвертация** | 1050–1260 | ~210 | `CurrencyRateService`, `CardSnapshotFactory` |
| **Котировки акций (market data)** | 1970–2320 | ~350 | `MarketDataClientProtocol`, `ProviderInstrumentResolver`, `AssetCatalogStore` |
| **Инвестиционные ордера (buy/sell)** | 1694–1970 | ~280 | `Investment`, `CashflowTransaction`, `EventBus` |
| **Savings Goal** | 323–348, 579–600, 632–662 | ~100 | `UserDefaults`, `CurrencyRateService` |
| **UI-хелперы (display names, snapshots, labels)** | 1252–1500 | ~250 | `Card`, `Credit`, `Investment`, `CardSnapshotFactory` |
| **Динамика (charts)** — живёт в FinanceDynamicsViewModel | отдельный файл | — | — |

### Предлагаемые дочерние VM/Services

| Модуль | Ответственность | Примерно строк | Изоляция |
|---|---|---|---|
| `FinanceGroupService` | CRUD групп, порядок, rename, удаление с архивацией | ~280 | Высокая — только `FinanceGroup`, `FinanceSystemGroups`, `ModelContext` |
| `FinanceAccountService` | Add/remove/restore/delete счетов, нормализация orphan-ссылок | ~750 | Средняя — зависит от Card/Credit/Investment + `CardManager` |
| `FinanceMarketDataService` | Refresh stock quotes, обработка ошибок по символам | ~350 | Высокая — только `MarketDataClientProtocol` + `Investment` |
| `FinanceInvestmentOrderService` | Buy/sell ордера, stampFrozenRate, settlement, создание транзакций | ~280 | Средняя — нужны Card + Investment + CashflowTransaction |
| `FinanceSavingsGoalService` | Enabled/amount/currency + конвертация при смене валюты | ~100 | Высокая — только `UserDefaults` + `CurrencyRateService` |
| `FinanceTotalsService` | calculateTotalAmountAsync, calculateGroupTotal, currency warnings | ~210 | Средняя — нужен `CurrencyRateService` + state.groups |

**Остаётся в `FinanceViewModel`:** handle(_ action), loadGroups/loadAccounts, subscribeToFinanceEvents, orchestration.

---

## Порядок декомпозиции (по риску — от низкого к высокому)

| # | Шаг | Файл | Размер | Риск |
|---|---|---|---|---|
| 1 | `CashflowHistoryService` | CashflowViewModel | ~200 строк | Минимальный — чистая фильтрация, нет внешних сервисов |
| 2 | `CashflowCurrencyService` | CashflowViewModel | ~80 строк | Минимальный — async helper, нет стейта |
| 3 | `FinanceSavingsGoalService` | FinanceViewModel | ~100 строк | Минимальный — изолированный UserDefaults + CurrencyRateService |
| 4 | `CashflowCategoryService` | CashflowViewModel | ~965 строк | Низкий — зависит только от ModelContext, нет связи с балансом |
| 5 | `FinanceGroupService` | FinanceViewModel | ~280 строк | Низкий — изолированный CRUD без балансовых эффектов |
| 6 | `FinanceMarketDataService` | FinanceViewModel | ~350 строк | Низкий — изолированный сетевой слой |
| 7 | `CashflowScheduledService` | CashflowViewModel | ~270 строк | Средний — нужен NotificationManager + доступ к transactions |
| 8 | `FinanceAccountService` | FinanceViewModel | ~750 строк | Средний — зависит от кэшей, CardManager/CreditManager/InvestmentManager |
| 9 | `CashflowAnalyticsService` | CashflowViewModel | ~660 строк | Средний — async, нужен snapshot периода из стейта |
| 10 | `FinanceInvestmentOrderService` | FinanceViewModel | ~280 строк | Средний — создаёт CashflowTransaction, балансовые эффекты |
| 11 | `FinanceTotalsService` | FinanceViewModel | ~210 строк | Высокий — читает state.groups, async конвертация |
| 12 | `CashflowPersistenceService` | CashflowViewModel | ~640 строк | Высокий — балансовые эффекты, cross-модель, undo |

---

## Риски

### Высокосвязанные зоны
- `CashflowPersistenceService` — зависит от Card, Investment, CashflowTransaction, HistoricalRateStore, балансовые эффекты применяются и для scheduled, и для обычных транзакций. Выделять последним.
- `CashflowAnalyticsService` — читает весь `state.transactions` и вызывает `convertAmountForTransaction`. Нужен доступ к диапазону дат из стейта — это граница через замыкание или dependency injection.
- `FinanceTotalsService` — calculateTotalAmountAsync проходит по всем группам и вызывает calculateGroupTotal. Связан с loadGroups и loadAccounts.

### Тесты, которые уже есть (нужно не сломать)
- `CashflowViewModelTests.swift` — 40+ тестов: период, балансы, категории, recurring, currency, events
- `CashflowViewModelPeriodRangeTests.swift` — период/диапазон дат
- `FinanceViewModelTests.swift` — 40+ тестов: группы, счета, ордера, savings goal, конвертация
- `FinanceDynamicsViewModelTests.swift` — отдельная VM, трогать не нужно
- Тесты категорий: `CashflowCategoryUpdateFeedbackPlanTests`, `CashflowCategorySheetBootstrapTests` — зависят от публичного API категорий на VM

### Стратегия разделения без сломанного интерфейса
Каждый Service вводится как зависимость (DI через init или lazy property). ViewModel делегирует в Service, но сохраняет тот же публичный API (`func categoryOptions(...)` и т.д.) — реализации переезжают, сигнатуры остаются.

---

## Примечание о структуре State

`CashflowState` (320 строк) и `FinanceState` (215 строк) — крупные value-type structs со смешанным стейтом. После декомпозиции Services их стейт тоже можно разбить, но это второй этап: сначала выносим логику, потом (если нужно) дробим State.
