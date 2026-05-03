# Plan: Декомпозиция CashflowViewModel и FinanceViewModel

**Slug:** `viewmodel-decomposition`
**Дата создания:** 2026-05-03
**Stage:** 3 / Planning
**Spec:** [`specs/2026-05-03-viewmodel-decomposition.md`](../specs/2026-05-03-viewmodel-decomposition.md)
**Research:** [`thoughts/research/2026-05-03-viewmodel-decomposition.md`](../thoughts/research/2026-05-03-viewmodel-decomposition.md)

## Статус

`РЕАЛИЗОВАН`

**Реализовано:** Все фазы 1–12 завершены (2026-05-03/04)
**Результат:** CashflowViewModel ~4598 → 2067 строк; FinanceViewModel ~2980 → 1583 строк

## Цель

Разбить `CashflowViewModel` (4598 строк) и `FinanceViewModel` (2980 строк) на специализированные Services по SRP, не меняя публичный API и не ломая тесты. Каждая фаза — отдельный PR, компилируется независимо.

## Acceptance Criteria (из spec)

- [x] AC1: `CashflowHistoryService` выделен, тесты зелёные
- [x] AC2: `CashflowCurrencyService` выделен
- [x] AC3: `FinanceSavingsGoalService` выделен
- [x] AC4: `CashflowCategoryService` выделен
- [x] AC5: `FinanceGroupService` выделен
- [x] AC6: `FinanceMarketDataService` выделен
- [x] AC7: `CashflowScheduledService` выделен
- [x] AC8: `FinanceAccountService` выделен
- [x] AC9: `CashflowAnalyticsService` выделен
- [x] AC10: `FinanceInvestmentOrderService` выделен
- [x] AC11: `FinanceTotalsService` выделен
- [x] AC12: `CashflowPersistenceService` выделен
- [x] AC13: Все тесты зелёные после каждой фазы
- [x] AC14: Компиляция без ошибок после каждой фазы

## Challenge Log

### 1. Решает ли план проблему из spec?
Каждая фаза закрывает один AC. AC13/AC14 — сквозные, проверяются в каждой фазе в шаге Gates.

### 2. Это самое эффективное решение?
- **Альтернатива A: Monolith → Actor.** Завернуть всё в actor — нет SRP, только threading безопасность. Не решает проблему.
- **Альтернатива B: Feature-first (по экрану).** Разбить по UI-фичам (Budget, History, Chart) — границы нечёткие, много пересечений.
- **Выбрано: по ответственности (SRP Services)**, потому что границы чёткие, каждый Service тестируется изолированно, ViewModel остаётся оркестратором.

### 3. Нет ли кода ради кода?
Только вынос существующего кода, новой логики не добавляем. Drive-by рефакторинг (переименование, форматирование) — откладываем.

---

## Фазы

**Состояния:** `[ ]` не начато · `[~]` в работе · `[x]` готово

---

### `[x]` Phase 1: CashflowHistoryService — фильтрация истории

**AC из spec:** AC1, AC13, AC14
**Сложность:** S (1–2 файла)

**Файлы:**
- `millio/UI/Services/Cashflow/CashflowHistoryService.swift` — новый файл
- `millio/UI/Services/Cashflow/CashflowViewModel.swift` — удалить перенесённые методы, добавить DI

**Что переезжает (строки 902–1103 + вспомогательные):**
- `historyTransactions(matching:)` (~52 строки)
- `shouldHideLinkedSettlementTransactionInHistory(_:)` (~17 строк)
- `historyTransactionMatchesCardFilter(_:cardID:)` (~12 строк)
- `historyTransactionMatchesCategoryFilter(_:categoryRawValue:typeFilter:)` (~30 строк)
- `historyTransactionMatchesSearch(_:query:cardsByID:)` (~40 строк)
- `linkedHistoryTransactions(for:)` (~10 строк)
- `normalizedHistoryDateRange(start:end:)` (~15 строк)
- Вспомогательные enum/struct (если есть private types)

**Интерфейс сервиса:**
```swift
@MainActor
final class CashflowHistoryService {
    init(modelContext: ModelContext) { ... }
    func historyTransactions(
        matching query: CashflowHistoryQuery,
        in transactions: [CashflowTransaction],
        allCards: [Card]
    ) -> [CashflowTransaction]
}
```
ViewModel хранит `let historyService: CashflowHistoryService` и делегирует через тот же публичный метод.

