# Research: экран кредита — что уже есть и в чём дельта до решений владельца

Дата: 2026-09-07 · Для фазы Ф3 плана `plans/2026-09-06__account-screens-unification.md`
Ветка исследования: `feature/account-screens-cash` (= develop + Ф0 + Ф1 + Ф2).

---

## Главная находка: Ф3 — не «строим экран», а закрываем дельту

План унификации 06.09 описывает Ф3 как «research → spec → plan → код по макету Ф9a; движок есть,
делаем UI: условия · график · лист досрочки». **Это устаревшая оценка.** Весь UI кредита уже
написан и уже в `develop`:

- План `plans/2026-09-04__credit-account-type.md` — фазы Ф1–Ф7 закрыты ✅.
- Мерж в `develop` — коммит `dcf4cd6` («тип счёта „Кредит“ + редизайн экранов счетов»),
  `git merge-base --is-ancestor origin/feature/credit-account-type develop` → истина.
- Код присутствует в текущем рабочем дереве (`feature/account-screens-cash`).

**Файл `plans/2026-09-03__account-screens-redesign.md` (макет Ф9a) в рабочем дереве отсутствует** —
существует только в коммите `9d3f15f` другой ветки. Ветку `feature/deposit-detail-unified-card`
(его исходный дом) в develop не влили. Для Ф3 это не блокер: расхождения с макетом уже зафиксированы
письменно в журналах Ф3–Ф6 плана 09-04, ниже они учтены.

### Что реализовано (файл : назначение)

**Ядро — `millio/Core/AccountsCore/Loan/` (13 файлов):**

| Файл | Публичный API (вход → выход) |
|---|---|
| `LoanTerms.swift` | value-struct условий: `principal · annualRatePercent · termPeriods · firstPaymentDate · scheduleType · frequency · paymentOverride` |
| `LoanScheduleEngine.swift` | `schedule(terms:calendar:) -> LoanSchedule` (массив `LoanScheduleRow`: index/date/payment/interest/principal/balanceAfter); `regularPayment(terms:)`, `annuityPayment(...)`, `periodRate(...)`, `remainingTerms(...)`, `paymentDate(...)`. `LoanSchedule` даёт `totalOverpayment`, `payoffDate`, `outstandingPrincipal(afterPayments:)`, `interestAhead(afterPayments:)`, `nextPaymentDate(afterPayments:)` |
| `LoanPrepaymentPlanner.swift` | сумма → `LoanPrepaymentPlan` (два `LoanPrepaymentPreview`: `.term` и `.payment`, у каждого `savings`, `paymentsDelta`, `payoffDate`, `interestAhead`) / `LoanUnderpaymentPlan` / полное погашение; отдаёт готовый `LoanExtraPaymentEntry` (principalPart, interestPart, consumesPeriod, pinnedPayment). Дифференцированный график — только `.term`, `.payment` = `nil` |
| `LoanContract.swift` + `Store` + `Backfill` | `@Model` (схема V12), upsert по `accountID`, ленивый идемпотентный backfill из легаси `LoanMeta` |
| `LoanPaymentRecorder.swift` | `record(entry:on:date:note:)` и `recordScheduledPayment(...)` — единственный путь записи любого платежа: тело → событие ленты, проценты → договор, одна транзакция |
| `LoanPaymentCashflowProjector.swift` | проводка платежа в Cashflow: расход `.other` + отдельная строка `.insurance`; дедуп `importSourceRaw:"loanPayment"` + `importReferenceKey` (`paymentID`, `paymentID#insurance`) |
| `LoanOutstanding.swift` | кламп пыли `Decimal`: остаток ниже копейки = ноль |
| `LoanTermsResolver.swift` | `LoanContract ?? LoanMeta` — единственная точка чтения условий |

**UI — `millio/UI/Services/Finances/AccountsCore/Loan/` (15 файлов, 2004 строки):**
витрины `LoanDetailPresentation` (94) · `LoanSchedulePresentation` (145) · `LoanPrepaymentPresentation` (356);
вью `LoanHeroContent` (106) · `LoanDetailSection` (116) · `LoanScheduleView` (135) ·
`LoanPrepaymentSheet` (305) · `LoanPaymentConfirmSheet` (98) · `LoanTermsFormCard` (269) ·
`LoanTermsEditSheet` (126) · `LoanTermsDraft` (119); стиль/примитивы `LoanScreenStyle` (45) ·
`LoanMoneyFormat` (31) · `LoanBreakdownRow` (31) · `LoanShareBar` (28).
Все вью — «дамб»: цифры считает витрина, витрина зовёт ядро. Тестов по кредиту: 107 зелёных
(на момент Ф7 плана 09-04).

**Интеграция с деталкой после Ф1-декомпозиции** (`UI/.../AccountsCore/`):
`AccountDetailView.swift:42` — `ActiveSheet.loanPayment/.loanPrepayment/.loanTerms`;
`AccountDetailActions.swift:75` — кнопка платежа; `AccountDetailView+Sheets.swift:91,455` — листы и
роутинг `LoanDetailAction`; `AccountDetailLiabilitySection.swift` — 14 loan-упоминаний.
Ф0 уже выдал кредиту круглый `AccountActionsRow`, `AmountTextField`, `accountSheetChrome`,
локализацию (ru/en/zh-Hans).

---

## Дельта до решений владельца 06.09

### D1. Платёж = плановая операция Cashflow — НЕ сделано (главная работа Ф3)

Сейчас: пользователь жмёт «Внести платёж» → `LoanPaymentRecorder` → `LoanPaymentCashflowProjector`
кладёт в Cashflow **факт** расхода. Плановой записи нет вообще: кредит не виден в «Предстоящих», не
попадает в бюджет месяца, не даёт напоминания, не участвует в сводке применённых.

