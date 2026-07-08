# Plan: Экран деталей счёта под каждый тип продукта

**Slug:** `account-detail-per-type`
**Дата создания:** 2026-07-05
**Stage:** 3 / Planning
**Spec:** [`specs/2026-07-05-account-detail-per-type.md`](../specs/2026-07-05-account-detail-per-type.md)

## Статус

`НЕ НАЧАТ`

**Реализовано:** —
**Осталось:** все фазы.
**Зависимости:** Ф7 (новые поля модели) — ТОЛЬКО после стабилизации V5-схемы (см. `progress/accounts-core-rebuild-handoff.md`); решение по источнику графика (snapshot backfill vs ленивый реплей + лимит 3М) — до старта Ф1.

## Цель

Разложить единый AccountDetailView на 12 продуктовых конфигураций одного каркаса: общий график/KPI/edit-sheet + per-kind дескрипторы, без действий-ловушек и мёртвых контролов.

## Acceptance Criteria (из spec)

- [ ] AC1: один `AccountChartSection` на все kind, легаси-график не переносится
- [ ] AC2: единые компоненты `KPITileRow` / `AccountEditSheet` / `PriceRevaluationSheet` / `PayoffProgressBar` / `NextDateCard` / `StalenessBadge` / `RevaluationHistoryList`
- [ ] AC3: движок A — ступенчатая линия, периоды 7Д/1М/3М/1Г/Всё, «Потрачено» без transferOut (одна формула)
- [ ] AC4: actionsRow каждого kind — только реально читаемые движком действия
- [ ] AC5: edit-sheet редактирует все backed-поля (включая «Группу» у всех); валюта и assetClass read-only везде
- [ ] AC6: «нет поля — нет контрола»; мёртвые тумблеры вырезаны
- [ ] AC7: archivedAt → read-only у всех kind
- [ ] AC8: redenomination — пост-деноминационные значения в графике/KPI всех kind
- [ ] AC9: S8 для E/F без «перевести остаток»
- [ ] AC10: токены/`L(...)` без нарушений; кэш серии графика по refreshToken

## Challenge Log

### 1. Решает ли план проблему из spec?
AC1–AC2 → Ф1; AC3 → Ф2; AC4–AC9 → Ф2–Ф6 (per-kind) + Ф1 (каркас read-only/S8); AC10 → каждая фаза (gate). Все AC покрыты.

### 2. Это самое эффективное решение?
- **Альтернатива A:** 12 отдельных экранов-файлов. Плюс: изоляция; минус: 12× дублирование графика/edit-sheet, расползание как в легаси. Отвергнуто.
- **Альтернатива B:** один экран + разрастающийся switch (текущее). Минус: уже нечитаем на 830 строках без графика и настроек. Отвергнуто.
- **Выбрано:** общий каркас + per-kind дескриптор (конфиг-структуры), группировка фаз по движкам — соседи по движку отличаются только конфигом.

### 3. Нет ли кода ради кода?
Замена легаси-графика — не drive-by: он не подключён к ядру и нарушает токены; перенос невозможен. Новые поля модели вынесены в отдельную гейтованную фазу, а не размазаны.

## Фазы

**Состояния:** `[ ]` не начато · `[~]` в работе · `[x]` готово

### `[ ]` Phase 1: Общий каркас + переключение по kind

**AC из spec:** AC1, AC2 (частично), AC7, AC9, AC10

**Файлы:**
- `millio/UI/Services/Finances/AccountsCore/Components/AccountChartSection.swift` — новый: чипы периодов, линия (step/stepEnd/линия по конфигу), drag-точка, оверлеи (zero-line, лимит, риски дат, cost-basis, маркеры событий), инверсия знака, слот KPI; серия кэшируется по refreshToken
- `millio/UI/Services/Finances/AccountsCore/Components/KPITileRow.swift` — новый: 3 плашки, «—» вместо 0,00
- `millio/UI/Services/Finances/AccountsCore/Components/AccountEditSheet.swift` — новый: скелет Form (имя/группа/includeInTotal/заметка/валюта read-only) + слот kind-секции + деструктивная зона архива
- `millio/UI/Services/Finances/AccountsCore/AccountDetailDescriptor.swift` — новый: per-kind дескриптор (actionsRow состав/порядок/тайтлы, конфиг графика, KPI-провайдер, словарь подписей истории)
- `millio/UI/Services/Finances/AccountsCore/AccountDetailView.swift` — подключить дескриптор, шестерёнку, общий read-only режим archivedAt, S8-варианты по движку
- `millio/Localizable.xcstrings` — новые ключи

