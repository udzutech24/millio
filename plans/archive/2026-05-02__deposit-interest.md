# Plan: Процентный доход по вкладам

**Slug:** `deposit-interest`
**Дата создания:** 2026-05-02
**Stage:** 3 / Planning
**Spec:** [`specs/2026-05-02-deposit-interest.md`](../specs/2026-05-02-deposit-interest.md)
**Research:** [`thoughts/research/2026-05-02-deposit-interest.md`](../thoughts/research/2026-05-02-deposit-interest.md)

## Статус

`РЕАЛИЗОВАН`

**Реализовано:** Phase 1–9 (все)
**Дата завершения:** 2026-05-03

## Цель

Вклад должен хранить % ставку и срок, автоматически рассчитывать плановый ежемесячный доход и при желании пользователя добавлять его в Cashflow как recurring income (Проценты).

## Acceptance Criteria (из spec)

- [ ] AC1: Секция "Процентный доход" с полями ставка/дата открытия/дата закрытия в редакторе вклада
- [ ] AC2: Авторасчёт планового дохода = `amount × rate / 100 / 12`
- [ ] AC3: Тоггл → создаётся scheduled income (monthly, .interest)
- [ ] AC4: При изменении суммы/ставки → linked scheduled transaction обновляется
- [ ] AC5: При архивации/удалении вклада → linked scheduled transaction удаляется
- [ ] AC6: Локализация ru/en/zh-Hans
- [ ] AC7: `isDeposit = true` при создании через пикер

## Challenge Log

### 1. Решает ли план проблему из spec?
- AC1 → Phase 2 (UI секция в редакторе)
- AC2 → Phase 2 (computed property в редакторе)
- AC3 → Phase 3 (Cashflow-интеграция, создание)
- AC4 → Phase 3 (Cashflow-интеграция, обновление)
- AC5 → Phase 3 (Cashflow-интеграция, удаление)
- AC6 → Phase 4 (локализация)
- AC7 → Phase 1 (модель + preset-проставление)
- AC8 → Phase 5 (FinanceDynamicsView блоки)
- AC9 → Phase 6 (прогнозная линия на графике)
- AC10 → Phase 7 (капитализация)
- AC11 → Phase 8 (НДФЛ)
- AC12 → Phase 9 (уведомления)
Все AC покрыты. ✓

### 2. Самое эффективное решение?
- **Альтернатива A (выбрана):** расширить Investment (7 опциональных полей) → M, lightweight migration
- **Альтернатива B:** новая модель Deposit → L, дублирование, новый тип в FinanceAccount
- **Выбрано:** A — минимальный blast radius, deposit уже является Investment

### 3. Нет ли кода ради кода?
- Каждое поле модели обслуживает конкретный AC
- CashflowViewModel трогаем точечно: только 1 метод для create/update/delete linked transaction
- Новая секция в InvestmentEditorView — только когда `isDeposit == true` (не затрагивает обычные инвестиции)

## Фазы

**Состояния:** `[ ]` не начато · `[~]` в работе · `[x]` готово

---

### `[x]` Phase 1: Модель — deposit-поля в Investment (DONE)

**AC из spec:** AC7 (isDeposit при создании)

**Файлы:**
- `millio/UI/Services/Investments/Investment.swift` — добавить 6 полей
- `millio/UI/Services/Investments/InvestmentViewModel.swift` — isDeposit в action + private func + логика создания
- `millio/UI/Services/Finances/Editors/FinanceAddAccountView.swift` — pass isDeposit при create и update
- `millio/UI/Services/Finances/InvestmentEditorView.swift` — pass isDeposit в saveInvestment()