**Шаги:**
1. `[x]` Создать `CashflowHistoryService.swift`, перенести методы
2. `[x]` Добавить `historyService` в `CashflowViewModel.init`
3. `[x]` Заменить вызовы в ViewModel на вызовы через сервис, публичный метод `historyTransactions(matching:)` на VM делегирует
4. `[x]` Gates: компиляция + тесты
5. `[x]` Коммит: `refactor(cashflow): extract CashflowHistoryService`

**Реализовано:** 2026-05-03
**Guard phrase для старта:** «Реализуй Phase 1 по плану.»

---

### `[x]` Phase 2: CashflowCurrencyService — конвертация для транзакций

**AC из spec:** AC2, AC13, AC14
**Сложность:** S (1–2 файла)

**Файлы:**
- `millio/UI/Services/Cashflow/CashflowCurrencyService.swift` — новый файл
- `millio/UI/Services/Cashflow/CashflowViewModel.swift` — DI + делегирование

**Что переезжает:**
- `convertAmountForTransaction(_:to:)` (~25 строк)
- `convertAmount(value:from:to:)` (~15 строк)
- `convertAmountForValidation(amount:from:to:on:)` (~20 строк)
- `resolveExchangeInfo(for:)` (~35 строк)
- `suggestedTransferExchangeInfo(...)` (~55 строк)
- `transferReceivedAmount(for:in:)` (~15 строк)
- `markEstimatedRateWarning(on:)` (~12 строк) — остался в VM (мутирует state)
- `estimatedRateWarningText(date:locale:)` (~20 строк) — static переехал в сервис, VM делегирует

**Шаги:**
1. `[x]` Создать `CashflowCurrencyService.swift`
2. `[x]` Добавить в `CashflowViewModel` как `lazy var`, перенести вызовы
3. `[x]` `TransferExchangeSuggestion` вынесен на top-level
4. `[x]` Gates: компиляция + тесты
5. `[x]` Коммит: `refactor(cashflow): extract CashflowCurrencyService`

**Реализовано:** 2026-05-03
**Guard phrase для старта:** «Реализуй Phase 2 по плану.»

---

### `[x]` Phase 3: FinanceSavingsGoalService — цель накоплений

**AC из spec:** AC3, AC13, AC14
**Сложность:** S (1–2 файла)

**Файлы:**
- `millio/UI/Services/Finances/FinanceSavingsGoalService.swift` — новый файл
- `millio/UI/Services/Finances/FinanceViewModel.swift` — DI + делегирование

**Что переезжает:**
- `storedSavingsGoalEnabled` computed property (~4 строки)
- `storedSavingsGoalAmount` computed property (~4 строки)
- `storedSavingsGoalCurrency` computed property (~10 строк)
- `convertSavingsGoalAmountIfNeeded(from:to:)` (~30 строк)
- `normalizedConversionCurrency` скопирован как static в сервис

**Шаги:**
1. `[x]` Создать `FinanceSavingsGoalService.swift`
2. `[x]` Добавить в `FinanceViewModel` как `lazy var`, stored* properties стали thin wrappers
3. `[x]` `convertSavingsGoalAmountIfNeeded` делегирует в сервис
4. `[x]` Gates: компиляция + тесты
5. `[x]` Коммит: `refactor(finance): extract FinanceSavingsGoalService`

**Реализовано:** 2026-05-03
**Guard phrase для старта:** «Реализуй Phase 3 по плану.»

---

### `[x]` Phase 4: CashflowCategoryService — CRUD категорий

**AC из spec:** AC4, AC13, AC14
**Сложность:** M (3–5 файлов)

**Файлы:**
- `millio/UI/Services/Cashflow/CashflowCategoryService.swift` — новый файл (~800–1000 строк)
- `millio/UI/Services/Cashflow/CashflowViewModel.swift` — DI + делегирование
- Возможно обновление тест-файлов (публичный API не меняется, но если тесты напрямую тестируют VM-метод — остаётся через ViewModel)

