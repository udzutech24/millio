# Research: Accounts history source-of-truth audit

- **Date:** 2026-08-07
- **Scope:** iOS-проект `millio`; read-only аудит архитектуры счетов и экрана «Динамика».
- **Observed case:** live total `99 633 041 ₽`; историческая точка 2026-08-05 — `77 125 067 ₽`; разница `22 507 974 ₽` без пользовательских операций.
- **Verdict:** корневой механизм ночного провала доказан чтением текущего кода. Точная привязка разницы `22 507 974 ₽` к конкретным пользовательским счетам требует диагностического снимка их валют/вкладов; репозиторий пользовательских данных не содержит.
- **Mode:** `$millio-bulletproof`, L/Research. Код продукта, spec и implementation plan не создавались.

## Executive conclusion

Экран не имеет единого исторического источника истины. Текущий total действительно сведен к `AccountsTotalsService.totalAt(Date())`, но агрегированная серия «Динамики» складывает два мира: легаси-replay и core-total (`FinanceDynamicsViewModel.swift:1931-1981`). Внутри этих миров историческая валютная конвертация имеет разные контракты.

Подтвержденный механизм дефекта:

1. Пока точка относится к сегодняшнему дню, core-total использует live курс (`AccountsTotalsService.swift:144-149`). Live-сервис имеет persisted stale/offline fallback (`CurrencyRateService.swift:74-89,140-171,283-318`).
2. После локальной полуночи та же календарная дата перестает быть `isDateInToday`, поэтому core-total переключается на `getHistoricalRate` (`AccountsTotalsService.swift:146-149`).
3. `CurrencyRateService.getHistoricalRate` пробует сетевые historical providers и при неуспехе возвращает `nil`; persisted live cache и previous/current fallback здесь не используются (`CurrencyRateService.swift:180-202`).
4. `AccountsTotalsService` трактует отсутствие курса как «не учитывать счет»: `guard let rate ... else { continue }` (`AccountsTotalsService.swift:47-53,64-70`). Поэтому из исторического total исчезает **вся стоимость каждого ненулевого core-счета в валюте, отличной от валюты отображения**.
5. Легаси-путь в той же серии ведет себя иначе: `HistoricalRateStore` после historical miss использует предыдущий сохраненный курс, затем current (`HistoricalRateStore.swift:61-80`), а `convertAmount` в крайнем случае возвращает исходное число (`FinanceDynamicsViewModel.swift:2760-2792`).

Следовательно, сумма меняется после смены дня не потому, что изменился баланс, а потому, что меняется режим оценки одной и той же даты. Это нарушение исторического источника истины и fail-open/fail-closed контрактов, а не косметика графика.

## Evidence and reproduction model

Минимальный детерминированный сценарий без изменения данных:

1. Core-счет: `currency = USD`, opening balance `250_000`; display currency `RUB`.
2. Live `USD→RUB = 90`; historical provider для дня D возвращает `nil` (offline, transient failure, unsupported pair, выходной/еще не опубликованный курс, crypto).
3. В день D: `totalAt(now)` = `22 500 000 ₽`.
4. После локальной полуночи запросить `totalAt(endOfDay(D))`: счет будет пропущен, вклад = `0 ₽`.

Масштаб практически совпадает с наблюдаемой разницей `22 507 974 ₽`, но это только иллюстрация механизма, не доказательство, что у владельца ровно `250 000 USD`. Чтобы доказать состав конкретной дельты, нужен read-only diagnostic dump: account id/name (можно хэшировать), kind, native balance, currency, выбранный display currency и resolution курса на D. Логировать PII или суммы в Crashlytics нельзя.

## Models and relationships

### Current core

```text
AccountGroup
  └─ accounts [Account]?                 nullify on group deletion
       ├─ group AccountGroup?
       ├─ events [AccountEvent]?          cascade on physical Account deletion
       └─ snapshots [AccountDailySnapshot]? cascade on physical Account deletion

AccountEvent.account ──> Account
AccountDailySnapshot.account ──> Account
HistoricalRate                         independent SwiftData cache
HistoricalAssetPrice                  independent append-only market-price cache
```

Evidence:

- `Account` хранит identity, kind, currency, lifecycle/meta и relationships, но не numeric balance (`Account.swift:4-42`).
- `AccountGroup.accounts` использует `.nullify`; удаление группы не удаляет счета (`AccountGroup.swift:37-38`).
- События и daily snapshots каскадно принадлежат счету (`Account.swift:38-42`).
- `AccountEvent` — операция/изменение баланса, содержит event date, фиксированный `dayKey`, amount/quantity/unit price и FX trace (`AccountEvent.swift:4-50`).
- `AccountDailySnapshot` — производный checkpoint в валюте счета, а не portfolio snapshot и не FX snapshot (`AccountDailySnapshot.swift:4-20`).

