# План: тип счёта «Кредит»

**Спека:** [`specs/2026-09-04-credit-account-type.md`](../specs/2026-09-04-credit-account-type.md)
**Ветка:** `feature/credit-account-type` (worktree `millio-dev/worktrees/credit-account-type`, база `4c38a0e`)
**Правила прогона:** коммит после каждой зелёной фазы · merge / push / установка на устройство — **только с явного разрешения владельца** · симулятор один: iPhone 17 Pro (iOS 26.5) · сборка
`xcodebuild ... -derivedDataPath /tmp/dd-credit -quiet 2>&1 | tail -20` · перед каждым коммитом
`git diff --stat -- millio/Resources/Localizable.xcstrings` (Xcode портит файл при сборке на устройство).

---

## Ф1 — Разведка, спека, план ✅

Дописаны `specs/2026-09-04-recon-schema.md` (разделы 2–5: существующий `LoanMeta`, паттерн связи по id,
`ModelTypeRegistry` / totals / Cashflow / периодичность, список ломающихся тестов) и
`specs/2026-09-04-recon-ui.md` (139 строк: что переиспользуем, что параметризуем, что пишем).
Написана спека и этот план. Контракт округления проверен расчётом — все 12 контрольных чисел макета
сходятся только при неокруглённом платеже (см. спеку §4.3).
**Коммит:** разведка + спека + план, без кода.

## Ф2 — Ядро расчёта и схема ✅

**Делаем**
- `LoanPaymentFrequency` (5 кейсов → `stepMonths`), `LoanScheduleType` (annuity / differentiated).
- `LoanTerms` — value-struct условий (без SwiftData).
- `LoanScheduleEngine` — график, остаток, проценты впереди, переплата, дата закрытия.
  Округление по спеке §4.3: `Decimal` без промежуточных округлений, платёж не округляем.
  Даты периодов — через `DepositInterestScheduler.scheduledPeriodEnd(...)`, свою арифметику дат не пишем.
- `LoanPrepaymentPlanner` — два сценария «срок» / «платёж» + недоплата, экономия по фактическому графику.
- `@Model LoanContract` + `LoanContractStore` (upsert по `accountID`, образец `AccountAppearanceStore`).
- `AppSchemaV12 = V11.models + [LoanContract.self]`, `.lightweight(V11→V12)`,
  `AppSchemaCurrent = AppSchemaV12`. Декларации V1–V11 и константы checksum не трогаем.
- `LoanTermsResolver` (`LoanContract ?? LoanMeta`) + grep всех чтений `LoanMeta` — свести к резолверу.

**Тесты**
- Эталонные числа спеки §4.5 — 12 проверок, сходимость в ноль.
- Дифференцированный график: Σ тел = principal, платёж убывает, конечный остаток = 0.
- Периодичность: квартал / полгода / год — платёж и переплата.
- `SchemaConsistencyTests.v12PreservesEveryV11Entity()` (новый, образец `v11PreservesEveryV10Entity`, `:148-165`).
- `AppSchemaFrozenGraphTests.testCurrentSchemaOnlyAddsNewEntityOnTopOfPreviousVersion` — baseline V10 → V11,
  ожидаемая разница `{"LoanContract"}`.

**Готово когда:** эталонные числа зелёные, `make test` без новых красных против `4c38a0e`,
стор существующего пользователя открывается (миграция V11→V12 на симуляторе с непустой базой).

**Сделано.** `millio/Core/AccountsCore/Loan/` — `LoanPaymentFrequency`, `LoanTerms` (+ сид из
легаси `LoanMeta`), `LoanScheduleEngine` (`LoanScheduleRow`/`LoanSchedule`), `LoanPrepaymentPlanner`,
`LoanContract`, `LoanContractStore`, `LoanTermsResolver`. Схема: `AppSchemaV12` + lightweight-стадия
V11→V12, `AppSchemaCurrent = AppSchemaV12`; декларации V1–V11, `stableEntityHashes` и
`accountHashByVersion` не тронуты. Единственное оставшееся чтение `LoanMeta` в UI
(`AccountDetailView.loanInfoLines`) переведено на резолвер.
Все 12 эталонных чисел §4.5 сошлись в ноль. Гейт: 234 теста зелёные (ядро кредита + схема + вклад),
полный `millioTests` — 2609 passed / 26 failed, все 26 совпадают с известным baseline
(`progress/accounts-baseline-failures`-класс: l10n/race/network), проверено прогоном тех же сьютов
с `AppSchemaCurrent`, откаченным на V11 — набор красных идентичен.

