# Account Balance Snapshots — план реализации

**Статус:** РЕАЛИЗОВАН  
**Дата:** 2026-06-13  
**Slug:** account-balance-snapshots

## Зачем

Пользователь хочет видеть историю баланса по каждому счёту (дни, месяцы, год).
Сейчас есть только `DashboardBalanceHistoryStore` — снапшот ОБЩЕГО баланса (35 дней, UserDefaults).
Нужен per-account snapshot за 365 дней с UI в виде sparkline + full-screen chart.

## Что меняем

| # | Файл | Что |
|---|------|-----|
| 1 | `AccountBalanceHistoryStore.swift` (новый) | JSON-файл в Application Support, 365 дней × N счетов |
| 2 | `FinanceTotalsService.swift` | + `calculateAllAccountBalances() async -> [String: (Double, String)]` |
| 3 | `AccountBalanceSnapshotService.swift` (новый) | Фоновый сервис, дебаунс по дате |
| 4 | `FinanceViewModel.swift` | Вызов snapshotService после `computeDashboardSparkline()` |
| 5 | `AccountBalanceChartView.swift` (новый) | SwiftUI + Swift Charts, период 7д/1м/3м/1г, empty state |
| 6 | `FinanceRows.swift` | Sparkline под балансом + tap → full chart sheet |

## Фазы

- [x] Phase 1: Research (TotalsService, DashboardBalanceHistoryStore, FinanceAccountRow)
- [x] Phase 2: AccountBalanceHistoryStore + план файл
- [x] Phase 3: calculateAllAccountBalances в TotalsService
- [x] Phase 4: AccountBalanceSnapshotService + интеграция в FinanceViewModel
- [x] Phase 5: AccountBalanceChartView (sparkline + full screen)
- [x] Phase 6: Встройка в FinanceAccountRow
- [x] Phase 7: Сборка — BUILD SUCCEEDED, 0 ошибок

## Acceptance criteria

- [ ] Снапшот пишется 1 раз в сутки для каждого активного счёта
- [ ] История хранится до 365 дней, старые удаляются
- [ ] Chart показывает линию баланса с периодами 7д / 1м / 3м / 1г
- [ ] Empty state при < 2 точках (текст "накапливаем историю")
- [ ] Периоды без данных дизейблятся
- [ ] Sparkline видна в строке счёта (FinanceAccountRow)
- [ ] Tap → full-screen chart sheet
- [ ] Удалённый и пересозданный счёт — история осиротевших записей не растёт (cleanup при старте)
- [ ] Смена currency счёта → silent reset истории (как в DashboardBalanceHistoryStore)
- [ ] Нет лагов в calculateTotalAmountAsync (snapshot — в фоне)

## Красные флаги из bulletproof

- **F1** (хранилище) — JSON в Documents, не UserDefaults ✅
- **F2** (per-account API) — отдельный public метод в TotalsService ✅
- **F3** (критический путь) — SnapshotService вызывается Task { } off critical path ✅