### Types and balance rules

`AccountKind` содержит 8 видов: `cash`, `debitCard`, `bankAccount`, `deposit`, `loan`, `debt`, `marketInvestment`, `manualAsset` (`AccountKind.swift:6-15`). Они сводятся к 6 engines (`AccountKind.swift:16-42`).

| Kind | Stored current balance | Historical rule |
|---|---|---|
| cash / debitCard / bankAccount | нет | signed sum of events |
| deposit | нет | та же лента + interest events |
| loan | нет | liability sign map; debt negative |
| debt | нет | sign encoded by created events/direction |
| marketInvestment | нет | quantity from buy/sell × price(date); last event price fallback |
| manualAsset | нет | last revaluation, else opening |

`AccountBalanceEngine.balanceAt` — чистый replay и декларируемая SSOT баланса (`AccountBalanceEngine.swift:11-29`). Кредитная карта — не отдельный kind: определяется наличием `CardMeta.creditLimit`; вклад в net worth = raw balance − limit (`AccountTotalsContribution.swift:9-29`). Метаданные вкладов, кредитов, долгов, рынка и ручных активов находятся в `AccountMeta.swift:8-96`.

### Legacy compatibility world

Еще существуют отдельные SwiftData-модели:

- `Card.balance`, `initialBalance`, `creditLimit`, `includeInTotal`, `archivedAt` (`Card.swift:108-169`);
- `Credit.remainingAmount`, `initialRemainingAmount`, adjustment, `includeInTotal`, `archivedAt` (`Credit.swift:64-145`);
- `Investment.amount`, market fields, deposit fields, `includeInTotal`, `archivedAt` (`Investment.swift:109-213`);
- строковая junction `FinanceAccount(accountType, accountID, group)` без SwiftData relationship к underlying model (`FinanceAccount.swift:38-75`);
- `FinanceGroup.accounts [FinanceAccount]` с `.nullify` (`FinanceGroup.swift:12-48`).

Это не чистый single-world: `FinanceDynamicsViewModel` по-прежнему гидратирует legacy links/caches и складывает legacy series с core (`FinanceDynamicsViewModel.swift:950-1019,1931-1981`).

## Current total data flow

```text
FinanceViewModel.calculateTotalAmountAsync
  → FinanceTotalsService.calculateTotalsSnapshot
    → newCoreTotalProvider(displayCurrency)
      → AccountsTotalsService.totalAt(Date(), displayCurrency)
        → fetch ALL Account
        → Account.participates(on: now)
        → AccountSnapshotRebuilder.rebuild(upTo: now)
        → latest AccountDailySnapshot.dayKey <= today OR direct event replay
        → AccountTotalsContribution.signedValue
        → live currency rate (today)
        → sum → state.totalAmount
```

Evidence: provider wiring (`FinanceViewModel.swift:282-312`), publication and generation guard (`FinanceViewModel.swift:875-898`), core sum (`AccountsTotalsService.swift:37-55`). Fetch выполняется напрямую из SwiftData, поэтому текущий общий total не зависит от `state.accounts` или порядка загрузки UI caches.

Список/сортировка счета использует отдельный синхронный replay `newCoreBalanceToday`, без snapshot actor и без market price provider (`FinanceViewModel.swift:1221-1238`). Значит формула знака общая, но источник цены и cache path уже различаются.

## Historical chart data flow

```text
FinanceDynamicsViewModel.updateChartDataAsync
  → historical FinanceAccount scope (legacy links)
  → aggregatedDynamicsSeries
      ├─ buildTimeSeriesData(legacy links)
      │   └─ calculateBalanceAtDate
      │       ├─ Card/Credit/Investment stored baselines
      │       ├─ CashflowTransaction replay/live reconcile
      │       └─ HistoricalRateStore (exact→previous→current→raw fallback)
      └─ for every chart point:
          AccountsTotalsService.totalAt(point.date)
            ├─ core event/snapshot balance
            └─ today live FX; past direct historical FX; nil ⇒ drop account
  → dedupe by Calendar.current day
  → state.chartData
```

