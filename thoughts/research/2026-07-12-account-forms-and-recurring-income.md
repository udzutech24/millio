# Research: формы счетов (создание/детали) + авто-линковка доход/расход в Cashflow

**Дата:** 2026-07-12 · **Статус:** RAW — зафиксировано владельцем по скриншотам, код не тронут. Для новой сессии (Александр + Fable-ревью формы).

## Контекст

После редизайна 5c.7.6/5c.7.7 (см. `plans/2026-07-11__phase-5c7-finances-replatform.md`, СМЕРЖЕНО в develop локально, не запушено) владелец прогнал реальный флоу «создать вклад» + посмотрел экраны деталей счёта на симуляторе. Три отдельные находки — все требуют продумывания форм, не точечного патча.

## Находка 1 — форма создания вклада (New account → Deposit)

Скриншоты: заголовок формы "New account" + поле "Name" (плейсхолдер "e.g. Cash") наверху, а ниже, после выбора Product type = Deposit, появляется ВТОРОЕ поле "Name" с плейсхолдером "Deposit name" — визуально два независимых поля ввода имени в одной форме.

- `millio/UI/Services/Finances/Editors/FinanceAddAccountView.swift:139` — первый TextField (имя, базовая форма создания счёта)
- `millio/UI/Services/Finances/AccountsCore/InlineDepositCreateForm.swift:101` — второй TextField (имя, внутри inline-формы под конкретный тип Deposit)

Судя по всему это две разные формы, стэкающиеся друг над другом при выборе типа продукта — общий каркас `FinanceAddAccountView` + type-specific `InlineDepositCreateForm`. Нужно решить: либо один name-field на весь флоу, либо чёткое разделение (например верхний — временный draft, убирается когда открывается type-specific форма).

## Находка 2 — Amount без форматирования разрядов

`InlineDepositCreateForm.swift:113` — `TextField(..., text: $amountText)` с `.keyboardType(.decimalPad)`, plain `String` binding без разделителя тысяч. При вводе `10000` не видно `10 000` — сложно проверить сумму на глаз, особенно для крупных вкладов.

Нужен паттерн live-форматирования суммы при вводе (thousand separator), сохраняя корректный decimal parsing. Если в проекте уже есть такой форматтер для других денежных TextField (Cashflow amount input и т.п.) — переиспользовать, не писать новый (ponytail: reuse before build).

## Находка 3 — разбивка блоков формы (Rate/Term) неудобна при активной клавиатуре

Скриншоты показывают, что при вводе Amount/Rate раскладка (Rate segmented control None/Monthly/Quarterly, Term toggle, цифровая клавиатура) выглядит тесной/наезжающей. Нужен визуальный review формы целиком в раскрытом состоянии (все поля Deposit: Name, Amount, Rate, Term) — возможно, это чисто спейсинг/скролл, не архитектурная проблема. Fable-ревью формы должен явно проверить: видно ли активное поле над клавиатурой, не перекрывает ли клавиатура последний блок, логичен ли порядок полей.

## Находка 4 (продуктовая идея) — авто-линковка дохода/расхода продукта с Cashflow

Идея владельца: если у создаваемого продукта (Deposit с rate, возможно другие типы) есть регулярный доход — при создании автоматически заводить запись в Cashflow как регулярный доход (recurring income); аналогично для регулярного расхода (если применимо к другому типу продукта).

Существующая инфраструктура (переиспользовать, не изобретать заново):
- `millio/UI/Services/Cashflow/CashflowTransaction.swift:51` — `enum CashflowRecurrenceRule` (none/weekly/monthly/quarterly/semiannual/yearly) — уже есть периодичность, совпадает по смыслу с Rate у Deposit (Monthly/Quarterly).
- `millio/UI/Services/Cashflow/CashflowScheduledService.swift:16,71` — `CashflowScheduledService.recurringTemplates()` — сервис, который уже управляет регулярными шаблонами Cashflow.
- `millio/Core/AccountsCore/DepositInterestScheduler.swift:9,83` — `DepositInterestScheduler.regenerateFutureInterestEvents()` — УЖЕ считает будущие проценты по `depositMeta.rate` отдельным путём (генератор interest-событий на счёте). Это отдельный, параллельный механизм от Cashflow-recurring.