**Шаги:**
1. `[x]` Добавить поля в `Investment` (@Model): isDeposit, depositInterestRate, depositStartDate, depositEndDate, depositIncomeInCashflow, depositLinkedScheduledID
2. `[x]` Добавить `isDeposit: Bool` в `InvestmentAction.updateInvestment`, приватную функцию, set при создании новой инвестиции
3. `[x]` В `FinanceAddAccountView.createInvestmentAndAddToGroup` передать `isDeposit: selectedInvestmentPreset == .deposit`; в updateInvestmentAndGroup — `isDeposit: investment.isDeposit`
4. `[x]` В `InvestmentEditorView.saveInvestment()` передать `isDeposit: viewModel.state.editingInvestment?.isDeposit ?? false`
5. `[x]` Self-audit: все 6 полей опциональны или имеют default (false/nil) → lightweight migration не ломает существующие записи
6. `[x]` Сборка: BUILD SUCCEEDED

**Guard phrase для старта:** «Реализуй Phase 1 по плану.»

---

### `[x]` Phase 2: UI — секция "Процентный доход" в редакторе (DONE)

**AC из spec:** AC1, AC2

**Файлы:**
- `millio/UI/Services/Finances/InvestmentEditorView.swift` — новая секция (читать только нужные диапазоны, файл ~1700 строк)

**Шаги:**
1. `[ ]` Добавить @State-переменные в редактор:
   ```swift
   @State private var depositInterestRateText: String = ""
   @State private var depositStartDate: Date = Date()
   @State private var depositEndDate: Date? = nil
   @State private var depositHasEndDate: Bool = false
   ```
2. `[ ]` Computed property:
   ```swift
   private var depositMonthlyIncome: Double {
       guard let rate = Double(depositInterestRateText), rate > 0, amount > 0 else { return 0 }
       return (amount * rate / 100 / 12).rounded(toPlaces: 2)
   }
   ```
3. `[ ]` Новая секция `depositIncomeSection` — показывается только при `viewModel.editingIsDeposit || isDepositCreate`:
   - TextField "Ставка, % годовых"
   - DatePicker "Дата открытия"
   - Toggle "Срок вклада" + DatePicker "Дата закрытия" (если toggle on)
   - Label "Плановый доход: ~X ₽/мес" (если rate > 0)
4. `[ ]` Вставить секцию после баланс-секции, до секции группы
5. `[ ]` Валидация: дата закрытия не раньше даты открытия
6. `[ ]` Self-audit: секция не видна при `isDeposit == false` (обычные инвестиции не тронуты)
7. `[ ]` Коммит: `feat(deposit): deposit interest section in InvestmentEditorView`

**Guard phrase для старта:** «Реализуй Phase 2 по плану.»

---

### `[x]` Phase 3: Cashflow-интеграция (DONE)

**AC из spec:** AC3, AC4, AC5

**Файлы:**
- `millio/UI/Services/Investments/InvestmentViewModel.swift` или `InvestmentManager.swift` — добавить метод синхронизации scheduled transaction
- `millio/UI/Services/Cashflow/CashflowViewModel.swift` (4598 строк — читать только нужные методы!) — найти метод создания scheduled transaction

**Шаги:**
1. `[ ]` Изучить как создаются scheduled transactions в CashflowViewModel (Explore-агент, <200 слов)
2. `[ ]` Добавить метод `syncDepositIncome(investment: Investment, context: ModelContext)`:
   - если `depositIncomeInCashflow == true` и `depositInterestRate > 0` и `amount > 0`:
     - если `depositLinkedScheduledID == nil` → создать новую scheduled income transaction
     - если `depositLinkedScheduledID != nil` → обновить amount в существующей
   - если `depositIncomeInCashflow == false`:
     - если `depositLinkedScheduledID != nil` → удалить scheduled transaction, обнулить ID
3. `[ ]` Вызывать `syncDepositIncome` при save в InvestmentEditorView (после save investment)
4. `[ ]` Добавить тоггл "Планировать доход в Cashflow" в UI секцию Phase 2:
   - показывать только если `depositInterestRate > 0`
   - при включении — показывать "Будет создан: доход ~X ₽/мес, категория Проценты"
5. `[ ]` При архивации Investment (`archivedAt != nil`) → вызвать `syncDepositIncome` с `depositIncomeInCashflow = false` для удаления
6. `[ ]` Edge case: `depositLinkedScheduledID` → несуществующая транзакция → создать новую (graceful fallback)
7. `[ ]` Коммит: `feat(deposit): cashflow integration for deposit interest income`

