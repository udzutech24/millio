# Единый источник правды для totals (Дашборд / Счета / Динамика) — 2026-07-05

**Статус:** РЕАЛИЗОВАН (фазы 1–3), Фаза 4 — ЗАБЛОКИРОВАН (осознанно отложена, см. ниже)
**Ветка:** `feature/unified-totals` (от `develop@258295d`, ядро AccountsCore уже смержено)
**Владелец распорядился:** устранить класс бага «разные экраны показывают разный итог».

---

## 1. Диагноз (верифицирован на HEAD, все file:line проверены)

### 1.1. Три экрана — три места, где считается «итог»

| Экран | Функция | Файл:строки |
|---|---|---|
| Заголовок «Динамика» / дельта | `updateCurrentBalanceAndDelta()` → `calculateBalanceAtDate(...)` | `FinanceDynamicsViewModel.swift:820-910, 1787-2119` |
| Дашборд + экран «Счета» (общий баланс, оба берут `state.totalAmount`) | `FinanceViewModel.calculateTotalAmountAsync()` → `FinanceTotalsService.calculateTotalsSnapshot()` | `FinanceViewModel.swift:944-953`, `FinanceTotalsService.swift:62-142` |
| (мёртвый код, не используется нигде) | `calculateTotalForAllGroups()` | `FinanceDynamicsViewModel.swift:2326-2337` |

### 1.2. Таблица отличий формул ДО фикса

| Параметр | Динамика (`calculateBalanceAtDate`) | TotalsService (`getAccountAmount`) |
|---|---|---|
| `card.includeInTotal` | фильтрует (`continue`, :1821) | фильтрует (внутри `CardSnapshotFactory.netWorthAmount`, обнуляет) |
| `card.archivedAt` | фильтрует, если `date > archivedAt` (:1817) | **НЕ фильтрует вообще** |
| `credit.includeInTotal` | фильтрует (:1963) | было: **НЕ фильтрует вообще**; исправлено (см. Фазу 3). НО: практического эффекта на прод нет — см. врезку ниже (нормализатор) |
| `credit.archivedAt` | фильтрует (:1959) | **НЕ фильтрует вообще** — реальный, воспроизводимый баг |
| `investment.includeInTotal` | фильтрует (:2013) | фильтрует (:290) |
| `investment.archivedAt` | фильтрует (:2009) | **НЕ фильтрует вообще** |
| Liability-знак (кредит/кредитка) | `debtAsNegative && isLiabilityAccount` → `-abs(...)`, иначе `+` (:2104-2109) | credit: всегда `-remainingAmount`; card: знак уже внутри `CardSnapshotFactory` (`-debt` для credit-карты) — по факту эквивалентно `debtAsNegative=true` всегда |
| Валюта: курс | `historicalRateStore.getRate(on: date, ...)` — для `date == сегодня` **делегирует напрямую в `currencyService.getRate`** (`CurrencyRateService.swift:187-189`) | `currencyService.getRate(from:to:)` напрямую |
| Валюта: custom-курсы пользователя | учитываются (через `getRate`, т.к. на сегодня историч. стор делегирует туда же) | учитываются |
| Вклад AccountsCore (новое ядро) | **НЕ добавляется** в реальном заголовке (см. 1.3) | добавляется (`newCoreTotalProvider` → `accountsTotalsService.totalAt`) |

**Вывод:** реальный, воспроизводимый на HEAD баг — отсутствие фильтра `archivedAt` (все 3 типа: card/credit/investment) в `FinanceTotalsService`. Именно это воспроизводит класс бага «разные экраны — разный итог» (напр. архивный кредит с непогашенным долгом продолжает вычитаться из Дашборда/Счетов бесконечно, а в Динамике корректно исчезает после архивации). Курсовая часть на «сегодня» фактически совпадает (обе ветки сходятся к одному и тому же `currencyService.getRate`), поэтому трогать её не нужно — риск того, что не стоит выгоды (см. 1.4).