**Ключевой архитектурный вопрос для Fable/Александра:** сейчас доход по вкладу уже материализуется через `DepositInterestScheduler` (interest-события на самом счёте). Если добавить ещё и recurring-запись в Cashflow — это два источника дохода по одному вкладу (риск двойного учёта в аналитике/дашборде), либо `DepositInterestScheduler` нужно связать с Cashflow как единый источник. Нужно явно продумать:
1. Один источник правды: либо interest-события счёта дублируются в Cashflow view-слоем (без второй записи в БД), либо Cashflow recurring — единственный источник, а `DepositInterestScheduler` от него зависит.
2. Что происходит при изменении rate/удалении вклада — обновляется ли/удаляется ли linked-recurring-запись в Cashflow.
3. Применимо ли к другим типам продуктов (кредит с регулярным платежом = расход?) — если да, единый паттерн, не Deposit-специфичный хак.
4. UI: где пользователь видит/выключает эту авто-линковку (toggle в форме создания? всегда авто? можно отвязать потом?).

## Находка 5 — экран деталей счёта после редизайна: слишком общий, типовые действия исчезли

Скриншоты «после»: Card-счёт (Tinkoff Black) — actions `Income / Expense / Adjust balance / Transfer / Edit`. Investment-счёт (AAPL) — actions `Revalue / Edit / Delete`, потеряны `Buy/Sell`, которые были раньше у инвестиций.

Владелец: "стало всё очень просто и неинтересно... у акций вообще было купить/продать и для каждого типа счёта нужно было сделать внутри экран, а сейчас криво — UI generic".

Это прямое пересечение с уже существующей незапущенной спекой: `progress/` память проекта фиксирует `millio-account-detail-per-type` — спека+план на 7 фаз готовы (НЕ НАЧАТА на 2026-07-05), решения владельца зафиксированы тогда: график = отложен до backfill (снят), icon/favorite = отложить, **кредитка = отдельная задача**. Инвестиции (Buy/Sell) явно требуют разбора: являются ли они частью той же спеки или отдельным doc — нужно свериться со спекой перед стартом, не изобретать заново классификацию per-type actions.

Найти актуальный путь спеки (`specs/2026-07-05-account-*` или похожий) и файл(ы) экрана деталей счёта per-type в новой сессии — не сделано в этом ресёрче (не запрашивалось).

## Результаты research-прохода + решения владельца (2026-07-12, сессия исполнена)

**Статус:** research-проход, Fable-ревью формы и стресс-тест находки 4 выполнены. Код НЕ писался (guard phrase не давалась).

### Верифицированные факты

- **Находка 2:** форматтер существует — `millio/UI/Shared/AmountInputFormatter.swift` (sanitize/display/sanitizeForDisplay), рабочий паттерн raw+display state в `CashflowTransactionEditorView` (два @State :64–65, onChange :361–370, helpers :1816–1822). Готового переиспользуемого компонента нет. **Решение владельца: AmountInputFormatter = глобальное правило проекта** (вписано в `millio/CLAUDE.md` → «Проектные правила», память `feedback-amount-input-formatter-global-rule`): любой денежный TextField только через него, helpers вынести в общий компонент, не копировать по формам.
- **Находка 4:** авто-линковка дохода вклада в Cashflow **уже реализована** — `millio/UI/Services/Cashflow/AccountsCoreDepositCashflowBridge.swift:28` материализует наступившие interest-события в обычные `CashflowTransaction` (income/.interest, дедуп по `importReferenceKey == sourceTransactionID`, идемпотентно, вызов при каждой загрузке Cashflow-таба); будущие события → «Предстоящие» read-only (`upcomingInterestEvents()` :96–115), в БД не пишутся. `CashflowScheduledService` (ручные recurring) — независимый механизм, ключи дедупа не пересекаются. Синхронизации материализованного прошлого при изменении rate/удалении вклада нет (для прошлого — корректно).
- **Находка 5:** спека `specs/2026-07-05-account-detail-per-type.md` + план `plans/2026-07-05__account-detail-per-type.md` (НЕ НАЧАТ, 7 фаз) **уже покрывают** и Buy/Sell для Investment (раздел 7.3), и действия Card (раздел 1.3). Отдельная задача не нужна — находка 5 = аргумент запустить существующий план. Экран: `millio/UI/Services/Finances/AccountsCore/AccountDetailView.swift` + `AccountDetailSheets.swift`.

### Стресс-тест находки 4 (вердикт)