**Шаги:**
1. `[ ]` Тесты: дескрипторы (состав действий per kind, движок E/F без cash-действий), формулы KPI движка A, read-only при archivedAt
2. `[ ]` Имплементация каркаса
3. `[ ]` Self-audit по AC
4. `[ ]` Verification (deep bug hunt: производительность реплея, кэш серии)
5. `[ ]` Impact analysis (существующие sheets/alerts не сломаны)
6. `[ ]` Коммит: `feat(accounts-core): account detail per-kind scaffold`

**Acceptance:** старый экран работает для всех kind через дескриптор; график рендерится хотя бы для движка A; edit-sheet сохраняет общие поля через AccountsCoreService; archivedAt скрывает actionsRow/шестерёнку у всех.

**Guard phrase для старта:** «Реализуй Phase 1 по плану.»

---

### `[ ]` Phase 2: Движок A — Карта / Наличные / Счёт

**AC из spec:** AC3, AC4, AC5, AC6, AC8 (для A)

**Файлы:**
- `AccountDetailDescriptor.swift` — конфиги .debitCard/.cash/.bankAccount (ступень, 7Д/1М/3М/1Г/Всё, оверлеи овердрафта/нуля)
- `Components/BalanceStatusLine.swift` — новый: статус ниже нуля (овердрафт warning/error)
- `AccountEditSheet.swift` — kind-секции: банк-пикер (общий справочник Карта+Счёт) / last4 / овердрафт; у .cash секция пустая
- `AccountDetailSheets.swift` — режим AccountAdjustBalanceSheet «фактическая сумма → дельта» (Пересчитать/Сверка)
- `AccountDetailView.swift` — карточка «Сверка» для .cash; кэшбэк-секция Карты за фичефлагом (выключен до моста)

**Шаги:**
1. `[ ]` Тесты: KPI-формула (expense+fee, без transferOut), семантика минуса от overdraftLimit, режим «факт → дельта»
2. `[ ]` Имплементация
3. `[ ]` Self-audit
4. `[ ]` Verification
5. `[ ]` Impact analysis
6. `[ ]` Коммит: `feat(accounts-core): cashLike detail screens`

**Acceptance:** у карты минус в пределах лимита = «Овердрафт −X из Y», не error; .cash не рендерит bank/last4; «Пересчитать» пишет adjustment-дельту от фактической суммы; empty-state для свежих счетов; один набор периодов и одна KPI-формула на всех трёх.
**Известные блокеры вне фазы:** bridge пишет .cash вместо .debitCard; пресета «Наличные» нет (открытые вопросы 1–2 spec).

---

### `[ ]` Phase 3: Движок B — Вклад

**AC из spec:** AC4, AC5, AC6, AC8 (для B)

**Файлы:**
- `AccountDetailDescriptor.swift` — конфиг .deposit (периоды «Срок»/1Г/Всё и 1М/1Г/Всё, факт-сплошной + проекция-пунктир по будущим interest шедулера)
- `Components/TermProgressBar.swift` — новый (createdAt→termEnd)
- `AccountEditSheet.swift` — deposit-секция: ставка/капитализация/срок/allowsTopUp/allowsEarlyClose+штраф (доля↔%, конвертация на границе); БЕЗ remindEnd/autoRollover/payoutDay; сноска «регенерация только будущих начислений»
- `AccountDetailView.swift` — рефактор depositForecastSection (следующее начисление, gross/net, налог с «доля этого вклада»), условия-карточка, выделение interest в истории

**Шаги:**
1. `[ ]` Тесты: APY-формула, регенерация только будущих interest при смене условий, «настройте ключевую ставку» вместо налога 0
2. `[ ]` Имплементация
3. `[ ]` Self-audit
4. `[ ]` Verification (проекция визуально ≠ факт; будущие события не в ленте)
5. `[ ]` Impact analysis (DepositInterestScheduler, early-close flow)
6. `[ ]` Коммит: `feat(accounts-core): deposit detail screen`

