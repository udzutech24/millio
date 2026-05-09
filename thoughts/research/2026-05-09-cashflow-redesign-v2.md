# Research: Cashflow Redesign v2 — UI + Architecture

**Date:** 2026-05-09
**Stage:** 1 / Deep Research
**Related:** [`specs/2026-05-09-cashflow-redesign-v2.md`](../../specs/2026-05-09-cashflow-redesign-v2.md)

## Задача исследования

Полный редизайн экрана расходов/доходов (Cashflow) и рефакторинг его архитектуры. Цель — сделать один раз по уму: правильная структура VM+View и современный UX.

---

## Findings from codebase

### Структура файлов

**CashflowView.swift** — 2080 строк, монолитный экран:
- `CashflowView` (обёртка)
- `CashflowContentView` (тело с состоянием)
- `cashflowChartSection` — chart встроен, но expand → fullScreenCover
- `assetBreakdownSection` — статистика
- Навигация через `viewModel.state` bindings (sheet/fullScreenCover)
- LazyVGrid с `CashflowCategoryGridLayout.columns()` — сейчас 4 колонки

**CashflowViewModel.swift** — 4598 строк, God-VM:
- 5 lazy-сервисов уже вынесено: History, Currency, Category, Analytics, Scheduled, Persistence
- **8 MARK-разделов:**
  - Categories — **33 функции** (самый большой, кандидат на VM)
  - History — **25 функций** (кандидат на VM)
  - Scheduled Transactions — 7 функций (уже изолировано в Service)
  - Persistence — 2 функции (тонкая обёртка)
  - Currency helpers — 9 функций (тонкая обёртка)
  - System Visibility — 1 функция
  - Static Utils — 2 функции
  - Period/State/Main — остаток

**Модели:**
- `ExpenseCategory` enum (29 категорий), `IncomeCategory` enum (11 категорий)
- `CashflowCustomCategory` @Model — SwiftData
- `CashflowSystemCategoryOverride` @Model — переопределяет системные
- `CashflowTransaction` — amount, currency, type, expenseCategoryRaw/incomeCategoryRaw (строка или "custom:ID"), recurrenceRule
- `BudgetPlan` @Model — totalLimitAmount, период, anchorYear/Month
- `BudgetCategoryLimit` @Model — лимит по категории, связь через budgetID
- `BudgetProgressCalculator` — пороги: 70% warning, 90% critical, >100% exceeded

**FinanceViewModel.swift** — 2980 строк, отдельный God-VM для счетов. **Не трогаем в этом спринте.**

**CashflowTransactionEditorView.swift:**
- 17 @State переменных, поддержка expense/income/transfer
- `AmountInputFormatter` для ввода суммы, шрифт 38pt base / 32pt compact
- Сложный UX: нужно сначала выбрать тип → потом категорию → потом сумму
- Quick entry отсутствует — тап на категорию идёт в полный редактор

**Chart:**
- `CashflowInsightsBars` — bar chart, высота 110pt
- Expand → fullScreenCover
- PRO-гейт: `EntitlementPolicy.canUseCashflowChart`
- Режимы данных: по периодам (неделя/месяц)

**Цветовая система:** неоновая — cyan #47D7FF, violet #8A6BFF, positive #6DFFC7, negative #FF6666

### Существующие паттерны

- ViewModel = `@Observable` или `@Published var state = ...State()`
- DI через DIContainer, lazy сервисы в VM
- SwiftUI навигация через sheet/fullScreenCover + `@State`/`@Binding`
- Charts: custom bar chart (не Swift Charts), ручная отрисовка через Canvas или Shape
- Лимиты: `BudgetProgressCalculator.snapshot(for:)` → `BudgetProgressSnapshot` с полями progress, tone, isExceeded

### Зависимости

- `BudgetPlan`, `BudgetCategoryLimit` — SwiftData @Model
- `CashflowHistoryService`, `CashflowCategoryService`, `CashflowAnalyticsService` — уже изолированы
- `EntitlementPolicy` — PRO-гейт для chart
- `CashflowCategoryGridLayout` — конфигурирует LazyVGrid

### Тесты

- `millioTests/` — unit-тесты есть (Core, Policy, L10n)
- Тестов на CashflowViewModel нет (God-VM сложно тестировать)
- После декомпозиции — можно добавить тесты на `CashflowCategoriesViewModel` и `CashflowHistoryViewModel`

---

## Findings from UX research

### Референсы (финтех iOS apps)

- **Revolut**: segment control `Income | Expenses | All` под заголовком — мгновенный переключатель контекста
- **Monzo**: PageTabView со свайпом между Income/Spending, Summary card с прогрессом
- **Wallet**: категории как список с inline progress bar (лимит + потрачено)
- **YNAB**: строки вместо плиток — больше данных за экран

### Best practices 2026

- Swipe-based context switch (PageTabView) лучше, чем скрытый filter picker
- Limit progress per category — ключевой мотиватор для PRO конверсии
- Quick entry: тап на категорию → bottom sheet с цифровым полем — снижает friction добавления
- Empty state с иллюстрацией и призывом — стандарт для нулевого месяца
- Collapsible chart section — пользователь сам решает показывать или нет

---

## Alternatives

### Вариант A: Только UI-редизайн (без рефакторинга VM)
- **Плюсы:** быстрее, меньше риск регрессии
- **Минусы:** God-VM остаётся, следующий редизайн так же сложен. CashflowView останется 2000+ строк
- **Трудоёмкость:** M

### Вариант B: Только рефакторинг VM (без UI изменений)
- **Плюсы:** чистая архитектура, тестируемость
- **Минусы:** UX боли остаются, пользователь не видит результата
- **Трудоёмкость:** M

### Вариант C: VM декомпозиция + View декомпозиция + полный UI редизайн ✅
- **Плюсы:** сделать один раз по уму, после этого масштабируемо. Пользователь видит результат
- **Минусы:** большой PR, ~5–6 фаз, нужны careful gates на каждой фазе
- **Трудоёмкость:** L

---

## Recommendation

**Выбран:** Вариант C — всё сразу, по фазам.

**Почему:**
1. VM декомпозиция создаёт чистую базу для UI — каждая View получает правильный VM, не весь God-VM
2. View декомпозиция делает UI изменения безопасными — маленькие компоненты, изолированные изменения
3. Пользователь получает все UX улучшения в одном релизе

**Ключевые архитектурные решения:**
- `CashflowViewModel` → 3 VM: `CashflowMainViewModel`, `CashflowCategoriesViewModel`, `CashflowHistoryViewModel`
- `CashflowView` (2080 строк) → 7 компонентов
- Grid 4 col → 3 col + limit bars
- PageTabView (свайп Расходы/Доходы/Всё) вместо скрытого фильтра
- Chart: collapsible inline section (не только fullscreen)
- Quick entry: тап категории → `CashflowQuickEntrySheet`
- FAB убирается, один "+" в Quick Actions

**Что учесть при имплементации:**
- Сначала Phase 1 (VM) до Phase 2 (View) — нельзя параллельно, зависимость
- PRO-гейт на chart сохраняется через `EntitlementPolicy`
- `BudgetProgressCalculator` уже готов — переиспользовать для per-category bars
- После Phase 1 — обязательно `xcodebuild build` чтобы убедиться нет регрессий
- Кастомные категории (CashflowCustomCategory) должны корректно отображаться в новом grid