Evidence: scope/build (`FinanceDynamicsViewModel.swift:1536-1588`), legacy series (`:1637-1927`), core merge (`:1929-1981`), presentation endpoints (`:816-836`). Core-only series может иметь всего два endpoint-а, потому что skeleton создается только из period start/end (`:1956-1966`); это не причина указанного уменьшения, но ограничивает историческую детализацию.

## Daily snapshot lifecycle

### Core `AccountDailySnapshot`

1. Snapshot — sparse checkpoint только для дней с событиями (`AccountSnapshotRebuilder.swift:4-15,76-86`).
2. При `totalAt` rebuilder лениво достраивает хвост до запрошенной даты (`AccountsTotalsService.swift:92-95`).
3. Для каждого event day cursor = время последнего события этого дня; replay записывает native balance (`AccountSnapshotRebuilder.swift:106-129`).
4. Чтение берет последний checkpoint с `dayKey <= requested dayKey`, иначе direct replay (`AccountsTotalsService.swift:96-121`).
5. Любая запись/правка/удаление event инвалидирует snapshots от dayKey изменения (`AccountsCoreService.swift:68-117,404-457,600-620`).
6. Archive инвалидирует от archive day; restore — от прежней archive date (`AccountsCoreService.swift:509-525`).
7. Startup backfill запускается один раз per data scope и затем ставит флаг даже при частичных ошибках; недостающее предполагается восстановить lazy (`AccountSnapshotBackfillCoordinator.swift:18-24,40-72`).

Snapshot не содержит currency, FX rate, completeness/source hash и portfolio membership. Поэтому он не может быть историческим источником total; это только native-balance cache.

### Legacy JSON snapshots

`AccountBalanceSnapshotService` один раз в сутки сохраняет balances старых `FinanceAccount` links в `account_balance_history_v1.json` (`AccountBalanceSnapshotService.swift:23-45`). Он вызывается fire-and-forget после dashboard calculation (`FinanceViewModel.swift:901-969`). Cleanup удаляет записи отсутствующих active IDs (`AccountBalanceHistoryStore.swift:68-75`). Этот store не участвует в основном графике «Динамика»; он отдельный источник для UI history/sparklines. Архивный link, не попавший в balances, может потерять JSON history при cleanup.

## Calendar and timezone contract

- Event `dayKey` создается Gregorian/POSIX formatter-ом, но timezone явно не задается, то есть используется текущая timezone процесса; ключ затем хранится и не пересчитывается (`AccountEvent.swift:99-119`).
- Snapshot queries создают dayKey тем же helper в текущей timezone (`AccountsTotalsService.swift:99-103`).
- Series stepping использует новый Gregorian calendar без явной timezone (`AccountsTotalsService.swift:74-86`).
- Dynamics grouping/end-of-day использует `Calendar.current` (`FinanceDynamicsViewModel.swift:1647,1766,1814-1817,1988-2001`).
- Historical rates нормализуются к `Calendar.current.startOfDay` (`HistoricalRateStore.swift:117-123`); модель прямо документирует local TZ (`HistoricalRate.swift:23-24`).

UTC как единый day boundary не используется. Гипотеза «график целиком считает день UTC» опровергнута. Но контракт хрупок при смене timezone: persisted event dayKey остается старым, request/rate day normalizes в новой timezone. Тест проверяет только сохранность fixed event dayKey (`AccountSnapshotRebuilderTests.swift:108-127`), а не end-to-end total/rate после путешествия.

## Archive and delete rules

### Core

- Active participation: `includeInTotal == true` и `date < min(archivedAt, deletedAt)` (`Account.swift:67-75`).
- Main UI «Удалить» = archive; balance history до cutoff сохраняется (`AccountsCoreService.swift:509-517`).
- Group deletion archives every account, sets `group = nil`, deletes group; relationships счетов сохраняются (`FinanceGroupService.swift:59-80`).
- Archive list fetches `archivedAt != nil && deletedAt == nil` (`ArchivedAccountsView.swift:18-24`).
- «Удалить навсегда» в UI фактически вызывает `softDelete`; events/snapshots остаются (`ArchivedAccountsView.swift:144-153`, `AccountsCoreService.swift:528-540`). UI copy/имя метода misleading.
- Реальный `physicallyDelete` cascade-удаляет events/snapshots и переписывает surviving transfer legs; заявлен для converter dedup (`AccountsCoreService.swift:542-597`).

### Legacy