**Отклонение от спеки (зафиксировано).** §4.4 описывает «недоплату» как рост срока. Модель, дающая
эталонные числа §4.5 (остаток 937 241 = 1 137 241 − 200 000), трактует сумму как ЧИСТОЕ уменьшение
тела: при любой положительной сумме срок не растёт, просто выгода мельче. Заниженный очередной
платёж — другой сценарий (живёт в `paymentOverride`, при платеже ниже процентов график пуст),
покрыт отдельным тестом.

**Не сделано осознанно.** `LoanPrepaymentPlanner` поддерживает только аннуитет: у дифференцированного
графика нет единого платежа, сценарий «сократить платёж» для него не определён, эталонных чисел нет,
UI (Ф6) — аннуитетный. Возвращает `nil` + тест.

**Долг Ф7:** `LoanContract` ещё не зарегистрирован в `ModelTypeRegistry` (нет `LoanContractImporter`),
поэтому в бэкап пока не попадает.

## Ф3 — Экран «Условия кредита» ✅

Форма в двух режимах: создание (сумма и ставка редактируемые) и правка (read-only, как на макете).
Срок, дата первого платежа, сегмент типа платежа, чипсы периодичности, тумблер «задать платёж вручную»
+ сумма с подсказкой «по формуле выходит N ₽».
Переиспользовать: `AccountDetailsFieldRow` / `AccountDetailsToggleRow` / `AccountFieldPickerSheet`
(`DepositAccountDetailsSheet.swift:33/62/86`), `periodChip` (`DepositTermsInputCard.swift:226`),
нативный `.pickerStyle(.segmented)`, `AmountTextField` для всех сумм.
Первым — потому что без способа завести договор остальные три экрана нечем наполнять.
**Готово когда:** договор создаётся и правится, изменения переживают перезапуск, сборка зелёная.

**Сделано.** `millio/UI/Services/Finances/AccountsCore/Loan/`: `LoanTermsDraft` (черновик формы —
разбор полей, срок «месяцы ↔ периоды», платёж-подсказка из ядра), `LoanTermsFormCard`
(режимы `.create`/`.edit`: в правке сумма и ставка read-only), `LoanTermsEditSheet` (оболочка
правки, пишет `LoanContract` через `LoanContractStore`). Вход в правку — кнопка «Условия кредита»
в `AccountDetailView` (`ActiveSheet.loanTerms`). Создание: карточка условий встроена в
`InlineCreditCreateForm`, договор пишется через `graphEnricher` `AccountProductFactory.create` —
в ТОЙ ЖЕ транзакции, что и счёт. `LoanMeta` не расширялась, легаси-кортеж формы сохранил форму.

**Переиспользовано:** `AccountDetailsBoxCard` / `AccountDetailsFieldRow` / `AccountDetailsToggleRow` /
`AccountDetailsDivider` / `AccountFieldPickerSheet` (у трёх снят `private`), `AmountTextField`,
нативный `.pickerStyle(.segmented)`. Чипс `periodChip` вынесен из `DepositTermsInputCard` в
`AccountSelectionChip` — вклад теперь зовёт тот же компонент. Написано с нуля только
`AccountDetailsValueRow` (read-only близнец строки формы, аналога не было).

**Режим определяется наличием договора, а не экраном.** Счёт, созданный старой формой, приходит
со ставкой 0 (`AccountsCoreAdditionBridge.loanMeta` её никогда не собирал) — поэтому пока
`LoanContract` не заведён, сумма и ставка редактируемые даже в правке.

**Дедупликация формы создания.** Из `InlineCreditCreateForm` убраны поля «Сумма кредита»,
«Ежемесячный платёж», «Режим платежа» и «День платежа»: их теперь собирает карточка условий, и два
поля «сумма кредита» на одном экране были бы багом. Легаси-кортеж собирается из черновика
(`paymentMode` всегда `.dayOfMonth`, день — из даты первого платежа), `LoanMeta.termEnd` считается
ядром вместо прежнего «+1 год».

**Гейт.** Сборка зелёная (BUILD SUCCEEDED). Тесты: 176 passed / 0 failed
(`LoanTermsDraftTests`, `LoanContractPersistenceTests`, `LoanScheduleEngine`, `LoanContractStore`,
`LoanPrepaymentPlanner`, `SchemaConsistencyTests`, `AppSchemaFrozenGraphTests`,
`AllPresetsOnNewCoreTests`, `CreditCardCreationContractTests`, `DepositPresentationTests`) +
36 passed / 0 failed на локализации (`LocalizationKeysTests`, `LocalizableXcstringsTests`,
`FinanceLocalizationTests`). Диff `Localizable.xcstrings` — 570 строк, только вставки.

**Расхождения с макетом (осознанные).** (1) «Сумма платежа» и «Сумма кредита» правятся листом
снизу, а не инлайн-полем — на этом экране все поля открываются листом (требование брифинга,
`AccountFieldPickerSheet`). (2) Срок в модели — периоды, в форме — месяцы; при неежемесячной
периодичности срок подтягивается вверх до кратного шагу. (3) Медный акцент `#E0A458` не вводился:
`LoanScreenStyle` — предмет Ф4, форма пока в общем `brandPrimary`.

