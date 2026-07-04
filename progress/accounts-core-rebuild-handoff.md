# Handoff: перестройка ядра счетов — фазы 0–6a РЕАЛИЗОВАНЫ

**Дата:** 2026-07-04 (обновлён после автономной сессии) · **Было:** старт реализации · **Стало:** фазы 0–5 + 6a готовы

## Состояние
- Ветка **`feature/accounts-core`** (от develop), НЕ мержено, НЕ запушено — ждёт команды владельца.
- Коммиты: 09e0819 (Ф0 каркас) · 155b150/625a015 (Ф1a сервисы+UI+сид) · 5a719cc (Ф1b Cashflow→события) ·
  5864f79 (Ф2 кредит/долг) · 9642fdc (Ф3 вклад+налог) · ca39904 (Ф4 рынок/активы) · 473ec43 (Ф5 архив) ·
  a895155 (Ф6a пресеты/read-only) · 37a774b (AC10 курсы append-only) + тест-фиксы ff7014f/b41d02a.
- `feature/dynamics-chart-fix` — fallback, не тронута.
- Полный итог + аудит AC1–AC15 + открытые хвосты: **план, раздел 8** (`plans/2026-07-04__accounts-core-rebuild-plan.md`).
- Известные падения тестов и flaky-класс: `progress/accounts-core-baseline-failures.md`.

## Что построено (кратко)
`millio/Core/AccountsCore/` — Account/AccountEvent/AccountGroup/AccountDailySnapshot (схема V4),
AccountBalanceEngine (6 движков, детерминизм, redenomination), AccountsCoreService (единственная
точка записи), AccountSnapshotRebuilder (@ModelActor, инкрементальный кэш), AccountsTotalsService
(totalAt/seriesBetween, курс на дату точки), DepositInterestScheduler, DepositTaxCalculator,
AccountMarketPriceService + HistoricalAssetPrice (append-only цены), AccountArchivePolicy, сид-полигон
(11 счетов, DEBUG-кнопка в AdminStatsDebugView). UI: AccountDetailView (+sheets), ArchivedAccountsView,
мосты AccountsCoreAdditionBridge / AccountsCoreCashflowBridge. Все 11 пресетов добавления создают
счета нового ядра. Grep-гейт: `scripts/check-balance-mutations.sh`.

## Следующие шаги (по приоритету)
1. Дождаться фикса регрессии testIncomeBudgetSummary… (бисект был запущен; см. последние коммиты ветки).
2. **Решение владельца по 6b** — физический снос Card/Credit/Investment/FinanceAccount (~90 файлов,
   backup-реестр, схема V5). До решения легаси живёт read-only.
3. Ручная проверка на симуляторе: сид → Accounts/Analytics/Dashboard/Cashflow (сверка чисел),
   затем `/stress-test` UI-флоу перед мержем в develop.
4. Хвосты: StockBulkImport на ядро, UI редоминации, тест AC14, налог для валютных вкладов,
   пикеры Quick Entry/Bulk Import, LanguageManager-гонки в тестах.

## Правила (без изменений)
Bulletproof — только через суб-агента; не пушить/не мержить без запроса; симулятор iPhone 17 Pro;
guard phrase для кода. Гейт тестов: «не хуже baseline» по файлу baseline-failures.
