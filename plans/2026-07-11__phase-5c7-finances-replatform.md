# План: Ф5c.7 — реплатформинг Finances-слоя на AccountsCore (слито с Ф6)

**Дата создания:** 2026-07-11 · **Статус:** RESEARCH+SPEC+PLAN готовы, РЕАЛИЗАЦИЯ НЕ НАЧАТА · **Тип:** L (2-3 сессии) · **Родитель:** `plans/2026-07-07__legacy-accounts-purge-path-b.md`, секция «⛔ Блокер Ф5c.6», remaining-scope 5c.7. Разблокирует Ф2c (унификация `orderedAccounts`/`calculateGroupTotal`/per-account chart-modes) и открывает путь к 5c.8–5c.11 (снос @Model).

**Baseline для всех гейтов этого плана:** `xcrun xcresulttool` **1745 passed / 14 failed** (develop @ `aea084a`, HEAD на момент старта Ф5c.7 — `dda6b5e`, docs-only поверх `aea084a`, baseline не меняется). Любая под-фаза обязана дать 0 новых красных относительно этого числа — **сравнивать список идентификаторов упавших тестов, не только счётчик** (Fable-риск №10: миграция одного из 14 baseline-красных на другую причину не должна маскироваться как «то же самое число»).

> **Fable-ревью §0 (2026-07-11, до старта кода)** — независимая проверка plan-review + стресс-тест. Полный текст риска/митигации ниже по тексту рядом с соответствующей под-фазой. Верифицированы все file:line из §1 (актуальны); 3 минорных расхождения без влияния на план: `AccountEventType` — 15 case, не 14; `createMoneyAccountOnNewCore` def `:1121`/call `:1263` (не `:1275`); FDVM-метод называется `orderedAccounts(in:)`, не `(for:)`. Два содержательных вывода учтены ниже (5c.7.0 и 5c.7.1 скорректированы).

> **⚠️ МЕТОДОЛОГИЯ ГЕЙТОВ — обновлено после верификации 5c.7.0 (2026-07-11).** Заголовочный baseline **1745/14 устарел и неточен** — независимый прогон Fable-верификатора на том же коммите `dda6b5e` дал **1771/14**, расхождение 26 тестов, плюс сам сьют флакует ±1-2 между последовательными прогонами без каких-либо изменений (параллельный запуск/shared-state, не архитектурная проблема этого плана). Дальше по плану применяется **скорректированный протокол гейта**, а не сравнение с числом 1745/14:
> 1. Перед каждым гейтом — свежий прогон на ЧИСТОМ HEAD без диффа под-фазы (`git stash -u` → xcresulttool → `git stash pop`) — это и есть baseline для этого конкретного гейта, не число из шапки.
> 2. Сравнивать **сет ID failed-тестов**, не счётчик.
> 3. Любой ID, которого нет в свежем clean-baseline сете, но есть в прогоне с диффом — не считать красным гейтом сразу: перепрогнать этот ID изолированно (`-only-testing`) 1 раз. Зелёный изолированно → флак, не блокирует. Красный изолированно дважды подряд → настоящая регрессия, стоп-правило.
> 4. Это не ослабление гейта — фактическая строгость та же (0 новых детерминированных красных), просто протокол сравнения починен под реальное поведение сьюта.

**Открытый вопрос владельца, закрываемый этим планом:** rich-редактирование существующего счёта (rename/currency/группа/мета/иконка) недоступно юзеру с Ф1 — `AccountsCoreService` не имеет `updateAccount`, легаси rich-editor снесён как runtime-мёртвый (`1b4e60f`). Решение — строить в под-фазе 5c.7.0 (см. ниже), это не регрессия, а закрытие давнего пробела.

---

## 1. Research — что реально зависит от легаси (file:line)

### 1.1 `FinanceViewModel.swift` (1874 строк, 68 легаси-строк, живая — вход `RootTabView.swift:337`)

