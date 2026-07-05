# Handoff: перестройка ядра счетов — фазы 0–6a РЕАЛИЗОВАНЫ

**Дата:** 2026-07-04 (обновлён после сессии сим-проверки, вечер) · **Было:** старт реализации · **Стало:** фазы 0–5 + 6a готовы; сим-проверка частично пройдена, найдены 2 серьёзные проблемы (см. §Сим-проверка)

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
1. **Ночная сессия 2026-07-04→05 (скоуп утверждён владельцем: всё включая B2).**
   План: `plans/2026-07-04__guest-user-scope-race-fix.md`. Статус:
   ✅ Track A (race-фикс) — A1–A4 реализованы (коммиты f17a799…c6c0728), тесты 1583/17 лучше baseline;
   ✅ Track D1 (удаление не обновляло список/тоталы) — оба слоя, коммиты 20d05f6/4ddad7b;
   ✅ Track C (конвертация легаси→ядро, MVP opening balance) — коммит 457f3bb, 17 тестов;
   ✅ B1+B1b (дизайн reconciliation + стресс-тест) — спека specs/2026-07-04-guest-user-reconciliation.md;
   🔄 B2 (реализация reconciliation) — в работе, под-фазы B2a–B2d с коммитом каждая;
   ⏳ чистка кода (без сноса 6b) → финальный полный тест-прогон → утренний отчёт.
   🔴 НОВЫЙ релиз-блокер: new-core модели НЕ в ModelTypeRegistry → CloudKit-бэкап/export их не переносит.
   Ручные проверки утром: runtime login/logout/force-signout, fresh install+iCloud, UI-конвертация легаси.
2. **Решение владельца по 6b** — физический снос Card/Credit/Investment/FinanceAccount (~90 файлов,
   backup-реестр, схема V5). До решения легаси живёт read-only. Строго после Track A–C.
3. Ручная проверка на симуляторе: сид → Accounts/Analytics/Dashboard/Cashflow (сверка чисел),
   затем `/stress-test` UI-флоу перед мержем в develop.
4. Хвосты: StockBulkImport на ядро, UI редоминации, тест AC14, налог для валютных вкладов,
   пикеры Quick Entry/Bulk Import, LanguageManager-гонки в тестах (план §8, хвосты 1–14).

## Сим-проверка 2026-07-04 (вечер) — итоги и находки

Прогон: iPhone 17 Pro (3EC86784), Debug-сборка BUILD SUCCEEDED, сид залит через
DEBUG-кнопку AdminStatsDebugView (12 счетов + маркер, 45 событий в ZACCOUNT/ZACCOUNTEVENT
user-стора — подтверждено sqlite). Тест-гейт: 17 падений, ВСЕ из baseline/flaky-класса
(из baseline 2 прошли, включая починенный testIncomeBudgetSummary… 6cbe610) — «не хуже baseline» ПРОЙДЕН.

**🔴 Находка 1 — UI живёт на guest-сторе после холодного старта (race guest→user).**
Сид записан в `millio_user_ffb…store` (13 ZACCOUNT), но UI (Счета/Дашборд) сид-счета НЕ видит
даже после перезапуска. Причина по коду: `RootTabView.ensureFinanceViewModel()` создаёт
`FinanceViewModel` ОДИН раз (`guard financeViewModel == nil`) из `@Environment(\.modelContext)`;
при холодном старте первым биндится guest-контейнер, auth восстанавливается позже и
`activeModelContainer` меняется на user, но @State-виджмодель остаётся на guest-контексте
(`.id(appState.languageRefreshToken)` пересоздаёт дерево только при смене языка).
Симптомы, которые это объясняет: (а) сид не виден; (б) «Общий баланс» не изменился после сида;
(в) оба стора содержат ИДЕНТИЧНЫЕ 34 legacy-счёта (ZFINANCEACCOUNT 34/34 — пользовательские
записи, вероятно, годами шли в guest). Файлы: `RootTabView.swift:330-333`, `millioApp.swift:396-397`.
НЕ починено — нужен фикс класса «пересоздание VM при смене скоупа» (решение владельца).

**🟡 Находка 2 — миграционный риск V4 in-place подтверждён на устройстве владельца.**
`HistoricalAssetPrice` добавлен в АppSchemaV4.models задним числом (комментарий в
AppSchemaVersions.swift:90-91). Лог реального устройства: `Cannot use staged migration with an
unknown model version` → no-plan fallback («data may be partially readable») для ОБОИХ сторов.
В DEBUG-ветке fallback идёт через rebuildStorePreservingData (.bak.store виден на симе Pro Max).
До мержа: оформить V5 или пересоздать дев-сторы.

**🟢 Починено в этой сессии:** стрей-текст `plotFrame` в `AccountBalanceChartView.swift:288`
(валил компиляцию всей цепочки chartSection — «opaque return type…», «Cannot find plotFrame»).

**⚪ Мелочь:** alert сида пишет «Демо-портфель создан: 10 счетов», фактически создаётся 12.

**Скриншоты прогона:** scratchpad сессии (step*.png); финальные 4 экрана с сид-данными — НЕ сняты
(экран Mac заблокировался, cliclick недоступен; и без Находки 1 сид в UI всё равно не виден).
Гостевой стор: перед экспериментом сделан бэкап `millio_guest.backup.store` в scratchpad;
в guest-стор скопированы 13 ZACCOUNT + 6 ZACCOUNTGROUP из user (для проверки Находки 1 —
результат проверить после разблокировки экрана; откат: восстановить из бэкапа).

## Правила (без изменений)
Bulletproof — только через суб-агента; не пушить/не мержить без запроса; симулятор iPhone 17 Pro;
guard phrase для кода. Гейт тестов: «не хуже baseline» по файлу baseline-failures.
