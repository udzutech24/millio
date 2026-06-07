# Spec: Finance Balance Contract

**Date:** 2026-06-07
**Stage:** 2 / Spec
**Research:** [`../.business/история/2026-06-06-finance-accounts-cache-history-research.md`](../.business/история/2026-06-06-finance-accounts-cache-history-research.md)
**Связанный план:** [`plans/2026-05-28__finance-chart-history.md`](../plans/2026-05-28__finance-chart-history.md) — scope-фикс Dynamics входит в Phase 5 этого контракта

## Problem

У финансового модуля нет единого контракта «какие счета входят в расчёт и с каким смыслом». Каждый экран строит свои данные через свой scope, поэтому:

1. **Новый счёт добавлен в БД, но визуально не появляется.** `addAccountToGroup()` после `save()` вызывает `onLoadGroups()`, но не `onLoadAccounts()`. `getAccountInfo()` читает `cardByID/creditByID/investmentByID` из устаревшего кэша → resolver возвращает nil → счёт скрыт до следующего перехода/перезапуска.

2. **Удаление группы физически уничтожает историю.** `deleteGroup()` вызывает `onArchiveUnderlying()` (архивирует Card/Credit/Investment) и сразу `modelContext.delete(account)` — физически удаляет `FinanceAccount` links. Без links historical replay не может восстановить принадлежность транзакций к группам/счетам.

3. **Restore переписывает прошлое.** `restoreArchivedAccountToGroup()` сбрасывает `archivedAt = nil`. `FinanceDynamicsViewModel` использует `archivedAt` как единственную границу жизненного цикла → после restore интервал «счёт был архивирован» стирается из истории.

4. **`cardsUpdated` публикуется по балансному условию, а не по факту изменения списка.** `CashflowPersistenceService.shouldApplyCardBalanceImmediately()` возвращает false для future/recurring транзакций → `affectedAccountEvents()` возвращает [] → UI cashflow не перезагружается. Фикс «публиковать всегда» — неверен: событие балансное, а не структурное.

5. **Нет единого scope-контракта.** Dashboard total, Dynamics chart, Dynamics breakdown, dashboard sparkline и cashflow asset delta считают через разные фильтры, разные источники, разные курсы.

## Goal

Ввести явный Finance Balance Contract — единый набор scope'ов с чёткими правилами фильтрации — и устранить четыре конкретных поломки, которые из его отсутствия вытекают.

## Scope

- Определить пять scope'ов как явный enum/namespace в коде: `currentVisible`, `historicalAsOf(date)`, `historicalInterval(from:to)`, `dashboardSnapshot`, `cashflowContribution`
- Исправить `addAccountToGroup()`: добавить `onLoadAccounts()` после save, до `onLoadGroups()`
- Исправить `deleteGroup()`: не удалять `FinanceAccount` links физически — архивировать underlying, link оставлять (или переносить в скрытую системную группу)
- Исправить lifecycle history: ввести `FinanceAccountLifecycleEvent` (archived / restored с датами), хранить историю событий вместо одного nullable `archivedAt`
- Разделить события в `CashflowPersistenceService`: `transactionsUpdated` (всегда после изменения транзакций), `cardsUpdated`/`investmentsUpdated` (только при изменении модели счёта/актива)
- Привести `FinanceDynamicsViewModel` к scope-контракту: chart series → `historicalAsOf`, header/breakdown → `currentVisible`
- Исправить тест `deleteGroup → links.isEmpty`: он защищает плохое поведение; заменить на `deleteGroup → links preserved, underlying archived`

## Non-Goals

- Иммутабельные `PortfolioSnapshot` (Вариант B из `finance-chart-history.md`) — это отдельная долгосрочная задача
- Миграция SwiftData схемы для lifecycle events если потребует слишком сложной миграции (фоллбэк — хранить в отдельной не-миграционной структуре)
- Изменение логики CloudKit backup/restore
- Любые UI-изменения помимо того, что необходимо для отображения корректных данных

## Acceptance Criteria

- [ ] AC1: После `addAccountToGroup()` счёт немедленно виден в `visibleGroupsForList()` и `orderedAccounts` — без перехода/перезапуска
- [ ] AC2: После `deleteGroup()` `FinanceAccount` links для счетов группы сохраняются (underlying archived, link — нет); тест подтверждает
- [ ] AC3: После archive → restore счёт НЕ «притворяется», что никогда не был архивирован — lifecycle events сохраняют интервал
- [ ] AC4: `transactionsUpdated` публикуется при любом изменении транзакции; `cardsUpdated` публикуется только при структурном изменении счёта
- [ ] AC5: FinanceDynamicsViewModel chart series использует `historicalAsOf` scope (включает archived); header/breakdown — `currentVisible` scope
- [ ] AC6: Все существующие тесты зелёные; тест `deleteGroup → links.isEmpty` заменён на корректный

## Constraints

- **Стек:** Swift · SwiftData · XCTest · Swift Concurrency
- **Совместимость:** Не ломать CloudKit backup/restore
- **Миграция:** Если `FinanceAccountLifecycleEvent` требует SchemaVersion bump — добавить V4 по образцу `AppSchemaVersions.swift`
- **Контекст:** `CashflowViewModel` ~4598 строк — читать только по конкретным символам

## Edge Cases

- Счёт в нескольких группах одновременно (если это допустимо) — links при удалении одной группы не затрагивают другую
- Restore счёта в другую группу (не ту, откуда архивировали) — lifecycle event должен фиксировать целевую группу при restore
- Группа удалена, underlying archived, потом Card физически удалён пользователем — orphaned link нужно обрабатывать без краша
- `transactionsUpdated` при массовом импорте — не публиковать N событий, батчить

## Open Questions

- Где хранить `FinanceAccountLifecycleEvent`: новая SwiftData-модель (требует миграции) vs отдельный UserDefaults/JSON store (без миграции, но вне основной БД)?
- Нужна ли скрытая системная группа для orphaned links при deleteGroup, или достаточно `group = nil` на link?