## Ф4 — Деталка счёта ✅

Hero «Осталось выплатить» (`AccountHeroCardView` + `customContent`), прогресс погашенного тела,
метрики 2×1, чипсы условий, кнопки «Внести платёж» / «Досрочно», разбивка платежа и переход в график.
Ленивый backfill `LoanContract` из `LoanMeta` при первом открытии (спека Р5).
Меню и подтверждения — листом снизу (`AccountActionsSheet`), реквизиты счёта — экран вклада как есть.
Новое: `LoanScreenStyle` (accent `#E0A458`).
**Готово когда:** цифры деталки совпадают с ядром на эталонном кредите, экран собран из существующих компонентов.

**Сделано.** Витрина `LoanDetailPresentation` (`millio/UI/Services/Finances/AccountsCore/Loan/`) —
единственная точка, где цифры экрана берутся из `LoanScheduleEngine`; вью не считает ничего.
`LoanHeroContent` (остаток → прогресс погашенного тела → метрики 2×1) как `customContent` общего hero,
`LoanDetailSection` (чипсы условий → кнопки → разбивка платежа), `LoanPaymentConfirmSheet`
(подтверждение листом снизу), `LoanScreenStyle` (медь `#E0A458`; тело и проценты — существующие
`positiveColor`/`negativeColor`). В `AccountDetailView` добавлены ветка hero, секция, кейс
`ActiveSheet.loanPayment` и «···» кредита через `AccountActionsSheet`; генерик-ряд действий для кредита
с условиями скрыт — иначе на экране было бы две разные кнопки платежа. Ядро: `LoanPaymentRecorder`
(тело — в ленту, проценты — в договор, одна транзакция через save-барьер `recordEvent`) и
`LoanContractBackfill` (Р5: ленивый, идемпотентный, прогресс восстанавливается по календарю).

**Переиспользовано:** `AccountHeroCardView` + `customContent`, `AccountSelectionChip` (чипсы условий
в невыбранном состоянии), `AccountDetailsBoxCard`/`AccountDetailsDivider`, `AccountActionsSheet`,
`AccountRowAmountFormatter`, `AccountsCoreService.recordEvent`. Из `DepositHeroContent` вынесены в
`Hero/AccountHeroPrimitives.swift` `AccountHeroProgressBar` и `AccountHeroMetricTile` (плитка метрики
была написана там трижды) — вклад теперь зовёт те же компоненты, визуал не менялся. С нуля написана
только `LoanBreakdownRow` (строка «точка-легенда → название → сумма»).

**Гейт.** Сборка зелёная (BUILD SUCCEEDED). Тесты: 15 новых (`LoanDetailPresentationTests`,
`LoanPaymentRecorderTests`, `LoanContractBackfillTests`), 176 passed / 0 failed на регрессе
(ядро кредита, схема V12, вклад, пресеты) и 54 passed / 0 failed на локализации. Эталонный кредит
на слое витрины: остаток 1 137 241 · погашено тела 62 759 · прогресс 5,2 % · платёж 31 063 ·
тело 13 151 · проценты 17 912 · уплачено процентов 92 554 · следующий платёж 15.09.2026 ·
закрытие 15.03.2031 · 55 платежей впереди. Диф `Localizable.xcstrings` — 462 строки, только вставки.

**Расхождения с макетом (осознанные).** (1) «Досрочно» на экране есть, но неактивна — лист приходит
в Ф6; строка «График платежей · 55 впереди ›» неактивна до Ф5. (2) Чипсы условий кликабельны и ведут
в «Условия кредита»: `AccountSelectionChip` — кнопка, а кнопка без действия хуже, чем кнопка с
осмысленным. (3) «Изменить баланс» кредиту не даём ни рядом действий, ни в меню:
`AmountInputFormatter.sanitize` отбрасывает минус, и сохранение перевернуло бы знак долга — счёт-
обязательство ушёл бы в net worth активом. Это существующий баг генерик-пути; ремонт остатка
кредита — отдельная задача.

## Ф5 — График платежей ✅

Список строк «месяц · двухцветная полоса тело/проценты · сумма», подсветка текущего периода, легенда,
карточка «Переплата за весь срок» + доля от суммы кредита. Новый компонент — только двухцветная полоса.
**Готово когда:** первые 11 строк совпадают с таблицей макета (проценты тела 39…47%), переплата 663 760 ₽.