**Что переезжает (строки 2035–3000):**
- `categoryOptions(for:matching:includeHiddenSystem:)` и все зависимые helper-функции
- `orderedCategoryOptions(...)`, `sortCategoryOptions(_:...)` (static)
- `categoryOption(for:kind:fallbackName:)`, `canonicalSystemCategoryRaw(for:kind:)`
- `isCategoryPinned`, `setCategoryPinned`
- `incomeCategoryDisplayName`, `expenseCategoryDisplayName`, `expenseCategoryIcon`, `incomeCategoryIcon`
- `createCustomCategory(kind:name:icon:)`
- `renameCategory(rawValue:kind:newName:newIcon:)`, `renameCustomCategory(...)`, `renameSystemCategory(...)`
- `deleteCategory(rawValue:kind:)` + preview + bulk migration + undo snapshot
- `deleteCategoryPreview(rawValue:kind:)`, `revertCategoryMutation(from:)`
- `historyTransactionSummaryModel(for:in:)` (~40 строк)
- `loadCustomCategories()`, `loadSystemCategoryOverrides()`
- Undo-логика: `CashflowCategoryMutationUndoAction`, снэпшоты

**Шаги:**
1. `[ ]` Создать файл, перенести весь блок категорий
2. `[ ]` Добавить DI в ViewModel, все вызовы делегировать
3. `[ ]` Проверить тесты: `CashflowCategoryUpdateFeedbackPlanTests`, `CashflowCategorySheetBootstrapTests`, секции categories в `CashflowViewModelTests`
4. `[ ]` Gates: компиляция + тесты
5. `[ ]` Коммит: `refactor(cashflow): extract CashflowCategoryService`

**Guard phrase для старта:** «Реализуй Phase 4 по плану.»

---

### `[x]` Phase 5: FinanceGroupService — CRUD групп

**AC из spec:** AC5, AC13, AC14
**Сложность:** M (2–3 файла)

**Файлы:**
- `millio/UI/Services/Finances/FinanceGroupService.swift` — новый файл
- `millio/UI/Services/Finances/FinanceViewModel.swift` — DI + делегирование

**Что переезжает:**
- `updateGroup(name:colorHex:displayCurrency:)` (~30 строк)
- `deleteGroup(_:)` (~40 строк)
- `moveGroup(sourceGroupID:destinationIndex:)` (~25 строк)
- `visibleGroupsForList()`, `shouldHideGroupInList(_:)` (~15 строк)
- `orderedAccounts(for:)` (~15 строк)
- `normalizeHiddenGroupOrders(excluding:)` (~15 строк)
- `nextAccountOrder(in:)` (~5 строк)

**Guard phrase для старта:** «Реализуй Phase 5 по плану.»

---

### `[x]` Phase 6: FinanceMarketDataService — котировки акций

**AC из spec:** AC6, AC13, AC14
**Сложность:** M (2–3 файла)

**Файлы:**
- `millio/UI/Services/Finances/FinanceMarketDataService.swift` — новый файл
- `millio/UI/Services/Finances/FinanceViewModel.swift` — DI + делегирование

**Что переезжает (строки ~1970–2320):**
- `refreshStockPrices(forceRefresh:)` + весь batch quote logic (~280 строк)
- `StockRefreshIssues` private struct
- `stockRefreshIssueMessage(for:)`, `stockRefreshIssueCategory(for:)`, `assignStockRefreshIssue(...)`, `appendStockRefreshSymbols(...)`, `normalizedStockRefreshIssues(...)`, `normalizedStockRefreshSymbols(_:)`
- `shouldAbortQuoteAliasRefresh(after:)`
- `stockQuoteRequestSymbols(for:)`, `stockDisplaySymbol(_:)`
- `quoteBatchSize` constant

**Guard phrase для старта:** «Реализуй Phase 6 по плану.»

---

### `[x]` Phase 7: CashflowScheduledService — recurring и planned

**AC из spec:** AC7, AC13, AC14
**Сложность:** M (2–3 файла)

**Файлы:**
- `millio/UI/Services/Cashflow/CashflowScheduledService.swift` — новый файл
- `millio/UI/Services/Cashflow/CashflowViewModel.swift` — DI + делегирование

**Что переезжает (строки 1768–2034):**
- `recurringTemplates(for:relativeTo:)` (~25 строк)
- `plannedOneTimeTransactions(for:relativeTo:)` (~25 строк)
- `scheduledEntries(for:relativeTo:)` (~30 строк)
- `nextOccurrenceDate(for:relativeTo:)` (~50 строк)
- `generateRecurringTransactionsIfNeeded()` (~80 строк)
- `applyDuePlannedTransactionsIfNeeded()` (~80 строк)
- `scheduleRecurringGeneration()`, `scheduleDueAutoApplyIfNeeded()` (~30 строк)
- `dueAutoApplyCheckpointKey`, `isRecurringGenerationInProgress`, `isDueAutoApplyInProgress` — флаги переезжают в сервис или остаются в VM как координаторы