**Отдельная находка при написании регрессионного теста — `credit.includeInTotal` практически недостижим.** `FinanceAccountService.normalizeCreditsIncludeInTotal` (вызывается на КАЖДОМ `loadAccounts()`) принудительно ставит `credit.includeInTotal = true` для всех кредитов и сразу сохраняет это в SwiftData — экспериментально подтверждено юнит-тестом (создали кредит с `includeInTotal: false`, после `handle(.loadAccounts)` флаг уже `true`). UI (`FinanceAddAccountView`/`InlineCreateForms`) даёт пользователю переключатель "включить в тотал" для кредита, но он не работает — значение затирается почти сразу после сохранения. Это отдельный, не связанный с текущей задачей баг (сломанный тоггл), НЕ фиксится в этой сессии — фиксирую здесь как находку для отдельного тикета. Из-за этого фикс `credit.includeInTotal` в `FinanceTotalsService` (Фаза 3) — правильная защитная канонизация (не хуже, симметрично Card/Investment), но **не меняет никаких реальных чисел у пользователей сегодня**, т.к. состояние `includeInTotal=false` у кредита недостижимо в проде.

### 1.3. Второе, отдельное расхождение — НЕ входит в текущий фикс (см. Фаза 4)

`calculateTotalForAllGroups()` (:2326) и его комментарий утверждают, что «Analytics-тотал» уже складывается с вкладом AccountsCore той же функцией, что и Дашборд (`accountsTotalsService.totalAt`). **Это неверно на практике**: `calculateTotalForAllGroups()` — мёртвый код, ничего его не вызывает (проверено `grep` по всему репо). Реальный заголовок «Динамика» (`state.currentBalance`, выставляется в `updateCurrentBalanceAndDelta`) вклад AccountsCore не добавляет вообще. Значит: счёт, созданный через новый экран (`InlineDepositCreateForm` / AccountsCore), попадёт в тотал Дашборда и «Счетов», но не в заголовок «Динамика» — воспроизводимое расхождение, если у пользователя есть хоть один AccountsCore-счёт.

Существующий тест `FinanceTotalsServiceAccountsCoreTests.swift` (AC2) проверяет только точку интеграции внутри `FinanceTotalsService` — не проверяет реальный путь Dynamics-заголовка. Его докстринг «Accounts-тотал и Analytics-тотал получают вклад нового ядра из ОДНОЙ функции» **не подтверждён для реального кода** (см. Фаза 4).

Прежняя команда (`plans/2026-07-02__accounts-system-audit.md`, Фаза 3/5) уже проанализировала близкий класс проблемы (три пути тотала, R1) и явно отложила полную интеграцию AccountsCore в Dynamics-режимы `byAccounts`/`singleAccount` на «Фазу 1b» — с обоснованием (доп. сложность: delta, single-account fast path, синхронизация выбора счетов).

### 1.4. Почему НЕ трогаем источник курса (осознанное решение)

`HistoricalRateStore.getRate(on: today, ...)` при `Calendar.current.isDateInToday(date)` в `CurrencyRateService.getHistoricalRate` **напрямую делегирует в `getRate`** (`CurrencyRateService.swift:187-189`) — т.е. для «сегодня» (единственная дата, которая интересует Дашборд/Счета) оба пути СХОДЯТСЯ к одному и тому же вызову, включая учёт custom-курсов пользователя. НО `HistoricalRateStore` сначала проверяет собственный SwiftData-кэш точного курса на дату (`fetchExactRate`) — если запись за «сегодня» уже была закэширована раньше (например, утром), `HistoricalRateStore` вернёт её, даже если `currencyService` уже обновил live-курс. Переключение Дашборда на `HistoricalRateStore` могло бы сделать его *менее* свежим, чем сейчас (регрессия), ради устранения различия, которое и так почти всегда равно нулю на «сегодня». Не делаем — минимально инвазивный фикс, не God-рефактор.