**Acceptance:** KPI Начислено/Доход net/APY; termEnd=nil и termEnd-в-прошлом состояния; edit ставки регенерирует только будущее; мёртвых тумблеров нет.

---

### `[ ]` Phase 4: Движки C+D — Кредит + Долг

**AC из spec:** AC4, AC5, AC6, AC8 (для C/D)

**Файлы:**
- `AccountDetailDescriptor.swift` — конфиги .loan (|баланс|, инверсия цвета, 1М/6М/1Г/Всё) и .debt (модуль, direction-цвет, 1М/3М/1Г/Всё, дефолт «Всё»)
- `Components/PayoffProgressBar.swift` — новый, общий loan (principal→0) + debt (|openingBalance|→0)
- `Components/NextDateCard.swift` — новый, общий (loan.paymentDay+monthlyPayment, debt.dueDate; deposit подключается ретроактивно)
- `Components/CounterpartyAvatar.swift` — новый (инициалы)
- `AccountEditSheet.swift` — loan-секция (ставка/платёж/день/срок/principal; БЕЗ insurance и scheduleType-сегмента) и debt-секция (контрагент/направление с LOCK после событий/срок/ставка)
- `AccountDetailView.swift` — direction-словарь подписей истории, составные действия «Погасить полностью», баннеры переплаты/«выплачен 🎉»

**Шаги:**
1. `[ ]` Тесты: клэмп paymentDay 29–31, LOCK direction после первого не-opening события, переплата не флипает direction, rate=0 → «не указана»
2. `[ ]` Имплементация
3. `[ ]` Self-audit
4. `[ ]` Verification (redenomination для долга; hardcode termEnd +1 год не выдаётся за правду)
5. `[ ]` Impact analysis (инверсия 265–273, переименования 244–259 не сломаны)
6. `[ ]` Коммит: `feat(accounts-core): loan and debt detail screens`

**Acceptance:** хедер кредита — положительное число textPrimary; «платёж не отмечен» — мягкий бейдж, не «просрочен»; долг — фраза-направление и модуль суммы; «Начислить %» только при rate; прогноз-пунктир кредита не рисуется.

---

### `[ ]` Phase 5: Движок E — Инвестиция / Акции / Крипта

**AC из spec:** AC4, AC5, AC6, AC8, AC9 (для E)

**Файлы:**
- `AccountDetailDescriptor.swift` — конфиг .marketInvestment + вариации по assetClass (точность qty: крипта 8, акции 4; лейблы Дивиденд/Купон/Награда; валидация шорта: stock — стоп, crypto — предупреждение)
- `Components/StalenessBadge.swift` — новый (цена: «провайдер · дата» / «из сделки» / возраст)
- `Components/PositionStatsCard.swift` — новый (кол-во/средняя/текущая+источник/вложено)
- `AccountDetailSheets.swift` — `PriceRevaluationSheet` (цена за юнит; НЕ AdjustBalance+titleOverride)
- `AccountsCore/CostBasisCalculator.swift` — новый: единый метод (средняя цена И realized P&L из одного места; buy@0 исключён из cost basis)
- `AccountDetailView.swift` — cost-basis-пунктир, маркеры сделок, секция «Результат», подписи «не влияет на стоимость позиции», market-S8

**Шаги:**
1. `[ ]` Тесты: CostBasisCalculator (avg-cost, после redenom-множителя, qty=0/qty<0), исключение buy@0, market-S8 без «перевести остаток»
2. `[ ]` Имплементация
3. `[ ]` Self-audit
4. `[ ]` Verification (кэш точек графика; ступени до кэша цен с честной подписью)
5. `[ ]` Impact analysis (AccountBuySellSheet, AccountMarketPriceService)
6. `[ ]` Коммит: `feat(accounts-core): market detail screens`

**Acceptance:** у market-тройки нет income/expense/transfer/adjust в actionsRow; три экрана = один каркас, различия конфигом; qty=0 → «Позиция закрыта · итог» + CTA архив; archivedAt read-only.
**Гейт до старта:** решение владельца по вопросам 3 (кэш от продаж) и 17 (cost basis метод; награда buy@0 vs веса движка — если меняется движок, обязателен /stress-test).

---

### `[ ]` Phase 6: Движок F — Недвижимость / Бизнес / Другое