| Роль | Символ | Легаси-тип |
|---|---|---|
| Published state | `state.groups` | `[FinanceGroup]` |
| Published state | `availableCards/Credits/Investments` | `[Card]`/`[Credit]`/`[Investment]` |
| Кэш | `cardByID/creditByID/investmentByID` | `[String: Card/Credit/Investment]` |
| Экшен | `editGroup(FinanceGroup)`, `removeAccountFromGroup(FinanceAccount)`, `showAccountDynamics(FinanceAccount)` | параметры легаси |
| Экшен (data-critical) | `.physicallyDeleteLegacyAccount(FinanceAccount)` — case `:174`, handle `:499-500`, impl `:1332-1333` → `accountService.physicallyDeleteLegacyAccount` | вызывается из `FinanceDynamicsView.swift:1445` (purge-footer) |
| Расчёт (Ф2c-блокер (в)) | `calculateGroupTotal(group: FinanceGroup, …)` `:892` | ключён на легаси, схлопнётся сам после сноса, НЕ трогать напрямую |
| Мост | `orderedAccounts(for:)` `:970` — 1 из 3 определений (см. §1.3), `FinanceGroup → [FinanceAccount]` |
| Мост | `legacyAccountConverter`, `resolveCoreGroup` — уже существующие точки конвертации легаси↔core (переиспользовать, не изобретать заново) |

Потребители во View (через `getAccountInfo`/`FinanceAccountRow`, 8 файлов): `FinanceQuickEditAccountView`, `FinanceDynamicsView`, `FinanceOverviewCardView`, `FinanceGroupEditorView`, `FinancesSheets`, `FinanceRows` (+2). Уже на core: дуальный рендер `FinanceRows` (легаси) + `newCoreAccounts` (core) сосуществуют на экране «Счета».

### 1.2 `FinanceDynamicsViewModel.swift` (2915 строк, 57 легаси-строк, живая — экран «Динамика»)

- Fetch: `FetchDescriptor<Card/Credit/Investment>()` `:523-529` — единственная точка чтения легаси в этом файле.
- State/кэш: `state.groups: [FinanceGroup]`, `cardsCache: [String: Card]`.
- Per-account chart-modes (byAccounts/singleAccount, Ф2c-блокер «1b») живут внутри этого God-VM, завязаны на тот же fetch.
- **Уже реализован механизм «один источник правды» (6b, инвариант держит тест):** `aggregateGroupRows`/`signedAccountValue` — per-account строки считаются один раз, `.groups` = агрегация тех же строк; `addingCoreContribution` заменил снесённый `mergingNewCoreSeries` (stitching истории графика core-вклада, без задвоения). Инвариант `Total(Groups) == Total(Accounts)` закреплён тестом **`FinanceTotalsServiceFilterConsistencyTests`** (AC1/AC2) — **нельзя сломать**.
- `coreContributionWithLegacyPredecessor`/`legacyPredecessorContribution` — общий путь Cashflow/Dynamics для стартового Assets-at-period (багфикс 2026-07-10, `86e9918`) — трогать только через этот общий путь, не дублировать.
- Protected Dynamics-тесты — 6 файлов, ~3347 строк (полный сьют этого кластера — держит регресс графика/breakdown); прогонять после каждого шага 5c.7.4.

### 1.3 `FinanceAccountService.swift` (568 строк, 47 легаси-строк) / `FinanceGroupService.swift` (292 строки, 23 легаси-строки)

Публичные методы `FinanceAccountService` с легаси-типами: `loadAccounts()`, `addAccountToGroup(accountType:accountID:group:FinanceGroup?)`, `removeAccountFromGroup(_:FinanceAccount)→UnderlyingAccountKind`, `deleteAccountPermanently(_:FinanceAccount)→UnderlyingAccountKind`, `legacyRelatedTransactionCount(for:FinanceAccount)→Int`, `physicallyDeleteLegacyAccount(_:FinanceAccount)`, `restoreArchivedAccountToGroup(...)`, `updateUnderlyingArchiveState(...)×2`. Приватные: `normalizeCreditsIncludeInTotal`, `normalizeMarketAssetIdentities/QuoteLookupKeys`, `rebuildAllAccountCaches`, `cleanupInvalidFinanceAccounts`, `resolveUngroupedGroup()→FinanceGroup`.

**Важная граница скоупа:** `FinanceAccountService.swift:107/146` также инициализирует `CardCatalog`/`CardManager` — эти кэши потребляются Cashflow/Cashback-пикерами (`CashflowViewModel`, `CashbackViewModel`), НЕ Finances-слоем напрямую. Это отдельный узел (5c.6-кластер/будущая Cashback-миграция, вне 5c.7). **5c.7 переносит типизацию FinanceAccountService/FinanceGroupService на `Account`/`AccountGroup`, но НЕ трогает populate-логику `CardCatalog`/`CardManager`** — она либо остаётся как узкий residual-метод внутри сервиса (минимальный диф), либо переезжает в отдельный маленький сервис, если типы разойдутся. Решается на месте в 5c.7.2, не заранее.