---

## 2. Решение — канон

Прагматичный выбор: **не переписывать на AccountsCore** (снос легаси — отдельная задача 6b). Вместо этого — вынести общую для legacy-счетов (Card/Credit/Investment) политику «включён ли счёт в тотал и с каким знаком» в один файл, и звать её из ОБОИХ мест.

**Канон: `AccountTotalPolicy`** (новый файл `millio/UI/Services/Finances/AccountTotalPolicy.swift`) — statless enum с двумя чистыми функциями:
- `isActive(includeInTotal:archivedAt:at:)` — единый предикат участия счёта в тотале на дату.
- `signedContribution(_:isLiability:debtAsNegative:)` — единый знак liability-счёта.

Почему канон здесь, а не в `FinanceDynamicsViewModel`/`AccountsCore`: `calculateBalanceAtDate` — это тяжёлый historical-replay движок (кэши транзакций, реконструкция баланса по датам), избыточный для получения "тотала на сегодня", который нужен Дашборду. Вместо того чтобы заставлять Дашборд тянуть весь этот движок (тяжелее, больше отказов), выносим ТОЛЬКО чистую логику принятия решения (фильтр+знак) — обе стороны продолжают считать сырую сумму по-своему (Dynamics — replay, TotalsService — текущее состояние модели), но решение "включать ли и с каким знаком" — одно и то же.

### Что меняется в коде

1. **`FinanceDynamicsViewModel.calculateBalanceAtDate`** — рефакторинг БЕЗ изменения поведения: 3 инлайн-фильтра (`card`/`credit`/`investment`) и финальный sign-switch заменяются на вызовы `AccountTotalPolicy`. Формула Dynamics не меняется ни на копейку — это подготовка канона, не фикс.
2. **`FinanceTotalsService.getAccountAmount`** — добавляются недостающие проверки через `AccountTotalPolicy.isActive` (archivedAt — для card/credit/investment; includeInTotal — для credit). **Это меняет числа на Дашборде/Счетах** (см. раздел 3).
3. Удаление мёртвого кода: `calculateTotalForAllGroups()` + приватный `calculateGroupTotal(group:)` в `FinanceDynamicsViewModel` (нигде не вызываются, подтверждено grep) — их наличие вводит в заблуждение (ложно намекают, что AC2 покрывает Dynamics-заголовок). Комментарий в `FinanceTotalsService` про `newCoreTotalProvider` уточнён — убрана ссылка на несуществующий живой путь, добавлена ссылка на этот план.

---

## 3. Что изменится в числах для пользователя (ОЖИДАЕМО и ПРАВИЛЬНО)

После фикса Дашборд/«Счета» станут **строже** (числа могут уменьшиться), а не наоборот:
- **Архивные счета** (карта/кредит/инвестиция с `archivedAt != nil`) больше не будут пожизненно висеть в общем балансе Дашборда/Счетов — они и раньше корректно исчезали из Динамики, теперь исчезают одинаково везде. Если у пользователя есть архивный кредит с непогашенным остатком — общий баланс Дашборда **вырастет** (кредит-обязательство пропадёт из вычитания).
- **Кредиты с `includeInTotal == false`** — фильтр добавлен симметрично Card/Investment, но **практического эффекта нет**: `FinanceAccountService.normalizeCreditsIncludeInTotal` не даёт этому состоянию сохраниться (см. находку в разделе 1.2) — отдельный баг, не в этой сессии.
- Все три экрана (Динамика / Дашборд / Счета) теперь **всегда совпадают** для одного и того же набора legacy-счетов (Card/Credit/Investment) — независимо от архивации (и, после починки отдельного бага с нормализатором, от `includeInTotal` кредита тоже).
- **НЕ меняется:** живые (неархивные) счета с `includeInTotal == true` — те же суммы, что и раньше.
- **Известное ограничение, сохраняется:** AccountsCore-счета (новый экран, вклады/др.) по-прежнему не в заголовке «Динамика» (см. 1.3, Фаза 4).

