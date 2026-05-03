# Spec: Декомпозиция CashflowViewModel и FinanceViewModel

**Date:** 2026-05-03
**Stage:** 2 / Spec
**Research:** [`thoughts/research/2026-05-03-viewmodel-decomposition.md`](../thoughts/research/2026-05-03-viewmodel-decomposition.md)

## Problem

`CashflowViewModel.swift` (4598 строк) и `FinanceViewModel.swift` (2980 строк) нарушают SRP: каждый файл совмещает фильтрацию, аналитику, CRUD, scheduled-логику, управление категориями, балансовые эффекты, market data, инвестиционные ордера. Это:
- делает ревью и дебаг практически невозможными (одно изменение затрагивает непредсказуемые части),
- не даёт тестировать логику в изоляции (нужно поднимать весь VM),
- увеличивает cognitive load при любом новом feature.

## Goal

Разбить оба god-object VM на специализированные Services/VM по принципу Single Responsibility без изменения публичного поведения и без регрессий в тестах.

## Scope

- Выделение `CashflowHistoryService` (фильтрация истории)
- Выделение `CashflowCurrencyService` (async конвертация для транзакций)
- Выделение `CashflowCategoryService` (CRUD категорий, пины, bulk-миграция)
- Выделение `CashflowScheduledService` (recurring templates, planned, due auto-apply)
- Выделение `CashflowAnalyticsService` (ChartData, breakdown, totals)
- Выделение `CashflowPersistenceService` (CRUD транзакций + балансовые эффекты)
- Выделение `FinanceSavingsGoalService` (savings goal + конвертация)
- Выделение `FinanceGroupService` (CRUD групп)
- Выделение `FinanceMarketDataService` (котировки акций)
- Выделение `FinanceInvestmentOrderService` (buy/sell ордера)
- Выделение `FinanceAccountService` (add/remove/restore + нормализация orphan-ссылок)
- Каждый Service вводится через DI в оба ViewModel (сохраняется публичный API)

## Non-Goals

- Разбивка `CashflowState` и `FinanceState` (откладывается на второй этап)
- Изменение публичных сигнатур методов ViewModel (UI-файлы не трогаем)
- Переработка NavigationStack / AppRouter
- Изменения в BackupRestore, CloudKit
- Удаление тестов или переработка тестового harness

## Acceptance Criteria

- [ ] AC1: `CashflowHistoryService` выделен — `historyTransactions(matching:)` и связанные helper-функции перенесены, тесты зелёные
- [ ] AC2: `CashflowCurrencyService` выделен — `convertAmountForTransaction`, `suggestedTransferExchangeInfo`, `markEstimatedRateWarning` перенесены
- [ ] AC3: `FinanceSavingsGoalService` выделен — весь savings goal logic (stored properties + convertIfNeeded) перенесён
- [ ] AC4: `CashflowCategoryService` выделен — `categoryOptions`, `createCustomCategory`, `renameCategory`, `deleteCategory`, `orderedCategoryOptions`, `categoryOption`, pin-методы, bulk-миграция, undo-снэпшоты перенесены
- [ ] AC5: `FinanceGroupService` выделен — `updateGroup`, `deleteGroup`, `moveGroup`, `visibleGroupsForList`, `orderedAccounts` перенесены
- [ ] AC6: `FinanceMarketDataService` выделен — `refreshStockPrices`, batch quote logic, issue tracking перенесены
- [ ] AC7: `CashflowScheduledService` выделен — `recurringTemplates`, `plannedOneTimeTransactions`, `generateRecurringTransactionsIfNeeded`, `applyDuePlannedTransactionsIfNeeded` перенесены
- [ ] AC8: `FinanceAccountService` выделен — `addAccountToGroup`, `removeAccountFromGroup`, `deleteAccountPermanently`, `cleanupInvalidFinanceAccounts`, нормализация orphan-ссылок перенесены
- [ ] AC9: `CashflowAnalyticsService` выделен — `updateChartDataAsync`, assets snapshot, breakdown, chart points перенесены
- [ ] AC10: `FinanceInvestmentOrderService` выделен — `executeInvestmentOrder`, `updateMarketInvestmentDetails`, settlement logic перенесены
- [ ] AC11: `FinanceTotalsService` выделен — `calculateTotalAmountAsync`, `calculateGroupTotal`, currency warnings перенесены
- [ ] AC12: `CashflowPersistenceService` выделен — `persistTransaction`, `updateTransactionAsync`, `deleteTransactionAsync` + балансовые эффекты перенесены
- [ ] AC13: Все существующие тесты (CashflowViewModelTests, FinanceViewModelTests и связанные) зелёные после каждой фазы
- [ ] AC14: Компиляция без ошибок после каждой фазы (каждый PR компилируется отдельно)

## Constraints

- **Стек:** Swift 6, SwiftUI, SwiftData, `@MainActor`, async/await
- **Правило:** каждая фаза = отдельный PR, не ломает компиляцию
- **Тесты:** выносим публичный API — тесты переключаются на тот же публичный интерфейс (через ViewModel или напрямую через Service, если Service публичный)
- **DI:** Services внедряются через init, дефолтные значения = production-синглтоны, тесты — моки

## Edge Cases (предварительно)

- Что если Service async, а ViewModel — @MainActor? Все async вызовы через `Task { @MainActor }` — без изменений.
- Что если тест напрямую зависит от приватных методов VM? Эти методы становятся публичными на Service — нужно обновить только тест-файлы.
- Что с EventBus подписками? Остаются в ViewModel — Services получают callback/async-сигналы через делегата или замыкание.
- Circular dependency? Services не должны знать про ViewModel. Данные передаются параметрами.

## Open Questions

- Где живёт `CashflowState.budgetSnapshot` после выделения `CashflowAnalyticsService`? Либо остаётся в ViewModel (VM читает результат из Service и пишет в state), либо дублируется.
- Нужно ли выделять `CashflowScheduledService` как отдельный `@MainActor` actor? Сейчас логика требует доступа к `modelContext` (MainActor). Предварительно — нет, просто класс с DI.