`FinanceGroupService`: `visibleGroupsForList()→[FinanceGroup]`, `orderedAccounts(for:)` (1 из 3 определений — второе, третье в `FinanceViewModel:970`/`FinanceDynamicsViewModel:2868`), `deleteGroup`, `updateGroup`, `moveGroup`, `normalizeHiddenGroupOrders`, `nextAccountOrder`, `syncCoreGroup(oldName:newName:colorHex:displayCurrency:)` (уже существующий мост легаси-имя→core-группа, переиспользовать).

**Найден механизм дубля «Ungrouped» (гипотеза агента, подтверждена чтением):** `FinanceGroupService.swift:75-81` — `shouldHideGroupInList` скрывает легаси-Ungrouped-группу ТОЛЬКО когда `visibleAccountsForGroup(group).isEmpty && coreAccountsCount(group) == 0`. Если на core-стороне позже появляется свой «Ungrouped»-эквивалент (`AccountGroup`) — это будет ВТОРАЯ видимая пустая группа с тем же именем: `AccountGroup`/`AccountsCore` **не имеет** системного Ungrouped-эквивалента (grep `system|Ungrouped|ungrouped` по `millio/Core/AccountsCore` — 0 хитов). Единственный текущий Ungrouped — легаси `FinanceGroup` с именем `ungroupedGroupName`. Значит дубль возникает не от двух Ungrouped-сущностей сейчас, а от рассинхрона видимости легаси-группы против core-счетов без группы, отображаемых отдельным блоком в `FinanceRows` (дуальный рендер). **5c.7.1 обязан ввести ОДИН канонический Ungrouped на стороне `AccountGroup`** (или явный «no group» statuс на `Account`) и убрать легаси `resolveUngroupedGroup()`/`shouldHideGroupInList`-развилку — это устраняет баг структурно, не патчем видимости.

`AccountsCoreAdditionBridge.resolveAccountGroup(matching financeGroup: FinanceGroup?)` `:66` — вызывается `QuickSetupApplier:135`, `FinanceAddAccountView` ×4 — существующий мост легаси-группа→core-группа при CREATE, переиспользовать как образец для 5c.7.1.

### 1.4 `AccountsCoreService` (560 строк) — API-карта + гэп rich-edit

18 public-методов: `createAccount`, `recordEvent`, `adjustBalance`, `buy`/`sell`, `revalue`, `upsertEvent`, `transfer`, `archiveAccount`/`restoreAccount`, `physicallyDelete` и т.д. (event-sourcing, 14 `AccountEventType`). **`updateAccount` подтверждённо отсутствует** (grep `updateAccount|rename|editAccount|updateMeta|setName` по `millio/Core/` = 0 хитов, перепроверено). `AccountDetailView` (`FinanceRows.swift:394`) правит ТОЛЬКО баланс (`adjustBalance` `:505/728`) и архив (`archiveAccount` `:818`). `createMoneyAccountOnNewCore` (`FinanceAddAccountView.swift:1275`) — CREATE-only, доказанно непригоден для EDIT (bug Ф6a при переиспользовании).

Легаси rich-EDIT снесён коммитом `1b4e60f` (2026-07-11, обоснованно — путь был runtime-мёртв для мигрированного юзера): `FinanceDynamicsView.fullProductEditSheetContent`/`showFullProductEditSheet`/резолверы `resolvedCard/Credit/Investment`; `FinanceAddAccountView.editingCard/Credit/Investment`/`isEditingMode`/`makeLegacyCard`+6 легаси-writers. Три легаси-VM (`CardViewModel`/`CreditViewModel`/`InvestmentViewModel`) НЕ удалены — они backing живой CREATE-формы (`InlineCreateForms.swift`), декаплинг которых отдан в 5c.7.5 (было отложено в Ф6 по плану-родителю).

---

## 2. Spec — целевое поведение