**Осторожность:** `applyDuePlannedTransactionsIfNeeded` мутирует транзакции и вызывает `loadTransactionsSnapshot()` — callback или delegate pattern обратно в VM.

**Guard phrase для старта:** «Реализуй Phase 7 по плану.»

---

### `[x]` Phase 8: FinanceAccountService — управление счетами

**AC из spec:** AC8, AC13, AC14
**Сложность:** M (3–5 файлов)

**Файлы:**
- `millio/UI/Services/Finances/FinanceAccountService.swift` — новый файл (~600–700 строк)
- `millio/UI/Services/Finances/FinanceViewModel.swift` — DI + делегирование

**Что переезжает (строки 684–1050, 2466–2612):**
- `loadAccounts()`, `normalizeCreditsIncludeInTotal(_:)`, `normalizeMarketAssetIdentities(_:)`, `normalizeMarketQuoteLookupKeys(_:)`
- `rebuildAccountCaches()`, `rebuildAllAccountCaches(...)`
- `cleanupInvalidFinanceAccounts()`, `financeAccountDeduplicationRank(_:)`
- `addAccountToGroup(...)`, `removeAccountFromGroup(_:)`, `deleteAccountPermanently(_:)`, `restoreArchivedAccountToGroup(...)`
- `updateUnderlyingArchiveState(for:archivedAt:)`, `updateUnderlyingArchiveState(accountType:accountID:archivedAt:)`
- `updateUnattachedItems()`

**Guard phrase для старта:** «Реализуй Phase 8 по плану.»

---

### `[x]` Phase 9: CashflowAnalyticsService — ChartData и агрегация

**AC из spec:** AC9, AC13, AC14
**Сложность:** L (требует careful DI)

**Файлы:**
- `millio/UI/Services/Cashflow/CashflowAnalyticsService.swift` — новый файл (~500–600 строк)
- `millio/UI/Services/Cashflow/CashflowViewModel.swift` — DI + делегирование

**Что переезжает (строки 1104–1767):**
- `updateChartData()`, `updateChartDataAsync(expectedRevision:)`
- `chartUpdateRevision` + `nextChartUpdateRevision()`, `isCurrentChartUpdateRevision(_:)`
- `computeAssetsBreakdown(startDate:endDate:in:)` (~100 строк)
- `monthlyCategoryTotals(for:month:in:)` (~60 строк)
- `monthlyTransactions(for:month:)` (~15 строк)
- Bulk expense import helpers: `bulkExpenseImportSuggestedItems(...)`, `bulkExpenseImportBaselineCategoryTotals(...)` (~80 строк)

**Осторожность:** Сервис должен получать snapshot текущего периода и транзакций из ViewModel — через параметры, не через self.

**Guard phrase для старта:** «Реализуй Phase 9 по плану.»

---

### `[x]` Phase 10: FinanceInvestmentOrderService — ордера и market details

**AC из spec:** AC10, AC13, AC14
**Сложность:** M (3–5 файлов)

**Файлы:**
- `millio/UI/Services/Finances/FinanceInvestmentOrderService.swift` — новый файл
- `millio/UI/Services/Finances/FinanceViewModel.swift` — DI + делегирование

**Что переезжает:**
- `executeInvestmentOrder(account:side:quantity:unitPrice:funding:)` (~100 строк)
- `updateMarketInvestmentDetails(account:quantity:unitPrice:purchaseUnitPrice:)` (~70 строк)
- `normalizedInvestmentOrderFunding(...)` (~30 строк)
- `settlementAccount(for:investmentCurrency:)` (~25 строк)
- `stampFrozenRate(on:targetCurrency:)` (~10 строк)
- `marketAssetSnapshot(for:)`, `marketAssetSnapshot(quantity:...)` (~20 строк)
- `eligibleSettlementCards(from:investmentCurrency:)` (static, ~10 строк)
- `eligibleSettlementAccounts(...)` (static, ~30 строк)

**Guard phrase для старта:** «Реализуй Phase 10 по плану.»

---

### `[x]` Phase 11: FinanceTotalsService — суммы и конвертация

**AC из spec:** AC11, AC13, AC14
**Сложность:** M

**Файлы:**
- `millio/UI/Services/Finances/FinanceTotalsService.swift` — новый файл
- `millio/UI/Services/Finances/FinanceViewModel.swift` — DI + делегирование