**AC из spec:** AC4, AC5, AC6, AC8, AC9 (для F)

**Файлы:**
- `AccountDetailDescriptor.swift` — конфиг .manualAsset + вариации пресетов (дефолт напоминания: Недвижимость 12 мес, Бизнес 6; ипотечная секция только Недвижимость; helper «стоимость вашей доли» только Бизнес)
- `Components/RevaluationHistoryList.swift` — новый (revaluation-таймлайн с Δ ±abs/±% + строка «Покупка»)
- `Components/SaleFlowSheet.swift` — новый: продажа (финальная revaluation → income на денежный счёт → revaluation→0 → архив); до атомарного флоу в ядре — последовательные вызовы с откатом при ошибке
- `AccountEditSheet.swift` — manualAsset-секция: revalReminderMonths-пикер, linkedLoanID-пикер (только Недвижимость)
- `AccountDetailView.swift` — StalenessBadge оценки (переиспользован из Ф5), ипотечная секция «Своих: X (Y%)», stepEnd-график с пунктирным хвостом, empty-state

**Шаги:**
1. `[ ]` Тесты: staleness от revalReminderMonths, «Своих» = оценка − остаток (только same-currency), валидация суммы (Недвижимость >0, Бизнес/Другое ≥0), ленивое создание ManualAssetMeta
2. `[ ]` Имплементация
3. `[ ]` Self-audit
4. `[ ]` Verification (S8-ловушка F закрыта; висячий linkedLoanID очищается)
5. `[ ]` Impact analysis
6. `[ ]` Коммит: `feat(accounts-core): manual asset detail screens`

**Acceptance:** actionsRow F = Переоценить/Продажа/Настройки/Архив; RevaluationHistoryList вместо общей ленты; пресет «Другое» получает полный кит; redenomination у Бизнеса — по пересчитанным значениям.
**Гейт до старта:** вопрос 7 (атомарная продажа в AccountsCoreService) — либо решение, либо принятая деградация с откатом.

---

### `[ ]` Phase 7: Новые поля модели (⚠️ после стабилизации V5)

**AC из spec:** закрывает ⚠️-настройки spec (не входят в AC1–AC10 v1)

**Зависимость (жёсткая):** V5-схема стабилизирована и вмержена — см. `progress/accounts-core-rebuild-handoff.md`. Все поля — опционалы (CloudKit-safe, без unique-констрейнтов), добавляются одной миграционной волной, не поштучно. Перед фазой — `/stress-test` + подтверждение Алексея (правило workspace о крупных изменениях данных).

**Кандидаты (по решениям владельца из Open Questions spec):**
- `Account.iconName` / `Account.colorToken` / `Account.favorite` — либо выпилить сбор favorite/priority из форм создания
- Единый `ReminderMeta` (loan-платёж, deposit remindEnd, debt remindDaysBefore, manualAsset-переоценка) + сервис локальных нотификаций
- `CardMeta.cardColor`; мост Cashback→Account
- `DepositMeta.cashflowIncome: Bool?` (регрессия «вклады→Cashflow»)
- `MarketMeta.priceAutoUpdate: Bool?`
- `ManualAssetMeta.ownershipShare: Decimal?`
- фикс `createAccount` (принимать includeInTotal/favorite вместо потери)

**Файлы:** `Core/AccountsCore/Account.swift`, `AccountMeta.swift`, `AccountsCoreService.swift`, `AccountsCoreAdditionBridge.swift`, миграция схемы, UI-контролы, ранее спрятанные политикой «нет поля — нет контрола»

**Шаги:**
1. `[ ]` Решения владельца по каждому полю (AskUserQuestion батчем)
2. `[ ]` /stress-test изменения схемы
3. `[ ]` Тесты миграции (старые записи с nil-полями)
4. `[ ]` Имплементация полей + включение спрятанных контролов
5. `[ ]` Self-audit + Verification (CloudKit-бэкап новых полей — связка с блокером ModelTypeRegistry)
6. `[ ]` Коммит: `feat(accounts-core): model fields wave for detail screens`

**Guard phrase для старта:** «Реализуй Phase 7 по плану.» (+ явное «да» после stress-test)

---

## Edge Cases (Think Several Steps Ahead)

