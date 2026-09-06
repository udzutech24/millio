# Экраны счетов: единый стиль · декомпозиция · оставшиеся типы

Дата: 2026-09-06 · Статус: план на согласовании · Sidecar: `2026-09-06__account-screens-unification.status.json`
Предшественники: `2026-09-03__account-screens-redesign.md` (Ф9 макет Кредита), `specs/2026-07-05-account-detail-per-type.md`.

## Что установлено (research 06.09, три аудита)

**Состояние типов**
| Тип | Экран | Модель | Что не хватает |
|---|---|---|---|
| Вклад, Инвестиции, Кредитка | ✅ свои DetailSection | — | Investment без DetailSection под hero (сразу история) |
| Кредит (.loan) | общий экран + `LoanDetailSection` | `LoanMeta` + `LoanTerms/LoanContract`, движок `LoanScheduleEngine`, `LoanPrepaymentPlanner` **уже есть** | UI по макету Ф9a (условия, график, лист досрочки) |
| Дебетовая карта, Банк. счёт, Наличные | общий cash-like путь, `DebitCardDetailSection` ~110 строк | общая `CardMeta` (bank, last4, overdraftLimit…) | edit-sheet, банк-picker; **у наличных нет пресета в пикере создания** |
| Долг (receivable/payable) | общий, 3 строки info | `DebtMeta` (direction, counterparty, dueDate, rate) | формы создания нет, edit-sheet нет, напоминания нет |
| Недвижимость / Бизнес / Авто / Другое | общий | одна `ManualAssetMeta` (revalReminder, depreciation, linkedLoanID) | подтипы не различаются полями; переоценка-флоу |

**Тяжёлые файлы (>500 строк, зона счетов):** `AccountDetailView.swift` 1821 · `FinanceAddAccountView.swift` 1644 · `AccountsCoreService` 926 · `DepositOperationCoordinator` 730 · `FinanceAddAccountProductPicker` 711 · `InvestmentViewModel` 692 · `DepositAccountDetailsSheet` 667 · `AccountDetailSheets` 508.

**Расхождения стиля (топ):** меню «⋯» — 3 паттерна (bottom sheet / `Menu` / `Menu` в круглой кнопке) · панель действий — 3 стиля (круглые 46pt / pill-скролл / нет) · `AccountEventEntrySheet` без `AmountTextField` · `presentationDetents` заданы у половины листов · `autofocusAfterPresentation` только в одном листе · 5+ `.alert` вместо листов · заголовки листов — navigationTitle vs кастом · Save/Cancel то иконки (`CreditCardEditSheet:126`) то текст · плашки — тёмный `AccountDetailsBoxCard` (вклад) vs `.ultraThinMaterial` (кредитка) · **`CreditCardDetailSection.swift:46-73` — ~20 хардкод-строк EN/RU вперемешку, кредитка не переводится** · `"Изменить сумму долга"` в общем листе (`AccountDetailView:1417`) · графика нет ни у кого, кроме инвестиций (sparkline ad-hoc в hero).

**Скорость:** перф-запахи мелкие (3 форматтера в computed var `AccountDetailView:799,1067,1140`; `sortedEvents:92-101` без мемо; `FinanceAddAccountView:781` onAppear без guard). Главная UX-потеря — вклад/кредит: 3 тапа до действия (список → деталь → «⋯» → пункт) против 2 у карты/инвестиций.

**Общие компоненты, которые уже есть:** `AccountHeroCardView` (+ per-type HeroContent) · `AccountDetailPlaqueSection` · `AccountActionsSheet` · `AmountTextField` · `AccountEventEntrySheet`. Отсутствуют из спеки 07-05: `KPITileRow`, `AccountChartSection` как общий, единый `AccountEditSheet`.

## Фазы (порядок предложен, ждёт «да»)