### 2.1 Инварианты, которые нельзя сломать
1. **`Total(Groups) == Total(Accounts)`** — held by `FinanceTotalsServiceFilterConsistencyTests`. Любой рефакторинг group-агрегации обязан гонять этот тест на каждом шаге 5c.7.1/5c.7.4.
2. **Один источник правды breakdown**: per-account строки считаются один раз, group-агрегация — производная (`aggregateGroupRows`-паттерн), не отдельный расчёт. Новый `Account`-based код обязан следовать этому же паттерну, не вводить второй параллельный путь агрегации.
3. **`isEditingLegacy`-гуард моста** (`AccountsCoreAdditionBridge`) остаётся — защищает от дубликата при повторном использовании CREATE-пути для EDIT (тест `AllPresetsOnNewCoreTests:157-183`).
4. **Protected Dynamics-тесты** (6 файлов ~3347 строк) — 0 новых красных на каждом гейте 5c.7.4/5c.7.6.
5. **Легаси archive/restore/physicallyDeleteLegacyAccount продолжают работать** для оставшихся немигрированных легаси-записей (если есть) до момента, пока `Card`/`Credit`/`Investment` @Model физически существуют (до 5c.11) — 5c.7 переносит ТИПИЗАЦИЮ VM/сервисов на core, не удаляет @Model и не обрывает fallback для граничных случаев.
6. **`CardCatalog`/`CardManager` populate-логика** (Cashflow/Cashback-потребители) не регрессирует — переносится/сохраняется как отдельный узел, не как побочный эффект типовой миграции.
7. **[Fable-ревью] Backup/restore roundtrip.** Новые события/поля (`updateAccount`, `AccountGroup.customIconName`) обязаны переживать CloudKit backup→restore без потери и без краша на старом бэкапе, снятом до появления этих полей. Roundtrip-тест — часть гейта 5c.7.0 (для updateAccount-событий) и 5c.7.6 (для customIconName).
8. **[Fable-ревью] Смена валюты счёта в v1 `updateAccount` — ЗАПРЕЩЕНА.** Прямая мена валюты мутацией истории событий = переинтерпретация сумм задним числом (100000 RUB молча читается как 100000 USD) = порча пользовательских данных. 5c.7.0 разрешает менять name/группу/мета/иконку; смена валюты — либо отдельное `revalue`-событие с явной конвертацией (вне скоупа 5c.7.0), либо явный disabled-стейт в UI. Не реализовывать смену валюты как побочный эффект rename-формы.
9. **[Fable-ревью] Mixed-store как явный тест-кейс.** 5c.7.3/5c.7.4 обязаны иметь fixture с ОДНОВРЕМЕННО core-счетами и непроконвертированными legacy-записями (не только «чистый core» или «чистый legacy») — иначе `FetchDescriptor<Account>`-миграция тихо теряет legacy-хвост из графика/breakdown/пикеров.

### 2.2 Целевое поведение — экран «Счета» / «Динамика» после 5c.7
- `FinanceViewModel`/`FinanceDynamicsViewModel` читают `[Account]`/`[AccountGroup]` как первичный источник; легаси-@Model остаются только как fallback-чтение для непроконвертированных edge-case записей (если такие в принципе остаются после Ф1 — по факту это должно стремиться к нулю для реальных юзеров).
- Один канонический Ungrouped на стороне `AccountGroup` — устраняет дубль.
- `orderedAccounts`/`getAccountInfo`/`FinanceAccountRow`-каскад — единая core-типизированная реализация вместо 3 легаси-дублей.
- Rich-edit существующего счёта (rename/currency/группа/мета/иконка) — доступен юзеру через `AccountDetailView` + новый `AccountsCoreService.updateAccount` (event-sourced: имя/валюта/мета/группа как отдельные события или прямые поля-мутации на `Account`, согласовать с существующей event-моделью, не ломая `adjustBalance`/`archiveAccount`).
- Экран «Счета» (Ф6, слито сюда): stacked-полоса активы/обязательства с нетто, секции «Активы»/«Обязательства» с подытогами, `AccountGroup.customIconName` (уже найден паттерн `AccountIconPickerSheet`/`FinanceOverviewLedgerPresentation` — переиспользовать, поле добавляется additive без V6-бампа схемы). Без чипа прироста/sparkline в шапке «Счетов» (решение владельца 2026-07-08 — не дублировать Динамику).

---

## 3. План по под-фазам (гейт на каждой: build 0 ошибок; `xcrun xcresulttool` 0 новых красных vs baseline 1745/14; device stress-test — только для фаз, трогающих архив/удаление/реальные пользовательские данные; `/stress-test` + явное «да» владельца перед мержем каждой под-фазы, как во всех предыдущих фазах плана-родителя)