Как устроены плановые операции (`UI/Services/Cashflow/CashflowScheduledService.swift`, 545 строк):
- «Плановая» — это обычная `CashflowTransaction`, а не отдельная сущность. Два вида:
  **recurring-шаблон** (`recurrenceRule != .none` + `recurrenceSeriesID`, флаг `isRecurringTemplate`,
  `CashflowTransaction.swift:777-849`) и **разовая будущая** (`recurrenceRule == .none` + дата
  после baseline, `CashflowPlannedDatePolicy.isOneTimePlanned`).
- Чтение: `recurringTemplates(for:)`, `plannedOneTimeTransactions(for:)`, `scheduledPlannerEntries(for:)`,
  `scheduledCalendarEntries(...)`, `nextOccurrenceDate(for:relativeTo:)`.
- Применение: `generateRecurringTransactionsIfNeeded()` (:270) и
  `applyDuePlannedTransactionsIfNeeded(referenceNow:)` (:376) — асинхронные, дёргаются по расписанию.
- Вне Cashflow серии заводит только `InvestmentViewModel` (:311, :619 — читает по `recurrenceSeriesID`).

**Три конкретных препятствия, найденных в коде:**
1. `CashflowRecurrenceRule` = weekly / monthly / quarterly / semiannual / yearly.
   `LoanPaymentFrequency.every2Months` (`LoanPaymentFrequency.swift:10`) отображения не имеет —
   recurring-шаблон для такого кредита построить нечем.
2. Применение плановой операции сегодня создаёт только транзакцию. Если не встроить хук
   «применилась операция с `importSourceRaw == "loanPayment"` → `LoanPaymentRecorder.recordScheduledPayment`»,
   расход спишется, а тело долга не уменьшится — прямой рассинхрон Cashflow и net worth.
3. Два входа записи (ручная кнопка + авто-применение) без общего дедупа = двойной учёт платежа.
   Существующий дедуп проектора (`importReferenceKey = paymentID`) от этого не спасает: у ручного и
   планового платежа разные `paymentID`.

Смежная зависимость: ветка `feature/planned-operations-applied-notice` (сводка применённых) в
`develop` не влита — платёж кредита попадёт в сводку только после её мержа.

### D2. Досрочка без предвыбора — сделано на 80 %

`LoanPrepaymentSheet.swift:16` — `@State private var strategy: LoanPrepaymentStrategy = .term`,
то есть «срок» **предвыбран**. Витрина уже отдаёт обе опции с тегом выгоды
(`LoanPrepaymentPresentation.swift:199-234`), у каждой есть свой `savings` из планировщика.
Дельта: снять предвыбор (`strategy: LoanPrepaymentStrategy?`), заблокировать подтверждение до выбора,
показывать у каждого варианта **абсолютную** экономию, а не разницу экономий двух сценариев
(нынешний тег — разница, см. журнал Ф6 плана 09-04: 126 316 ₽).
Крайний случай уже обработан: `selectedStrategy: nil` при `plan.closesLoan` (:180) и одна опция у
дифференцированного графика.

### D3. Страховка отдельной операцией — почти сделано, есть лишний код

`LoanContract.insuranceAmount` **из UI не выставляется никогда** — поля нет ни в `LoanTermsFormCard`,
ни в `LoanTermsDraft` (grep `insurance` по `UI/` даёт только категории Cashflow/Cashback).
Единственные писатели — импорт бэкапа (`AccountsCoreFeatureRegistration.swift:78,94,111`).
При этом `LoanPaymentRecorder.swift:83-90` читает поле, а проектор строит по нему вторую строку
Cashflow. То есть в UI живёт мёртвая ветка, противоречащая решению владельца.
Дельта: снять insurance-ветку из recorder + projector. Поле модели **не удалять** — схема V12
заморожена, удаление поля стоит миграции при нулевой выгоде (данных из UI туда не попадало).

### D4. Net worth = только тело — сделано, доказано тестом

`LoanNetWorthContributionTests` (журнал Ф7 плана 09-04): остаток 1 137 241 ₽ уменьшает тотал ровно
на эту сумму, проценты впереди 571 206 ₽ в сальдо не попадают. Правок не требуется.

### D5. Стиль и декомпозиция — сделано в Ф0/Ф1, нужен только аудит

Кредит получил круглый ряд действий, `AmountTextField`, `accountSheetChrome`, 33 ключа локализации.
Остаточная проверка: три собственных экрана кредита (`LoanScheduleView`, `LoanPrepaymentSheet`,
`LoanTermsEditSheet`) на детенты, автофокус, текстовые Save/Cancel и отсутствие `Font.system`/
числовых литералов.

---

## Открытые вопросы к владельцу (нужны до кода Ф3.3)

1. **Периодичность «раз в 2 месяца».** Recurrence-правила такого нет. Варианты:
   (а) для неподдерживаемых периодичностей вести **одну разовую** плановую операцию, пересоздавая её
   после каждого применения (рекомендую — честно и без мусора);
   (б) добавить `every2Months` в `CashflowRecurrenceRule` (трогает общий Cashflow, шире фазы);
   (в) не планировать такие кредиты вовсе.
2. **Судьба кнопки «Внести платёж».** Рекомендую: кнопка = «применить ближайшую плановую операцию
   сейчас» (один путь записи), а не второй независимый способ внести платёж.
3. **Досрочка меняет платёж (`pinnedPayment`).** Пересоздавать плановую операцию молча или
   спрашивать подтверждение в листе?
4. **Мерж `feature/planned-operations-applied-notice`** — до Ф3 или после (влияет на то, увидит ли
   владелец платёж кредита в сводке применённых на device-проверке).