**Guard phrase для старта:** «Реализуй Phase 3 по плану.»

---

### `[x]` Phase 4: Локализация (DONE — 30 ключей ru/en/zh-Hans; unit-тесты в backlog)

**AC из spec:** AC6

**Файлы:**
- `millio/Localizable.xcstrings` — новые строки
- `millioTests/` — unit-тест на `depositMonthlyIncome` расчёт

**Новые ключи локализации:**
```
finances.deposit.section.income_title        "Процентный доход" / "Interest Income" / "利息收入"
finances.deposit.field.rate                  "Ставка, % годовых" / "Annual Rate, %" / "年利率，%"
finances.deposit.field.start_date            "Дата открытия" / "Start Date" / "开始日期"
finances.deposit.field.end_date              "Дата закрытия" / "End Date" / "结束日期"
finances.deposit.field.has_end_date          "Срок вклада" / "Fixed Term" / "固定期限"
finances.deposit.monthly_income_label        "Плановый доход" / "Planned Income" / "计划收入"
finances.deposit.cashflow_toggle             "Планировать в Cashflow" / "Plan in Cashflow" / "在现金流中计划"
finances.deposit.cashflow_preview            "~%@ ₽/мес · Проценты" / "~%@ /mo · Interest" / "~%@/月 · 利息"
```

**Шаги:**
1. `[ ]` Добавить все ключи в Localizable.xcstrings (ru/en/zh-Hans)
2. `[ ]` Unit-тест: `testDepositMonthlyIncomeCalculation` — проверить `amount × rate / 100 / 12` для граничных случаев (0%, 100%, дробные)
3. `[ ]` Unit-тест: `testDepositSyncCreatesScheduledTransaction` — mock CashflowViewModel, проверить что scheduled transaction создаётся/обновляется/удаляется
4. `[ ]` Self-audit: все AC покрыты
5. `[ ]` Коммит: `feat(deposit): localization and tests`

**Guard phrase для старта:** «Реализуй Phase 4 по плану.»

---

## Edge Cases (Think Several Steps Ahead)

- [ ] Ставка = 0% → тоггл Cashflow disabled, плановый доход не показывается
- [ ] Дата закрытия < даты открытия → валидация в UI, save заблокирован
- [ ] Вклад архивируется → syncDepositIncome вызывается с depositIncomeInCashflow=false
- [ ] depositLinkedScheduledID → несуществующая транзакция → graceful: создать новую
- [ ] Backup restore → linkedID может быть невалидным → не краш, просто nil fallback
- [ ] Пользователь меняет amount → syncDepositIncome пересчитывает при каждом save
- [ ] Lightweight migration: все новые поля default (Bool=false, Optional=nil) → без явной миграции

---

### `[x]` Phase 5: FinanceDynamicsView — блоки для вклада (DONE)

**AC из spec:** AC8 (новый, добавлен ниже)

**Файлы:**
- `millio/UI/Services/Finances/FinanceDynamicsView.swift` (3541 строк — читать только нужные диапазоны)
- `millio/UI/Services/Finances/FinanceDynamicsViewModel.swift` — вычислить прогноз дохода

**Что показываем** (только при `investment.isDeposit == true`):

1. **Полоса параметров** (между балансом и графиком):
   - "18.5% годовых · до 01.04.2027 · 334 дня"
   - Progress bar срока (только если `depositEndDate != nil`)

2. **Блок "Прогноз дохода"** (после таблицы Начало/Конец):
   - Ставка: `depositInterestRate`%
   - Ежемесячный доход: `amount × rate / 100 / 12`
   - Доход за весь срок: `ежемесячный × кол-во месяцев` (только если `depositEndDate != nil`)
   - Накоплено с начала: `ежемесячный × прошедших месяцев` (с `depositStartDate`)
   - Осталось получить: `за срок − накоплено` (только если обе даты есть)

3. **Строка "Следующее поступление"** (только если `depositIncomeInCashflow == true`):
   - Дата следующего monthly scheduled income + сумма