### 5c.7.0 — `AccountsCoreService.updateAccount` API + минимальный вход (M, фундамент, закрывает открытый вопрос владельца) — [x] РЕАЛИЗОВАНО, Fable-подтверждено, закоммичено (2026-07-11)
> updateAccount — прямая мутация полей + save (не событие, обоснованно проще); иконка исключена из скоупа (нет backing-поля в ядре, добавление было бы мёртвым кодом — переносится в 5c.7.6 вместе с `AccountGroup.customIconName`); инвалидация кэша при смене группы не потребовалась (кэш не group-keyed, доказано тестом AC3). Device-тест редактирования 3 типов счетов — PENDING (нужен телефон владельца вечером).
- **[Fable-ревью, скоуп сужен]** Спроектировать и реализовать `updateAccount` (имя/группа/мета/иконка — **БЕЗ смены валюты**, см. §2.1 инвариант 8) на event-sourced модели, согласованно с `adjustBalance`/`archiveAccount`.
- Минимальный UI-вход в `AccountDetailView` (простая форма rename/группа/мета, НЕ полноценный `FinanceAddAccountView`-based rich-editor).
- **Полноценный rich-edit UI (переиспользование `FinanceAddAccountView` в режиме prefill-from-core) — ПЕРЕНЕСЁН в 5c.7.5**, после того как эта форма перетипизирована на core (иначе двойная работа: строить prefill на легаси-типизированной форме, потом перетипизировать её же в 5c.7.5 — риск реинкарнации дубликат-бага Ф6a, если prefill трогает CREATE-путь раньше времени).
- Тест: create→updateAccount(rename/group/meta)→verify, не создаёт дубликат (регресс-guard по аналогии с `AllPresetsOnNewCoreTests`).
- Тест: backup→updateAccount-событие→restore roundtrip (инвариант 7).
- Гейт: build+xcresulttool; device-тест редактирования 3 разнотипных счетов (card/credit/investment-эквивалент на core) — минимальной формы, не финального UI.

### 5c.7.1 — `FinanceGroupService` → `AccountGroup` (S/M)
- **[Fable-ревью, скорректировано] Канонический Ungrouped = `account.group == nil`, НЕ отдельная `AccountGroup`-сущность.** `AccountsCoreAdditionBridge.swift:64-65` уже фиксирует эту семантику ядра («счёт без группы = nil, AccountGroup не создаётся») — создание отдельной Ungrouped-сущности `AccountGroup` ей противоречит и породило бы вторую видимую пустую группу вместо устранения дубля (Fable-риск №4, вероятность высокая при исходном варианте). Убрать легаси `resolveUngroupedGroup()`/`shouldHideGroupInList`-развилку, ввести единую точку рендера «счета без группы» поверх `group == nil`.
- `orderedAccounts(for:)` — одна core-реализация вместо 3 легаси-определений; `syncCoreGroup` как образец моста.
- Гейт: `Total(Groups)==Total(Accounts)` тест зелёный; group CRUD device-тест (создать/переименовать/удалить/переместить группу).

### 5c.7.2 — `FinanceAccountService` → `AccountsCoreService`-обёртка (M)
- Перевести `addAccountToGroup`/`removeAccountFromGroup`/`deleteAccountPermanently`/`restoreArchivedAccountToGroup`/`updateUnderlyingArchiveState` на `Account`/`AccountGroup`, используя уже существующие `AccountsCoreService.archiveAccount`/`restoreAccount`/`physicallyDelete`.
- `CardCatalog`/`CardManager` populate — сохранить как residual (см. §1.3 граница), НЕ расширять типизацию.
- **[Fable-ревью]** `loadAccounts()` (`FinanceAccountService.swift:107-146`) — точка, где инициализируются `CardCatalog`/`CardManager`; порт на core не должен обрывать их наполнение (Fable-риск №7 — иначе пустые пикеры Cashflow/Cashback вне видимости тестов этого плана). Smoke-тест пикеров — обязательная часть гейта, не отложить на 5c.7.5.
- **[Fable-ревью, формулировка ужесточена]** Regression-тест на смешанном сторе (converted core-счёт + непроконвертированная legacy-запись одновременно) — **создать fixture, не проверять «если есть»**; без него легаси archive/restore-путь для непроконвертированных записей непроверяем.
- Гейт: archive/restore/delete device-тест на core-счетах; легаси archive/restore-путь на смешанном фикстур-сторе (см. выше) зелёный; смок-тест наполнения CardCatalog/CardManager (пикеры Cashflow/Cashback не пустые).

