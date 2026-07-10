# Handoff 2026-07-10 (утро): итоги ночи 6b Путь B + что осталось

## Состояние репо
- Ветка **`feature/legacy-accounts-purge` @ 4b796dc** — Ф1, Ф1.5, Ф2, Ф2b, Ф3, Ф4, Ф5a, Ф5b реализованы. **НЕ мержено, НЕ пушено.** develop @ 016deec (31 коммит впереди origin).
- Финальный гейт: полный `millioTests` **1709 passed / 14 failed = 100% baseline, 0 новых** (только `xcrun xcresulttool` — консольный «✔ passed» xcodebuild ловили на лжи, НЕ доверять). Release-билд установлен поверх стора на симуляторе iPhone 17 Pro Max iOS 26.5 — миграция+ремапы без краша.
- Baseline красных: `progress/accounts-core-baseline-failures.md` (обновлялся ночью: +UserDefaults-flaky класс).
- Бэкап майского стора симулятора 26.4: `millio-dev/.sim-backups/2026-07-09-9A811413/`.

## Коммиты ночи
`80ad7cc`/`2e17d38` Ф2 (single-world тотал, снос AccountTotalPolicy, миграция до `.ready`) · `3a81230` фикс GroupsMigratorTests (use-after-free) · `49fe371` Ф2b (снос mergingNewCoreSeries) · `52fff71` Ф3 (bulk-импорт → ядро) · `5221736` Ф4 (снос мёртвых редакторов, −3054 строки) · `7d5e906` Ф5a (remapCashflowHistory: cardID/toCardID/investmentID → core-ID; cash-Investment → .bankAccount; снос мёртвых инвест-ордеров ~880 строк) · `c7ef57a` Ф5b (remapCashbackCardIDs + фикс CashbackImporter).

## НЕ сделано по плану (`plans/2026-07-07__legacy-accounts-purge-path-b.md`)

### 🔴 Ф5c — ЗАБЛОКИРОВАНА (отдельная L-сессия, НЕ «дочистить за час»)
Снятие легаси-типов из `ModelTypeRegistry`/`*FeatureRegistration`, схема V6, снос @Model (`Card/Credit/Investment/FinanceAccount/FinanceGroup.swift`) + миграторов/конвертера/реестра, чистка UserDefaults-легаси.
**Блокер:** 76 файлов ещё ссылаются на легаси-типы:
- Cashback UI ~3500 строк — пикер карт легаси-only (2367+1141 строк), нужна портация на ядро;
- EDIT-пути живы: `CardViewModel`/`CreditViewModel`/`InvestmentViewModel` (правка существующих легаси-записей);
- `FinanceAccountService` — 11 живых сайтов;
- `InlineCreateForms` — транзиентные DTO на легаси-типах (рефактор типов);
- ~9 Core-файлов.
Разбивка под-фаз — в плане (запись Ф5c). Апгрейд-путь зафиксирован: старая версия → билд Ф1–5b (миграция+ремапы) → билд 5c.

### Ф6 — редизайн экрана «Счета» (НЕ начат)
Stacked-полоса активы/обязательства, секции с подытогами, кастомные иконки групп (`customIconName`). Делать с владельцем (UI), после Ф5c или параллельно по его решению.

### Хвосты
- **Ручная проверка владельцем**: чек-лист `progress/2026-07-09-checklist-device-f1-f15.md` (билд уже на симуляторе 26.5). Миграцию поверх реальных данных — на устройстве.
- **Мерж ветки в develop** — только после чек-листа + device stress-test + явное «да».
- **Пуш develop** (31 коммит) — по команде.
- `ScreenshotDataSeeder` — не мигрирован (завязан на Cashback→Card; после ремапов Ф5b пересмотреть в Ф5c).
- Известное MVP-ограничение Ф2 (задокументировано, не чинится): дельта Динамики через границу миграции искажена (opening-balance датой миграции).
- Cashflow-фиксы cfd1b3d — ручная проверка владельцем так и не сделана (пункт E чек-листа).

## Регламент следующей сессии
- Реализация/диагностика — субагенты; главное окно — оркестрация (правила 7–9 CLAUDE.md). Режим ponytail (минимальный дифф, не писать код ради кода) — требование владельца.
- Итоги тестов — ТОЛЬКО `xcrun xcresulttool`.
- Параллельные xcodebuild — изолировать `-derivedDataPath`.
- НЕ мержить, НЕ пушить без явного «да».