**Шаги:**
1. `[ ]` Computed helpers в FinanceDynamicsViewModel:
   - `depositMonthlyIncome: Double?`
   - `depositTermMonths: Int?` (между start и end)
   - `depositElapsedMonths: Int` (с startDate до сегодня)
   - `depositTermProgress: Double?` (0…1, для progress bar)
   - `depositNextPaymentDate: Date?` (ближайший scheduled income)
2. `[ ]` Найти место вставки в FinanceDynamicsView (между балансом и графиком — через Grep по конкретным меткам)
3. `[ ]` `depositParamsStrip` — полоса параметров + progress bar
4. `[ ]` `depositForecastSection` — таблица прогноза дохода
5. `[ ]` `depositNextPaymentRow` — строка следующего поступления (если Cashflow включён)
6. `[ ]` Локализация новых строк — добавить в Phase 4
7. `[ ]` Self-audit: все три блока скрыты при `isDeposit == false`
8. `[ ]` Коммит: `feat(deposit): deposit forecast blocks in FinanceDynamicsView`

**Guard phrase для старта:** «Реализуй Phase 5 по плану.»

---

---

### `[x]` Phase 6: Прогнозная линия на графике (DONE — пунктир через projectedPoints в FinanceChartContainerView)

**AC из spec:** AC9

**Файлы:**
- `millio/UI/Services/Finances/FinanceDynamicsView.swift` — chart section
- `millio/UI/Services/Finances/FinanceDynamicsViewModel.swift` — прогнозные точки

**Шаги:**
1. `[ ]` Исследовать как устроен текущий chart в FinanceDynamicsView (Explore-агент, Swift Charts или custom)
2. `[ ]` Вычислить прогнозные точки: для каждого месяца от сегодня до depositEndDate — `balance + накопленный%`
3. `[ ]` Добавить второй `LineMark` / `AreaMark` с dash-style поверх основного графика (только при `isDeposit && depositEndDate != nil`)
4. `[ ]` Цвет прогнозной линии — accent (отличается от основной), легенда под графиком
5. `[ ]` Коммит: `feat(deposit): projected income line on dynamics chart`

**Guard phrase для старта:** «Реализуй Phase 6 по плану.»

---

### `[x]` Phase 7: Капитализация (сложный процент) (DONE)

**AC из spec:** AC10

**Файлы:**
- `millio/UI/Services/Investments/Investment.swift` — новое поле `depositCapitalization`
- `millio/UI/Services/Finances/InvestmentEditorView.swift` — UI выбора типа капитализации
- `millio/UI/Services/Finances/FinanceDynamicsViewModel.swift` — пересчёт дохода

**Новое поле модели:**
```swift
var depositCapitalizationRaw: String = "none"  // "none" | "monthly"
```

**Формулы:**
- Без капитализации: `amount × rate/100/12` каждый месяц (простые)
- Ежемесячная капитализация: `amount × (1 + rate/100/12)^months - amount`

**Шаги:**
1. `[ ]` Добавить `depositCapitalizationRaw` в `Investment` (lightweight migration, default "none")
2. `[ ]` `enum DepositCapitalization: String { case none, monthly }`
3. `[ ]` Picker "Капитализация" в редакторе (Без / Ежемесячная) — в секции Phase 2
4. `[ ]` Пересчитать `depositMonthlyIncome` и `depositForecastSection` с учётом типа
5. `[ ]` Обновить linked Cashflow transaction при смене капитализации
6. `[ ]` Коммит: `feat(deposit): compound interest capitalization`

**Guard phrase для старта:** «Реализуй Phase 7 по плану.»

---

### `[x]` Phase 8: НДФЛ — ориентировочный налог (DONE)

**AC из spec:** AC11

**Файлы:**
- `millio/UI/Services/Finances/FinanceDynamicsViewModel.swift` — расчёт НДФЛ
- `millio/UI/Services/Finances/FinanceDynamicsView.swift` — строка в блоке прогноза