| Ф | Что | Гейт | ETA |
|---|---|---|---|
| **Ф0 Единый стиль** | один `AccountActionsRow` (стиль на выбор владельца — круглые или pill) для всех типов · все «⋯» → `AccountActionsSheet` · `AccountEventEntrySheet` → `AmountTextField` · общий модификатор `.accountSheet(detent:)` = detents + drag indicator + autofocus + текстовые Save/Cancel · алерты зоны счетов → листы · заголовки листов одним способом · один стиль плашек (box card) · локализация кредитки (~20 строк) + хардкод → L() · 3 форматтера + `sortedEvents` мемо + onAppear guard | build + millioTests baseline (см. память flaky) + device-скрины 3 переработанных типов | 1 сессия |
| **Ф1 Декомпозиция** | `AccountDetailView` → Header / LiabilitySection / DepositSection / MarketSection / Forecast / History / Sheets (по существующим MARK) · `FinanceAddAccountView` → FormSections по типу продукта · без изменения поведения | тесты до/после одинаковые, `git diff --stat` только перемещения | 1 сессия |
| **Ф2 Наличные** | пресет в пикере (блокер) · `CashDetailSection`: баланс, «Сверка» (adjust), история · без CardMeta-полей | device | 0.5 сессии |
| **Ф3 Кредит (Ф9b)** | research → spec → plan → код по макету Ф9a; движок есть, делаем UI: условия · график · лист досрочки · платёж-в-Cashflow по ответу владельца | spec/plan согласованы, device | 2 сессии |
| **Ф4 Дебетовая + Банк. счёт** | один конфиг на cash-like с оверрайдами (last4/банк/овердрафт) · edit-sheet · банк-picker · кэшбэк-мост | макет → device | 1 сессия |
| **Ф5 Долг** | форма создания (direction, counterparty, dueDate, rate) · DetailSection · edit-sheet · ReminderMeta | макет → device | 1 сессия |
| **Ф6 manualAsset** | недвижимость/бизнес/авто/другое конфигом: hero + переоценка-лист + revalReminder; подтип-поля (площадь/VIN/доля) — только если владелец подтвердит | макет → device | 1–1.5 сессии |

Ф0+Ф1 первыми: после них Ф2–Ф6 — конфиг + DetailSection на 100–200 строк каждый, а не копипаста из 1821-строчного файла.

## Правила исполнения
- Каждая фаза — своя ветка от develop, коммит после под-фазы, worktree только внутри проекта.
- Мерж в develop — только после device-проверки владельцем.
- Сборка на устройство: `xcrun devicectl device install app`; после сборки проверить `default.metallib` в бандле; `git diff Localizable.xcstrings` перед мержем.
- Макеты Ф4–Ф6 — design-canvas по скринам владельца, до кода.

## Решения владельца (06.09.2026)
- Порядок фаз Ф0→Ф6 — **принят**.
- Панель действий для всех типов — **круглые иконки 46pt (как инвестиции)**, остальное в «⋯» (bottom sheet).
- Кредит: платёж по графику = **плановая операция в Cashflow** (бюджет, напоминания, сводка применённых).
- Кредит: досрочка — **без предвыбора** (срок/платёж выбирается каждый раз, с цифрой выгоды у каждого варианта).
- Кредит: страховка — **отдельная плановая операция в Cashflow**, не поле кредита (`LoanMeta.insurance` не использовать в UI).

- Кредит в net worth — **только остаток тела** (без процентов).
- Ф0 — **старт разрешён 06.09**, ветка `feature/account-screens-unify-style`.

## Журнал

### Ф0 Единый стиль — `[~]` В РАБОТЕ (код готов, ждёт device-проверки)
Ветка `feature/account-screens-unify-style`, 7 коммитов `80bdd1e..5c8bf6b`. Не смержено, не запушено.

- `[x]` **Ф0.1** `80bdd1e` — `AccountActionsRow` (круглые 46pt) у всех типов; pill-ряд `genericActions`
  снят, у вклада и кредита панель появилась впервые (было 3 тапа до действия). `AccountActionSheetItem`
  слит с `AccountActionItem` — один тип на кнопку ряда и пункт меню.
- `[x]` **Ф0.2** `c9466e3` — `confirmationDialog` экспорта в календарь → `AccountActionsSheet`.
  Toolbar-`Menu` инвестиций и кредитки сняты ещё в Ф0.1: «···» теперь один, в ряду действий,
  а в toolbar остаётся только когда ряда нет (архивный/read-only счёт).
- `[x]` **Ф0.3** `bd718ed` — суммы через `AmountTextField` (доход/расход, перевод, возврат по дебетовой);
  парсинг через `AmountTextField.canonical` (раньше разряды с пробелами ломали `Decimal(string:)`);
  автофокус там, где поле суммы первое.
- `[x]` **Ф0.4** `02a22d8` — модификатор `accountSheetChrome(detent:)` на 12 листов без детентов;
  Save/Cancel кредитки с иконок на текст.