Archive marker живет на `Card`/`Credit`/`Investment`, не на `FinanceAccount` (`FinanceAccount.swift:38-54`; model refs выше). Dynamics может восстановить archive cutoff только если underlying object есть в caches (`FinanceDynamicsViewModel.swift:1168-1176`). Сохранение link критично: без него historical scope не достигает underlying model. Текущий group-delete core path больше link не удаляет, но legacy физические delete paths еще существуют (`FinanceViewModel.swift:1610-1696`).

## All total sources and filters

| Producer/consumer | Balance source | Account scope/filter | FX rule | Failure behavior |
|---|---|---|---|---|
| Accounts header / current total | core snapshot/event replay | all `Account`; `participates(now)` | live for today | missing rate drops account |
| Dynamics aggregate core part | same `AccountsTotalsService` | all `Account`; `participates(pointDate)` | live today, direct historical past | historical miss drops account |
| Dynamics legacy part | stored baseline + Cashflow replay + live reconcile | `FinanceAccount` historical scope; underlying include/archive checks | `HistoricalRateStore` exact→previous→current | final fallback returns unconverted value |
| Dynamics header/card | endpoints of generated aggregate series in unscoped mode | same series | inherited mixed rules | inherits disappearing core FX account |
| Group total | core subset via `accountsTotalsService.total` in current core path; legacy helper remains | live group membership, participating today | live | missing rate drops account |
| Account row/sort | direct `AccountBalanceEngine` | visible core state | no portfolio FX; native amount | market provider absent, last-event price fallback |
| Currency breakdown | legacy signed model values + core per-account totals | current visible; archived legacy rejected in signed helper | mixed native grouping then display conversion | separate warning/fallback behavior |
| Dashboard sparkline | `state.totalAmount` daily JSON | one value per display currency/day | already converted live total | overwrites same day; unrelated to Dynamics history |
| Legacy per-account history JSON | current legacy model values | FinanceGroup links returned by legacy totals | native only | cleanup removes absent IDs |

Единого producer contract нет. Название `AccountsTotalsService` верно только внутри core balance contribution; итоговый исторический капитал смешивает scopes, models, price providers и FX policies.

## Confirmed defects

### C1 — Historical FX miss removes entire core account (Critical)

**Evidence:** `AccountsTotalsService.swift:47-53,64-70,144-150`; `CurrencyRateService.swift:180-202`.

`nil` курса означает «счет не существует в total», хотя native balance известен. Это data-semantic corruption на чтении. Падает любой ненулевой core-счет с `account.currency != displayCurrency`: валютные cash/card/bank/deposit/loan/debt/manual asset и market investment. Чем больше счет, тем больше провал.

### C2 — Same date changes valuation branch at midnight (Critical; trigger for reported defect)

**Evidence:** `AccountsTotalsService.swift:146-149`; series core merge `FinanceDynamicsViewModel.swift:1970-1979`.

`Calendar.current.isDateInToday(date)` делает результат функции зависимым не только от `(accounts, events, rates-for-date, requestedDate)`, но и от wall-clock момента вызова. Точка D днем использует current rate, после полуночи — historical lookup. В сочетании с C1 это точно объясняет скачок без операций.

### C3 — Legacy and core FX fallbacks are contradictory (High)

**Evidence:** core direct historical/no fallback (`AccountsTotalsService.swift:144-150`); legacy previous/current fallback (`HistoricalRateStore.swift:61-80`); final raw fallback (`FinanceDynamicsViewModel.swift:2760-2792`).

Один и тот же портфель на одной точке может одновременно: корректно конвертировать legacy account по previous/current rate, удалить core account из total и трактовать еще один legacy amount как будто он уже в display currency. Warning не восстанавливает математический инвариант.

### C4 — Snapshot lookup ignores time within event day (High, отдельный исторический дефект)

**Evidence:** snapshot cursor включает все события event day (`AccountSnapshotRebuilder.swift:106-129`), а lookup сравнивает только `dayKey <= dayKey` (`AccountsTotalsService.swift:99-112`).

После появления snapshot за D запрос `totalAt(startOfDay(D))` может взять checkpoint после последнего события D и тем самым включить будущие относительно requested timestamp операции. Direct replay до создания snapshot дал бы другой результат. Это нарушение эквивалентности cache/replay. Оно не объясняет наблюдаемое уменьшение, но доказывает, что snapshot cache способен менять исторический ответ.

### C5 — Archive cutoff differs between core and legacy (Medium)