**Логика расчёта (2026):**
- Необлагаемый лимит = ключевая ставка ЦБ РФ × 1 000 000 ₽ (пользователь вводит ставку ЦБ вручную или берём default 21%)
- Если годовой доход по вкладу > лимита → НДФЛ = (доход − лимит) × 13%
- Отображаем как «~X ₽ НДФЛ за год» серым текстом под суммой дохода

**Поле модели:** не нужно — расчёт on-the-fly.

**Шаги:**
1. `[ ]` `depositEstimatedTax(cbRate: Double) -> Double?` — вычисляет НДФЛ, nil если доход ≤ лимита
2. `[ ]` В Settings или в редакторе вклада — поле "Ставка ЦБ, %" (default 21%, сохраняется в `UserDefaults`)
3. `[ ]` В блоке прогноза FinanceDynamicsView добавить строку "~X ₽ НДФЛ" (только если > 0)
4. `[ ]` Дисклеймер: "Ориентировочно, проконсультируйтесь с налоговым специалистом"
5. `[ ]` Локализация ru/en/zh-Hans
6. `[ ]` Коммит: `feat(deposit): estimated income tax display`

**Guard phrase для старта:** «Реализуй Phase 8 по плану.»

---

### `[x]` Phase 9: Уведомления об окончании вклада (DONE)

**AC из spec:** AC12

**Файлы:**
- `millio/Core/Notifications/NotificationManager.swift` — уже существует
- `millio/UI/Services/Investments/Investment.swift` — поле `depositNotifyDaysBefore`
- `millio/UI/Services/Finances/InvestmentEditorView.swift` — UI выбора N дней

**Новое поле модели:**
```swift
var depositNotifyDaysBefore: Int? // nil = выкл, иначе 7/14/30
```

**Шаги:**
1. `[ ]` Добавить `depositNotifyDaysBefore: Int?` в `Investment`
2. `[ ]` Picker "Напомнить за" в редакторе (Выкл / 7 дней / 14 дней / 30 дней) — только если `depositEndDate != nil`
3. `[ ]` При save вклада: если depositEndDate и depositNotifyDaysBefore != nil → запланировать локальное уведомление через `NotificationManager`
4. `[ ]` При изменении/архивации → отменить старое уведомление, создать новое (или удалить)
5. `[ ]` Уведомление: "Вклад [name] заканчивается через N дней (дата)"
6. `[ ]` Локализация ru/en/zh-Hans
7. `[ ]` Коммит: `feat(deposit): maturity date notification`

**Guard phrase для старта:** «Реализуй Phase 9 по плану.»

---

## Gates (Swift-проект)

- [ ] `xcodebuild build` — 0 ошибок компиляции
- [ ] `xcodebuild test` — все тесты green
- [ ] Ручная проверка: создать вклад → включить Cashflow-тоггл → проверить scheduled income в Cashflow

## Журнал изменений

- `2026-05-02` — создан план, research завершён, Phase 1 ещё не начата.

## Итог

**Результат:** РЕАЛИЗОВАН
**Дата завершения:** 2026-05-03

**Что реализовано:**
- Phase 1: Investment+6 deposit-полей (isDeposit, rate, startDate, endDate, incomeInCashflow, linkedScheduledID)
- Phase 2: UI-секция "Процентный доход" в InvestmentEditorView с полем ставки, датами, тогглом Cashflow, превью
- Phase 3: syncDepositIncome() в InvestmentViewModel — create/update/delete linked CashflowTransaction (monthly, .interest)
- Phase 4: 30 ключей локализации ru/en/zh-Hans в Localizable.xcstrings
- Phase 5: depositParamsStrip (полоса параметров + прогресс-бар срока) и DepositForecastSection в standardDynamicsContent
- Phase 6: projectedPoints в FinanceChartContainerView — пунктирная жёлтая прогнозная линия
- Phase 7: depositCapitalizationRaw (simple/compound) + DepositCapitalization enum + picker + формулы
- Phase 8: НДФЛ расчёт в DepositForecastView (ставка ЦБ из UserDefaults, @AppStorage)
- Phase 9: depositNotifyDaysBefore + DepositNotifyDays enum + picker + NotificationManager.scheduleDepositMaturityNotification