**Сделано.** Витрина `LoanSchedulePresentation` (`millio/UI/Services/Finances/AccountsCore/Loan/`) —
единственная точка счёта экрана: внесённые платежи берутся строками исходного графика договора,
платежи впереди — от ФАКТИЧЕСКОГО остатка тем же `LoanDetailPresentation.remainingTerms`, которым
живёт деталка (метод перестал быть приватным). Поэтому «55 впереди» на деталке и число невнесённых
строк экрана — одно число по построению, а не по совпадению. `LoanScheduleView` — дамб-вью: 60 строк
обычным `VStack`, подсветка текущего периода фоном `LoanScreenStyle.currentRowFill` и медью в ярлыке
месяца, внесённые приглушены `paidRowOpacity`, легенда и карточка «Переплата за весь срок» с долей от
суммы кредита. Строка «График платежей · N впереди ›» на деталке стала кнопкой и открывает экран
пушем (`navigationDestination`), витрина строится в замыкании назначения — 60 строк не нужны на
каждый пересчёт `body`.

**Переиспользовано:** `LoanScheduleEngine`, `LoanDetailPresentation.remainingTerms`,
`AccountDetailsBoxCard`, `GradientBackground`, `LoanScreenStyle`, ключ
`accounts_core.loan.detail.schedule` под заголовок экрана. С нуля написаны только `LoanShareBar`
(двухцветная полоса, аналога в проекте нет) и `LoanMoneyFormat` — общий форматтер денег и процентов,
в который переехали три метода `LoanDetailPresentation` (деталка и график печатают одни и те же
числа, вторая копия правил округления разъехалась бы с первой).

**Гейт.** Сборка зелёная (BUILD SUCCEEDED). Тесты: 7 новых (`LoanSchedulePresentationTests`),
119 passed / 0 failed на выборке «кредит + схема V12 + вклад + локализация». Эталонный кредит на
слое витрины: 60 строк · 5 внесённых · 55 впереди · текущий период шестой · переплата 663 760 ₽ ·
доля переплаты 55,3 % · доли тела платежей 1–11 = 39·40·40·41·42·42·43·44·44·45·46 %. Диф
`Localizable.xcstrings` — 110 строк, только вставки.

**Расхождения с макетом (осознанные).** (1) Колонка «Тело %» макета расходится с ядром начиная с
третьего платежа (макет: 41·42·42·43·44·44·45·46·47, ядро: 40·41·42·42·43·44·44·45·46). Макет спорит
сам с собой: его же шестой платёж 13 151 / 31 063 = 42,3 %, а в таблице стоит 43 %. Эталон — спека
§4.5, все её числа сошлись в ноль ещё в Ф2, поэтому ядро не подгонялось под таблицу. Месяцы макета
при этом верны: первый платёж 15 апреля 2026 = «Апр 26». (2) Ярлык месяца собирается из сокращения и
двух цифр года по отдельности: готовый шаблон `LLL yy` в русской локали добавляет «г.» («апр. 26 г.»)
и не помещается в колонку.

## Ф6 — Досрочное погашение (лист снизу)

Крупный ввод суммы, радио «Срок / Платёж» с тегом выгоды, diff «было → стало» (4 строки),
карточка экономии, кнопка подтверждения. Предвыбран «срок». Тот же лист обслуживает недоплату.
**Готово когда:** на эталонном сценарии лист показывает 937 241 ₽ / 25 600 ₽ / −13 платежей /
экономию 226 771 ₽, значения берутся из `LoanPrepaymentPlanner`, а не из вью.

## Ф7 — Интеграция

- Платёж → транзакция `.expense` в Cashflow (`CashflowMonthMutationPolicy.validate` перед вставкой,
  дедуп `importSourceRaw: "loanPayment"` + `importReferenceKey`); страховка — отдельной строкой.
- Платёж → событие в ленте счёта, уменьшающее тело долга (проценты долг не уменьшают).
- `ModelTypeRegistry`: регистрация `LoanContract` + `LoanContractImporter`, round-trip тест бэкапа.
- Тест net worth: счёт `.loan` уменьшает тотал ровно на остаток тела, будущие проценты не попадают
  (правок `AccountTotalsContribution` не ожидается — тест это доказывает).
**Готово когда:** полный `make test` зелёный, повторный прогон платежа не задваивает транзакцию.

## Ф8 — Сдача владельцу

Сводка изменений, что проверить на устройстве, вопрос о merge и установке. Ничего не мержим и не пушим
до явного «да».

---

## Смежное (вне этого плана)

Висит незакрытая device-проверка ветки `feature/deposit-detail-unified-card`
(план `millio/plans/2026-09-03__account-screens-redesign.md`, Ф8): вклад, инвестиция, лист снизу,
реквизиты + кнопка «Это кредитная карта» на «Альфа Кредитке» (лимит 1 500 000, ожидаемое падение
net worth на 267 660 ₽). Наша ветка растёт от неё — при мерже это тянется следом.