Core исключает счет при `date == archivedAt` (`Account.swift:71-75`), legacy включает до тех пор, пока `date > archivedAt` (`FinanceDynamicsViewModel.swift:2507-2512`). Мигрированный predecessor имеет отдельный dayKey cutoff (`FinanceDynamicsViewModel.swift:1148-1159`), но обычные смешанные счета остаются с разной семантикой.

### C6 — Backfill completeness flag accepts partial failure (Medium)

Backfill ставит completed flag даже при failures (`AccountSnapshotBackfillCoordinator.swift:58-72`). Lazy rebuild обычно лечит это, но нет persisted completeness marker per account/day. В сочетании с swallowed errors (`try?` в `AccountsTotalsService.swift:49,66,111`) невозможно отличить valid fallback replay от частично недоступного cache path.

### C7 — “Delete forever” UI is not delete forever (Medium, contract risk)

Кнопка и copy обещают физическое удаление, а действие вызывает soft delete (`ArchivedAccountsView.swift:115-119,144-153`). Для истории это безопаснее, но пользовательский и migration contract ложный; данные продолжают синхронизироваться/бэкапиться. Это не причина ночного скачка.

## Hypotheses checked

| Hypothesis | Status | Evidence / reproduction |
|---|---|---|
| snapshot created before all accounts load | **Не подтверждено для core total** | `totalAt` fetches all `Account` directly (`AccountsTotalsService.swift:39-40`), не UI cache. Legacy JSON writer зависит от FinanceGroup links и fire-and-forget, но Dynamics его не читает. |
| snapshot excludes archived accounts | **By design, not root cause** | participation is time-aware; archive invalidates from cutoff. Past-before-cutoff tests exist (`AccountsTotalsServiceTests.swift:302-342`). |
| archived product loses FinanceAccount link | **Current core group path опровергнут; legacy risk remains** | core group delete nullifies group and preserves account (`FinanceGroupService.swift:59-80`). Existing tests cover legacy link retention (`FinanceDynamicsViewModelTests.swift:423-479`). Reproduce legacy physical-delete/group paths separately. |
| inconsistent `isArchived` filters | **Confirmed architectural inconsistency, not required for observed trigger** | current lists use `participates(now)`; legacy scopes filter via model caches; archive cutoff differs C5. |
| UTC boundary instead of local | **Опровергнуто** | all relevant day boundaries are local/current calendar. Travel/timezone mismatch remains untested. |
| today live total, yesterday incomplete history | **Confirmed** | C1+C2. “Incomplete” is specifically missing historical FX contribution, not necessarily missing balance snapshot. |
| snapshot overwritten by background refresh | **Not confirmed** | core rebuilder updates existing checkpoint during rebuild (`AccountSnapshotRebuilder.swift:122-129`), but append-only event/cache invalidation should make it deterministic. Need concurrency stress test with two contexts and CloudKit merge. |
| different account types use different historical APIs | **Confirmed in legacy/core split** | legacy Card/Credit/Investment custom replay; core unified balance engine; market price provider is additional independent date source. |
| currency values use different rates | **Confirmed** | C1–C3. |
| account caches load after chart calculation | **Possible only for legacy part** | missing underlying cache causes `guard ... else continue` in `calculateBalanceAtDate` (`FinanceDynamicsViewModel.swift:2110-2439`); update attempts reload/fallback (`:1540-1567`). Reproduce cold launch with delayed CloudKit/legacy fetch. |
| SwiftData query excludes model/relationship | **Not confirmed for core aggregate** | fetch is unfiltered `FetchDescriptor<Account>`. Legacy historical reachability still depends on junction/group/cache. |
| launch/date/CloudKit race | **Not proven** | generation guard protects current total publication (`FinanceViewModel.swift:875-898`), but no injected clock/date-change test and no atomic portfolio snapshot. |

## Existing tests and gaps

Existing positive coverage:

- historical rate by date when rate exists (`AccountsTotalsServiceTests.swift:42-62`);
- time-aware archive and history-before-archive (`AccountsTotalsServiceTests.swift:83-101,302-342`);
- soft-delete preserves earlier series (`AccountSoftDeleteTests.swift:20-91`);
- fixed event dayKey (`AccountSnapshotRebuilderTests.swift:108-127`);
- `HistoricalRateStore` previous/current/unavailable fallbacks and negative cache (`HistoricalRateStoreTests.swift:115-263`);
- aggregate-series endpoint invariants, archived history and migrated predecessor (`FinanceDynamicsSeriesInvariantTests.swift:10-285`).

Missing tests that allowed the defect:

1. `AccountsTotalsService`: yesterday historical rate `nil`, current rate present — account must not disappear.
2. Same requested calendar date evaluated just before and just after midnight with injected clock.
3. Contract test: core and legacy conversion resolver return identical resolution/value for exact/previous/current/unavailable.
4. Portfolio invariant: `total(D)` is stable across app relaunch and wall-clock day change when events/accounts are unchanged.
5. Snapshot equivalence for query at start/middle/end of an event day after checkpoint exists (would catch C4).
6. Offline first launch after midnight with only persisted live rates.
7. Weekend/holiday and not-yet-published previous-day RUB/fiat rates.
8. Crypto and unsupported historical currency pair.
9. Timezone change after event creation: event dayKey, snapshot selection, rateDate and chart dedupe together.
10. CloudKit partial sync: accounts arrive before events/snapshots and vice versa; no partial total may publish as final.
11. Backfill partial failure retry/completeness per account.
12. Archive/delete group integration across both core and remaining legacy links.

Current mocks largely return `1` or provide all historical rates. They prove arithmetic when dependencies succeed, not failure semantics. Это слабое покрытие для финансового продукта.

## Minimal remediation strategy (not an implementation plan)

Не лечить симптом принудительным refresh графика. Минимально безопасная стратегия:

1. Ввести один `HistoricalValuationResolver` contract для core и legacy: result = value/rate + resolution (`exact`, `previous`, `frozenClose`, `currentEstimate`, `unavailable`), но **никогда не молча “drop account”**.
2. Зафиксировать close-of-day valuation. При первом успешном расчете дня D сохранять используемый FX/market valuation; после закрытия D ответ immutable. Если exact пока нет — хранить provisional с явным статусом и детерминированной replacement policy.
3. `AccountsTotalsService` должен возвращать structured completeness, а не голый Decimal. Неполный total нельзя выдавать как достоверный.
4. Исправить snapshot timestamp/day contract: либо snapshots строго end-of-day и все period endpoints тоже end-of-day, либо lookup учитывает requested timestamp/direct replay внутри checkpoint day.
5. Удалить legacy conversion path из aggregate только после доказанного migration gate; до этого оба мира обязаны использовать один resolver.

Это рекомендация архитектурной консолидации, не фазовый план реализации.

## Migration risks

- Уже сохраненные `HistoricalRate` могут содержать exact/previous значения с разной local timezone normalization; массовое переименование дня способно сдвинуть точки.
- `AccountDailySnapshot` не содержит FX и может быть пересобран, но старые portfolio values воспроизвести невозможно, если использованный live fallback не был зафиксирован.
- Рыночные активы используют отдельный historical price cache; FX-only migration не обеспечит immutable valuation.
- Soft-deleted/archive accounts обязаны остаться доступны для replay до cutoff; физическое удаление разрушает доказуемость старых totals.
- Legacy converted predecessors требуют строгого non-overlap cutoff; массовый rebuild может повторно открыть double-count на migration day.
- CloudKit schema changes должны быть additive; unique compound keys придется обеспечивать сервисом/idempotency.
- Нельзя «бэкфиллить» недостающие historical rates текущими курсами без маркировки: это перепишет историю под видом восстановления.

## Rollback strategy

Для будущего исправления rollback должен быть data-safe:

- новый valuation record/cache — только additive, versioned и rebuildable; старые Account/Event/Snapshot не удалять;
- feature flag переключает reader между old и consolidated producer, writer может временно dual-write;
- перед rollout считать old/new totals параллельно read-only и логировать только обезличенные completeness/delta buckets;
- rollback переключает reader назад, не удаляя новые records;
- historical backfill вести с checkpoint/status per account/day и idempotency key;
- запрещено rollback-ом восстанавливать старое поведение «nil rate ⇒ drop account» как молчаливую норму: UI обязан показывать incomplete state.

## Recommendation

**Не точечный фикс, а ограниченная консолидация источника истины.** Точечный `?? liveRate` остановит ночной провал, но заморозит другую ложь: прошлое будет плавать вместе с current rate. Правильный минимальный blast radius — один valuation resolver + completeness contract, затем подключение обоих historical paths. Полный rewrite моделей не нужен: `Account`/events уже дают хорошую основу; слабое место сейчас — слой historical valuation и продолжающий жить legacy aggregate.

До исправления severity — **Critical для доверия к данным / High для технической целостности**: операции и native balances не теряются, но приложение показывает исторический капитал, который может быть занижен на полную стоимость крупных валютных счетов, без ошибки и без признака неполноты.