- [ ] Нулевые данные: свежий счёт / только openingBalance → empty-state, KPI «—», не нули (все фазы)
- [ ] Огромные данные: 1Г/Всё = до 365+ реплеев на body → кэш по refreshToken + снапшоты/лимит периода (Ф1)
- [ ] Redenomination в середине периода: график/KPI по пост-деноминационным значениям у ВСЕХ kind (Ф2–Ф6)
- [ ] archivedAt time-aware: read-only, график обрезан, «Разархивировать» единственное действие (Ф1)
- [ ] S8-ловушка E/F: «перевести остаток» не работает (вес 0) — свои формулировки (Ф5, Ф6)
- [ ] Конкурентные изменения: правка меты во время реплея — запись только через AccountsCoreService, инвалидация refreshToken
- [ ] Обратная совместимость: счета от bridge (пустая/кривая мета: bank=.other, counterparty=nil, rate=0, termEnd+1год) — деградация с CTA «Указать», без падений
- [ ] Миграции данных: только Ф7, опционалы, после V5
- [ ] Откат/частичные сбои: SaleFlowSheet — последовательность с откатом до атомарного флоу ядра

## Gates (обязательны перед `[x]` на фазе)

- [ ] `xcodebuild build` — BUILD SUCCEEDED (iPhone 16 Pro sim)
- [ ] `xcodebuild test` (millioTests) — green, не хуже baseline
- [ ] Нет новых RU-литералов / `Color(hex:)` / `Font.system(size:)` (scripts/validate-placeholders + ревью)
- [ ] Все строки через `L(...)` с ключами в Localizable.xcstrings (RU/EN/zh-Hans)
- [ ] Self-audit по AC фазы

## Дизайн-слой — требование владельца 2026-07-08 (обязательно для всех фаз)

Владелец (скриншоты легаси-деталок SPY и «Кредит МА», ночь 2026-07-08): **«у каждого типа продукта своя страница, но стилистика единая, наполнение разное; сейчас плоховато»**. Дизайн — не побочный эффект, а часть AC этого плана:

1. **Единая стилистика всех 12 конфигураций** — тот же визуальный язык, что новые экраны Cashflow-редизайна (план 2026-07-05__cashflow-add-transaction-redesign §7.5): карточные секции с едиными радиусами/отступами, доминирующая типографика суммы (millioDisplay + monospacedDigit), чипы с иконкой и цветом, selected-state обводкой, одна доминирующая CTA на экран, вторичные действия визуально тише на порядок.
2. **Антипримеры с легаси-скриншотов — не воспроизводить:** сырые значения без форматирования (733.72998 в edit-режиме); Buy/Sell как две равнозначные крупные кнопки с эмодзи-иконками в рамке; три деструктивных/технических действия подряд списком (Move to new core / Delete asset / Delete permanently); заголовок-сумма без иерархии с типом продукта; edit-режим, отличающийся от view только рамками полей.
3. **Деструктивная зона** — единый паттерн: архив/удаление в конце edit-sheet, сгруппированы, с подтверждением; технических кнопок миграции в новом экране нет вообще (после 6b нечего мигрировать).
4. **Растущая иерархия страницы**: тип+имя продукта → сумма (доминанта) → динамика/график → KPI-плашки → per-kind секции → действия. Одинаковый скелет у всех 12, разное наполнение слотов (это уже заложено в дескрипторы — пункт фиксирует визуальный порядок).
5. Ремарка к скоупу: легаси-деталки со скриншотов (`Investment`/`Credit` миры, кнопка «Move to new core») НЕ полируются — они сносятся планом 6b Путь B; вся дизайн-энергия идёт в новый `AccountDetailView` + дескрипторы этого плана.

## Журнал изменений

- `2026-07-05` — план создан из спеки; статус НЕ НАЧАТ; гейты Ф5 (решения по market-ядру) и Ф7 (V5) зафиксированы.
- `2026-07-08` — добавлен обязательный дизайн-слой (требование владельца, ночной прогон): единая стилистика 12 конфигураций в языке Cashflow-редизайна, антипримеры легаси зафиксированы; легаси-деталки не полируем (снос по 6b).

## Итог (заполняется при завершении)

**Результат:** —
**Что реализовано:** —
**Что не реализовано и почему:** —
**Дата завершения:** —
**Архивируем:** `mv plans/undefined__account-detail-per-type.md plans/archive/`