### 5c.7.3 — `FinanceViewModel` → core (L, самый большой кусок)
- `state.groups`→`[AccountGroup]`, `availableCards/Credits/Investments`→единый `[Account]`, кэши по `Account.id`.
- `editGroup`/`removeAccountFromGroup`/`showAccountDynamics` — параметры на `Account`/`AccountGroup`.
- `physicallyDeleteLegacyAccount`-экшен — переименовать/развести на core-путь (`physicallyDelete` из 5c.7.2) + legacy-fallback только если легаси-запись реально есть.
- `calculateGroupTotal` — снять легаси-терм (Ф2c-блокер (в), теперь безопасно — VM уже core-typed).
- **[Fable-ревью] Characterization-тесты ДО порта.** Гейт «FinanceViewModelTests переписанные под core зелёные» самоподтверждается — переписанный тест не ловит регресс поведения, которое сам же переопределяет (Fable-риск №5, вероятность высокая). Перед портом зафиксировать текущее поведение totals/ordering/фильтров отдельными characterization-тестами на ТЕКУЩЕМ легаси-коде, затем гонять их же (адаптированные под новую сигнатуру, но с теми же ожидаемыми числами) после порта.
- Mixed-store fixture (инвариант 9, §2.1) — обязательная часть regression-сьюта этой под-фазы, не только 5c.7.4.
- Гейт: characterization-тесты (сняты ДО порта) зелёные после порта; `FinanceViewModelTests` полностью зелёные; 0 новых красных в остальном сьюте.

### 5c.7.4 — `FinanceDynamicsViewModel` → core (L)
- `FetchDescriptor<Card/Credit/Investment>()` `:523-529` → `FetchDescriptor<Account>`.
- Per-account chart-modes (byAccounts/singleAccount, Ф2c-блокер «1b») — порт на `Account`, сохранить `aggregateGroupRows`/`signedAccountValue`-паттерн без изменений семантики.
- **[Fable-ревью]** Mixed-store fixture (инвариант 9, §2.1) обязателен в этой под-фазе — `FetchDescriptor<Account>`-миграция не должна тихо терять непроконвертированный legacy-хвост из графика/breakdown (Fable-риск №6).
- Гейт: **обязательный полный прогон 6-файлового protected-кластера Dynamics-тестов** (~3347 строк) — 0 новых красных; `FinanceTotalsServiceFilterConsistencyTests` зелёный; mixed-store fixture зелёный.

### 5c.7.5 — Views + декаплинг CREATE-формы + полноценный rich-edit UI (M)
- `FinancesView`/`FinanceRows`/`FinanceOverviewCardView`/`FinanceAddAccountView`/`FinanceGroupEditorView`/`FinanceQuickEditAccountView`/`ArchivedAccountsView` — привести сигнатуры к core-типам вслед за VM (в основном механический порт после 5c.7.3/4).
- Декаплинг `InlineCreateForms` от `CardViewModel`/`CreditViewModel`/`InvestmentViewModel` (отложено в Ф5c.3, теперь самое время — они уже не нужны нигде, кроме этой формы).
- **[Fable-ревью, перенесено из 5c.7.0]** Полноценный rich-edit UI в `AccountDetailView`: переиспользовать теперь уже core-типизированную `FinanceAddAccountView` в режиме prefill-from-core вместо минимальной формы 5c.7.0. Строится ПОСЛЕ перетипизации формы (не до), чтобы не делать работу дважды и не трогать CREATE-путь раньше готовности — снижает риск реинкарнации Ф6a-дубликат-бага (Fable-риск №3).
- Гейт: UI device-проверка полного flow «создать → отредактировать (полноценный rich-edit) → архивировать → восстановить → удалить» на 3 типах счетов.

### 5c.7.6 — Редизайн «Счета» (Ф6 proper, M) — слито сюда по решению плана-родителя
- Stacked-полоса активы/обязательства с нетто; секции «Активы»/«Обязательства» с подытогами; `AccountGroup.customIconName` (паттерн `AccountIconPickerSheet`/`FinanceOverviewLedgerPresentation`, additive-поле, без V6).
- Шапка: вторичная валюта чипом; БЕЗ чипа прироста/sparkline (решение владельца 2026-07-08).
- Побочные полировки, естественно попадающие в скоуп (не форсировать лишнее): дубль Ungrouped — уже закрыт в 5c.7.1 структурно, здесь только визуальная проверка; «Скрытые»/пустые состояния групп.
- Гейт: визуальный review + device stress-test полного экрана «Счета» на реальном бэкапе владельца.