- `[x]` **Ф0.5** `3258bd7` — 4 `.alert` и 4 `@State`-флага → одно состояние `Confirmation` + лист снизу.
  Алерт ошибки оставлен (сообщение сервиса, не выбор действия).
- `[x]` **Ф0.6** `e54c640` — 33 ключа локализации кредитки (ru/en/zh-Hans), правка `xcstrings` строго
  аддитивная.
- `[x]` **Ф0.7** `5c8bf6b` — 4 `NumberFormatter` в `static let`, `sortedEvents` один раз на секцию,
  guard от повторного `loadAccounts` в форме создания.

**Гейт:** `** BUILD SUCCEEDED **`; `millioTests` 2710 passed / 23 failed — внутри baseline (2690–2720 / 18–23).
Шесть красных вне известного списка (`AccountsTotalsServiceTests` ×2, `RealEstateProductTests/atomicEditRollback`,
`ProfileLocalizationTests`(zh-Hans), `AccountsCoreAdditionBridgeTests`, `FinanceAddAccountProductCounterTests`)
перепроверены изолированно на `develop` — падают там же, к Ф0 отношения не имеют.

**Осталось по Ф0:** device-скрины трёх переработанных типов (вклад, кредит, кредитка) — без владельца
не закрывается.

### Ф1 Декомпозиция — `[x]` РЕАЛИЗОВАН (ждёт мержа)
Ветка `feature/account-screens-decompose`, 2 коммита `a3d5ff9`, `98cd0fe`. Не смержено, не запушено.

- `[x]` **Ф1.1** `a3d5ff9` — `AccountDetailView` 1789 → 294 строки каркаса (состояние, `ActiveSheet`/
  `Confirmation`, `body`) + 9 файлов рядом: Header 130 · Liability 77 · Deposit 122 · Market 167 ·
  Actions 220 · Forecast 55 · History 93 · Support 38 (общие форматтеры) · `View+Sheets` 640.
- `[x]` **Ф1.2** `98cd0fe` — `FinanceAddAccountView` 1650 → 406 строк каркаса + 6 файлов:
  FormSections 500 · CoreCreate 379 · Validation 142 · Entitlements 135 · RealEstate 67 · Statement 59.

**Что пришлось изменить сверх перемещения** (иначе не компилируется): у членов обоих типов снят
`private` — в Swift он не проходит границу файла, а тип теперь живёт в расширениях. По той же причине
`InvestmentCategory.isMarketTickerCategory` перестал быть `private extension`. Логика не менялась.
Отдельного `AccountDetailDepositSection`-дубля не возникло: существующий `Deposit/DepositDetailSection.swift`
— это View, а вынесенный файл — вычисления вклада для экрана.

**Гейт:** `** BUILD SUCCEEDED **`; `millioTests` 2705 passed / 28 failed. Passed внутри baseline
(2690–2720). Красных больше верхней границы baseline (23), но набор имён плавает от прогона к прогону
(25 в первом, 28 во втором, пересечение неполное) — изоляционные флаки параллельных клонов: 24 из 25
красных первого прогона проходят при изолированном перезапуске. Единственный стабильно красный —
`QuickSetupApplierTests.testApplyCreatesSelectedGroupsAndAssignsProductsToThem` — воспроизведён на
`develop`, к Ф1 отношения не имеет.

**Найдено по пути (не чинил, Ф1 — только перенос):**
1. `AccountDetailForecastSection.depositForecastSection` — мёртвый код: в `body` не вызывается
   (одноимённый метод `FinanceDynamicsView:1600` — другой). Кандидат на снос в Ф2.
2. `.dd-*/` (локальные derivedDataPath) не были в `.gitignore` — добавлены.

**Инцидент:** параллельная сессия сделала `git merge feature/entry-screen-simplify` на моей ветке
(reflog `HEAD@{4}`), приняв её за `develop`. Ветка перебазирована на `develop` — чужие 9 коммитов
остались в `feature/entry-screen-simplify`, ничего не потеряно, но их мерж в `develop` так и не сделан.

## Открытые вопросы
1. Скрины текущих экранов дебетовой карты и наличных — для макетов Ф2/Ф4 (владелец пришлёт).
2. `AccountProductTransitionSection:132` — `confirmationDialog` внутри формы правки. Намеренно не тронут
   в Ф0: система и так показывает его листом снизу, замена дала бы только другую обводку. Решить, нужен
   ли единый вид, вместе с Ф1.