---

## 4. Фазы

- [x] **Фаза 1 — канон `AccountTotalPolicy`.** Новый файл, чистые функции, покрыт unit-тестами (nil archivedAt / archivedAt в прошлом / архив в будущем / includeInTotal=false / liability-знак / не-liability).
  Статус: РЕАЛИЗОВАН.
- [x] **Фаза 2 — рефакторинг `FinanceDynamicsViewModel`.** `calculateBalanceAtDate` использует `AccountTotalPolicy` вместо инлайн-проверок. Поведение не меняется (существующие Dynamics-тесты должны пройти без изменений). Удалён мёртвый код `calculateTotalForAllGroups`/`calculateGroupTotal(group:)`.
  Статус: РЕАЛИЗОВАН.
- [x] **Фаза 3 — хардненинг `FinanceTotalsService`.** `getAccountAmount` фильтрует archivedAt (card/credit/investment) + includeInTotal (credit) через `AccountTotalPolicy`. Комментарий про `newCoreTotalProvider` уточнён (ссылка на этот план вместо мёртвой `calculateTotalForAllGroups`). Регрессионный тест консистентности: один набор legacy-счетов (обычный/`includeInTotal=false`/архивный/кредит/кредитка с долгом/мультивалюта) → тотал Dynamics == тотал TotalsService.
  Статус: РЕАЛИЗОВАН.
- [ ] **Фаза 4 (ЗАБЛОКИРОВАН, отдельная сессия) — AccountsCore в заголовке «Динамика».** Добавить `financeViewModel.accountsTotalsService.totalAt(date, in:)` в `updateCurrentBalanceAndDelta` для случая «все счета, без фильтра по группам/аккаунтам» (`state.selectedGroupIDs.isEmpty && state.selectedAccountIDs.isEmpty && !state.isSingleAccountMode`), аналогично уже существующему паттерну для графика (`ChartDataPoint.mergingNewCoreSeries`, Фаза AC3). Требует: учёт в `periodDelta` (стартовый баланс тоже должен включать AccountsCore на `startDate`), impact на single-account fast path, /stress-test (трогает протестированную дельту). НЕ реализовано в этой сессии — не было явно авторизовано, требует отдельного stress-test и решения владельца о размере (вероятно M). Зафиксировано здесь, чтобы не потерялось.

---

## 5. Тесты

- Новый: `millioTests/UI/Services/Finances/AccountTotalPolicyTests.swift` — чистая логика политики.
- Новый: `millioTests/UI/Services/Finances/FinanceTotalsServiceFilterConsistencyTests.swift` — регрессия: набор из 7 счетов (активная карта / исключённая карта / архивная карта / кредитка с долгом / кредит / архивный кредит / мультивалютная инвестиция) → `FinanceTotalsService` и `FinanceDynamicsViewModel` дают одинаковый итог.
- Прогнаны прицельно: `FinanceTotalsServiceAccountsCoreTests`, `FinanceViewModelTests` (использует `calculateGroupTotal(group:in:)` — другой метод, не удалённый), Dynamics-тесты, которые дергают `calculateBalanceAtDate`/`updateCurrentBalanceAndDelta`.

---

## 6. Impact-анализ

- **Регрессия:** пользователи с архивными счетами (карта/кредит/инвестиция) увидят иное (более корректное) число на Дашборде/Счетах. Это ожидаемо и коммуницируется как есть в этом плане — не bug report. `credit.includeInTotal` эффекта не даёт (см. находку в 1.2/3).
- **Offline:** оба пути — чистые in-memory расчёты по SwiftData-моделям, offline не влияет.
- **CloudKit:** не затронут (это не backup/restore).
- **Side effects:** удаление мёртвого кода не имеет side effects (0 вызывающих кодов, подтверждено).