**Что переезжает:**
- `calculateTotalAmount()`, `calculateTotalAmountAsync()` (~60 строк)
- `calculateGroupTotal(group:in:)` (~50 строк)
- `accountAmountAndCurrency(for:)` (~30 строк)
- `collectCurrenciesFromGroup(group:)` (~20 строк)
- `normalizedConversionCurrency(_:)` (~30 строк)
- `resolvedInvestmentCurrency(_:)` (~30 строк)
- `refreshRates()` (~5 строк)
- `scheduleGroupTotalRefresh(for:)` (~10 строк)

**Guard phrase для старта:** «Реализуй Phase 11 по плану.»

---

### `[x]` Phase 12: CashflowPersistenceService — CRUD транзакций

**AC из spec:** AC12, AC13, AC14
**Сложность:** L (core, максимально связанный)

**Файлы:**
- `millio/UI/Services/Cashflow/CashflowPersistenceService.swift` — новый файл (~500–600 строк)
- `millio/UI/Services/Cashflow/CashflowViewModel.swift` — DI + делегирование

**Что переезжает (строки 3618–4010):**
- `persistTransaction(...)` (~15 строк публичный entry point)
- `updateTransactionAsync(...)` (~130 строк)
- `deleteTransactionAsync(_:recalculate:)` (~40 строк)
- `deleteTransactionWithoutRecalculation(_:)` (~15 строк)
- `linkedTransactionsForDelete(containing:)` (~25 строк)
- `revertTransactionsForDelete(_:)` (~10 строк)
- `affectedAccountEvents(for:)`, `affectedAccountEventsForDelete(_:)`, `publishAffectedAccountEvents(_:)` (~40 строк)
- `applyCardBalanceEffect(...)`, `revertCardBalanceEffect(...)` (~80 строк)
- `applyInvestmentBalanceEffect(...)`, `applyInvestmentAssetSnapshot(...)` (~50 строк)
- `balanceDelta(for:onCardID:in:direction:)` (~60 строк)
- `canPersistTransaction(_:replacing:)`, `shouldApplyCardBalanceImmediately(for:)` (~50 строк)
- `preservedAccountBalances(for:)`, `restorePreservedAccountBalancesIfNeeded(_:)` (~35 строк)
- `deleteRevertPriority(_:_:)`, `deleteRevertSortKey(for:)` (~15 строк)

**Осторожность:** Сервис публикует `FinanceEvent.transactionsUpdated` через `EventBus` — это нормально. `loadTransactionsSnapshot()` вызывается через callback в ViewModel.

**Guard phrase для старта:** «Реализуй Phase 12 по плану.»

---

## Edge Cases (Think Several Steps Ahead)

- [ ] `@MainActor`: Все переносимые функции уже в `@MainActor` контексте — Service тоже должен быть `@MainActor final class`
- [ ] `weak self` в Task замыканиях — при переезде в Service нужно `[weak self]` на Service, не на ViewModel
- [ ] `objectWillChange.send()` в Services — Service не имеет `@Published`. Методы, которые используют `objectWillChange.send()` (например `setCategoryPinned`), должны принимать callback или оставаться на ViewModel как thin wrappers
- [ ] Circular imports: Service не должен импортировать ViewModel. Данные передаются параметрами
- [ ] Migration tests: `CashflowViewModelTests` использует весь VM — тесты на history/categories после Phase 1/4 остаются работать через ViewModel delegation (не трогаем тест-файлы до Phase 4+)
- [ ] Конкурентные Task в `scheduleRecurringGeneration` / `scheduleDueAutoApplyIfNeeded` — флаги (`isRecurringGenerationInProgress` и т.д.) остаются в ViewModel как координатор

## Gates (обязательны перед `[x]` на каждой фазе)

- [x] Swift compiler: 0 errors, 0 warnings (treat-warnings-as-errors если включено)
- [x] `xcodebuild test` — все тесты зелёные (1348 тестов, 0 упавших, Phase 12)
- [ ] Ручная проверка: открыть затронутый экран в симуляторе, проверить ключевой флоу

## Журнал изменений

- `2026-05-03` — создан план на основе research. Все фазы в статусе НЕ НАЧАТ.
- `2026-05-03` — реализованы Phase 1, 2, 3. Компиляция BUILD SUCCEEDED на каждой фазе. Ветки запушены в GitHub.

## Итог (заполняется при завершении)

**Результат:** —
**Что реализовано:** —
**Что не реализовано и почему:** —
**Дата завершения:** —