### 5c.7.7 — Финальный regression-гейт под-проекта
- Полный `millioTests` через `xcrun xcresulttool`: 0 новых красных vs 1745/14.
- Grep-подтверждение: `FinanceViewModel`/`FinanceDynamicsViewModel`/`FinanceAccountService`/`FinanceGroupService` — легаси-ссылки сокращены до fallback-путей для непроконвертированных записей (явно перечислить оставшиеся, если есть).
- Обновить пред-гейт-грепу `plans/2026-07-07__legacy-accounts-purge-path-b.md` (стр.459) — переклассифицировать (c)-Finances-кластер, проверить, снят ли блокер 5c.6/5c.11 (скорее нет полностью — 5c.8/5c.9/5c.10 остаются, но Finances-доминанта должна исчезнуть).
- Device stress-test на реальном бэкапе владельца + явное «да» перед мержем в develop.

---

## 4. Риски (топ-3 + Fable-ревью 2026-07-11)
1. **`FinanceTotalsServiceFilterConsistencyTests`/protected Dynamics-кластер (~3347 строк)** — самый большой риск регресса; каждая под-фаза 5c.7.1/3/4 обязана гонять его целиком, не точечно.
2. **`updateAccount` (5c.7.0) — новый event-sourced API, риск рассинхрона имени/группы с существующими `adjustBalance`/`archiveAccount`** — писать с явным regression-guard теста на дубли (по аналогии с `AllPresetsOnNewCoreTests`), не форсировать без него. Валюта — вне скоупа v1 (§2.1 инвариант 8).
3. **`CardCatalog`/`CardManager`-граница (§1.3)** — если 5c.7.2 случайно оборвёт populate-логику, ломается Cashflow/Cashback (вне видимости тестов этого плана) — явно тестировать смежные экраны при device-стресс-тесте 5c.7.2/5c.7.5.

**Fable-ревью, 10 причин провала (полный стресс-тест) — учтены точечно по под-фазам выше, сводка:**
1. Смена валюты в updateAccount переинтерпретирует историю → средняя вероятность → запрещена в v1 (инвариант 8).
2. Мутация группы мимо кэшей рвёт Total(Groups)==Total(Accounts) → средняя → invalidateSnapshotCache + FilterConsistency-тест сразу после updateAccount (5c.7.0).
3. Rich-edit UI на легаси-типизированной форме реинкарнирует Ф6a-дубликат-баг → средняя → UI перенесён в 5c.7.5 (после перетипизации формы).
4. Ungrouped как отдельная AccountGroup-сущность вместо канонизации `group==nil` → высокая при исходном варианте → скорректировано в 5c.7.1.
5. Самоподтверждающийся гейт «переписанные тесты зелёные» → высокая → characterization-тесты до порта (5c.7.3).
6. `FetchDescriptor<Account>` теряет legacy-хвост из графика на смешанном сторе → средняя → mixed-store fixture (5c.7.3/5c.7.4, инвариант 9).
7. Порт `loadAccounts()` обрывает CardCatalog/CardManager → пустые пикеры Cashflow/Cashback → средняя → smoke-тест пикеров в гейте 5c.7.2 (не отложен на 5c.7.5).
8. Неверный признак конвертации в physicallyDelete удаляет не тот счёт → низкая/средняя → тест на converted+unconverted пару, device PENDING.
9. Backup/restore roundtrip ломается на новых полях/событиях → средняя → roundtrip-тест в 5c.7.0 и 5c.7.6 (инвариант 7).
10. «0 новых красных» маскирует миграцию baseline-красного теста на другую причину падения → средняя → сравнивать список ID упавших тестов, не только счётчик (см. заголовок плана).

## 5. Что НЕ входит в этот план (остаётся в родительском плане)
- 5c.8 (Cashflow legacy-name-резолв), 5c.9 (MarketData `Investment`→core), 5c.10 (`ScreenshotDataSeeder`), 5c.11 (собственно снос @Model+V6+version-gate) — отдельные под-фазы плана-родителя, стартуют ПОСЛЕ этого плана.
- Миграция Cashback на AccountsCore — отдельный эскалированный скоуп (Ф3-решение владельца, вариант Б: `Card.swift` живёт дольше как spec-исключение).