Recurring-запись поверх моста отклонена: (1) гарантированный двойной учёт — механизмы с непересекающимися ключами дедупа; (2) расхождение сумм/дат — recurring фиксирован, реальные проценты компаундятся и падают на годовщины открытия; (3) осиротевшие шаблоны при изменении rate/закрытии вклада. Кредит как recurring expense — преждевременно (кредитного ядра нет, отдельный план от 2026-07-05). Открытые хвосты: перенос валюты вклада мостом не проверен; инвариант «1 interest-событие = 1 Cashflow-запись» не защищён тестом.

**Решение владельца (AskUserQuestion 2026-07-12):** галочка в форме создания вклада «добавлять/не добавлять доход в Cashflow», просто. Трактовка: мост остаётся единственным источником; per-deposit флаг (default ON = текущее поведение), мост его уважает; toggle в форме создания. Открытые вопросы для спеки: поведение при выключении флага на уже живом вкладе (что с материализованным прошлым), место флага (DepositMeta vs Account).

### Fable-ревью формы (находки 1–3, полный текст — в сессии 2026-07-12)

1. **Два Name — визуальный дубль одного значения**, конфликта данных нет (оба бьются в один `accountName`, binding в FinanceAddAccountView.swift:532, сохранение :1082–1083). Фикс: удалить nameSection из InlineDepositCreateForm (:67, :97–106) — выравнивает с card/credit/investment, у которых своей name-секции нет.
2. **Amount:** форма переиспользования — обёртка-View `AmountTextField` (не modifier): API `placeholder` + `value: Binding<String>` (raw canonical) + `maxFractionDigits` + опциональный font-closure (нужен Cashflow :614). В депозите применить к amount :113, rate :132, penalty :179; `parseNumber` (:42–44) → `AmountInputFormatter.parse`. Затем миграция копий в InlineCreateForms.swift:152–166, :934–977, :1142–1152.
3. **Раскладка — приемлемо**, перекрытий нет (родительский ScrollView :684–706 + системная keyboard avoidance + `.scrollDismissesKeyboard(.immediately)`). Минусы: нет @FocusState-цепочки; в FinanceAddAccountView массовые нарушения UI-токенов (`Font.system` :149, :217 и далее, сырые spacing :117, :685, сырая spring :852).
4. **Compat-шимы:** мёртвый archived-режим (`addAccountMode` не переключается, `archivedSelectionSections` :608–682 не референсится) — снести; 16-полевые кортежи creditData/investmentData (:56–57) — незавершённый переход на draft-структуры; 13 однотипных onChange (InlineDepositCreateForm.swift:75–88) → один onChange по Equatable `currentData()`.

**Порядок работ (рекомендация ревью):** PR-1 — удалить депозитную nameSection + мёртвый archived-код (безопасно). ✅ PR-1 DONE 2026-07-12: InlineDepositCreateForm.swift (nameSection удалена), FinanceAddAccountView.swift (enum AddAccountMode + @State addAccountMode + archivedSelectionSections + addAccountModeSection удалены, все `addAccountMode == .create` guard-и упрощены до безусловных — поведение не изменилось, т.к. значение всегда было .create). Build + релевантные тесты (FinanceAddAccountProductCounterTests, AllPresetsOnNewCoreTests, InlineCardDraftTests) зелёные. PR-2 — `AmountTextField` + миграция Cashflow и депозит-формы (отдельно, со stress-test — трогает протестированный Cashflow). PR-3 (после спеки) — toggle линковки Cashflow в форме. Позже: токен-чистка каркаса, FocusState. Находка 5 — не отдельная задача, запуск существующего плана account-detail-per-type.

## Рекомендация для новой сессии

1. Открыть новый чат в этом проекте (гарантирует делегирование Александру по CLAUDE.md).
2. Guard phrase не давать сразу — начать с `/bulletproof` или ручного Research-прохода: (a) прочитать существующую спеку `account-detail-per-type` (свериться, не задваивает ли Находку 5), (b) найти существующий money-formatter (если есть) для Находки 2, (c) прочитать `DepositInterestScheduler` полностью для Находки 4.
3. Явно запросить Fable-ревью формы (Находки 1-3) — визуальный макет + спейсинг, отдельно от продуктовой логики (Находка 4) — не смешивать UI-фикс и архитектурное решение о втором источнике дохода в одной фазе.
4. Находка 4 — стресс-тест обязателен (двойной учёт дохода — риск для реальных данных владельца, см. `millio-single-real-user-risk-calibration`).
