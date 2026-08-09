# Spec: Единый source of truth исторической оценки счетов

> Phase 5 clarification (2026-08-08): producer-date FX prefetch and append-only historical market
> close prefetch are required inputs to the structured reader. Prefetch may use the network, but
> valuation replay remains local-only. Closed evidence is immutable; incomplete results are not
> offered to the close repository.

**Date:** 2026-08-07
**Stage:** 2 / Spec
**Updated:** 2026-08-08
**Status:** SPEC; implementation plan создан, кода нет
**Research:** [`thoughts/research/2026-08-07-accounts-history-source-of-truth-audit.md`](../thoughts/research/2026-08-07-accounts-history-source-of-truth-audit.md)
**Related:** [`specs/2026-07-18-dynamics-single-series-producer.md`](2026-07-18-dynamics-single-series-producer.md), [`specs/2026-06-07-finance-balance-contract.md`](2026-06-07-finance-balance-contract.md)

## Problem

Одна и та же календарная дата считается по-разному до и после локальной полуночи. Core-путь для today берет live FX, для past — historical FX, а historical miss молча исключает счет из total. Legacy-путь имеет другие fallback-и. Поэтому портфель без операций может «потерять» целый валютный счет за ночь.

Голый `Decimal` не может быть достоверным historical total: он не сообщает, все ли счета, балансы, FX и market prices были разрешены. Пока это не исправлено, показывать partial sum как точный total — математически ложное поведение.

## Goal

Любой historical consumer получает один и тот же версионный close-of-day valuation с явной полнотой, качеством и provenance; после закрытия дня результат не зависит от wall clock, relaunch, online/offline и UI cache order.

## Scope

- Единый historical valuation contract для core и оставшегося legacy aggregate.
- Close-of-day semantics для native balance, FX, market price, account participation и archive/delete cutoff.
- Структурированная completeness/finality/quality semantics.
- Единая failure policy: ни один неразрешенный вклад не исчезает и не маскируется под display currency.
- Контракт миграции/rollback без удаления исходных Account/Event/Snapshot данных.
- Детерминированное воспроизведение ночного скачка `99 633 041 ₽ → 77 125 067 ₽` как regression fixture.
- Persisted product identity, единый product catalog и атомарное создание счета как prerequisite до публикации historical valuation.
- Детерминированная migration matrix `kind + meta → productType` без догадок для неоднозначных legacy-данных.

## Non-Goals

- Порт всех legacy-моделей на AccountsCore.
- Визуальный редизайн UI «Динамики», create form или account detail; перенос business mapping из SwiftUI в product catalog входит в scope.
- Изменение формул существующих balance engines и знаков активов/обязательств; спека только делает выбор этих правил явным через product catalog.
- Подмена недостающей истории текущими курсами без provenance.
- Массовая коррекция уже показанных historical totals: это отдельная product/data-migration policy.
- Физическое удаление historical data.

## Normative historical valuation contract

В этом разделе **MUST**, **MUST NOT**, **SHOULD** носят нормативный смысл.

### 0. Product identity and atomic creation

#### 0.1 Two identities, not one heuristic

- `ProductPreset` is a UI choice controlling the form. It is not persisted as financial truth.
- `AccountProductType` is the resolved financial product after all form answers are known. It MUST be persisted on `Account` and included in valuation inputs.
- `AccountKind` remains a technical replay/storage discriminator. It MUST NOT be used alone to reconstruct user intent.
- V1 intentionally does not persist `productDefinitionVersion`. Valuation semantics are versioned by
  `valuationPolicyVersion`; a future incompatible catalog revision requires its own additive schema
  and migration instead of silently reinterpreting stored accounts.

Minimum canonical `AccountProductType` set:

```text
cash | debitCard | creditCard | bankAccount | deposit | loan |
receivable | payable |
marketStock | marketCrypto | marketBond | marketMetal | genericMarketInvestment |
realEstate | business | vehicle | otherManualAsset | unknownLegacy
```

`unknownLegacy` preserves an ambiguous migrated account without guessing. Its existing `kind` and meta continue to select the current replay engine, but product-specific UI/actions requiring a proven subtype MUST stay unavailable until the user explicitly classifies it.

#### 0.2 One product catalog

There MUST be one `ProductDefinitionCatalog` mapping `AccountProductType` to:

```text
AccountKind
required/allowed meta
opening strategy identifier
allowed event/capability identifiers
detail/presentation capability identifiers
```

The catalog MUST NOT contain replay, sign, FX or market formulas. Those remain owned by
`AccountBalanceEngine`, `AccountTotalsContribution` and the unified resolver. UI/ViewModel/bridge
code MUST NOT independently derive kind, meta compatibility or opening strategy. Bank, ticker
presence and other optional form fields are data/validation inputs, not architecture switches.

Normative examples:

- `creditCard` remains a credit card with or without selected bank; `bank == other` MUST NOT convert it to `cash`.
- `genericMarketInvestment` is selected explicitly as market-valued; temporary absence of a ticker MUST be a validation error/draft state, not an implicit conversion to `manualAsset`.
- `realEstate`, `business` and `otherManualAsset` may share `AccountKind.manualAsset` and the same replay engine, but their persisted product identities remain distinct.
- `receivable` and `payable` may share `AccountKind.debt`, but product identity and `DebtMeta.direction` MUST agree.

#### 0.3 Valid combinations

For a resolved product, catalog validation MUST make incompatible states unrepresentable at the write boundary:

| Product | Required | Forbidden examples |
|---|---|---|
| `creditCard` | `CardMeta.creditLimit > 0` | market/manual/loan meta |
| `deposit` | `DepositMeta` | card/loan/market/manual meta |
| `loan` | `LoanMeta` | positive asset sign policy |
| `receivable` / `payable` | matching `DebtMeta.direction` | contradictory direction |
| market products | non-empty `MarketMeta.symbol`, matching asset class | manual-asset meta |
| manual products | `ManualAssetMeta` | market meta |

`AccountProductType`, `AccountKind` and relevant meta MUST be validated together on create, import, restore, reconciliation and any material edit.

#### 0.4 Atomic creation contract

Creation flows through one application boundary:

```text
ProductPreset + completed form
  → ProductDefinitionResolver
  → validated CreateProductCommand
  → AccountProductFactory
  → one ModelContext save
```

The single save MUST contain the complete initial state:

- `Account` with persisted product identity/version, kind, currency, lifecycle and valid meta;
- mandatory zero/non-zero `.openingBalance` anchor;
- initial `buy` for market products when quantity is part of creation;
- deterministic scheduled events required by the product at creation time, or a persisted explicit pending/rebuild marker if those events are derived asynchronously.

If any required component fails validation or persistence, no partial account may remain. In particular, an empty market account after failed `buy` and a deposit silently missing its required schedule are forbidden.

#### 0.5 Material edits and product conversion

- Cosmetic metadata edits do not change historical valuation inputs.
- A change affecting kind, engine, sign or valuation policy MUST NOT mutate product type in place.
- Ordinary edits MUST reject any in-place change of engine, sign or valuation policy. A future
  predecessor/successor conversion requires a separate normative specification (including transfer
  legs and non-overlap); this initiative implements only the guard and MUST NOT invent a partial
  conversion model.
- Correcting product classification without changing financial semantics is an explicit versioned correction; it invalidates valuation from its declared effective date and preserves prior published versions.

#### 0.6 Existing-account migration matrix

Migration MUST be idempotent and preserve `Account`, events, snapshots and lifecycle fields. It assigns product identity only when evidence is unambiguous:

| Existing evidence | Persisted `AccountProductType` | Confidence/action |
|---|---|---|
| `kind == cash`, `CardMeta.creditLimit != nil` | `creditCard` | deterministic compatibility mapping |
| `kind == cash`, no credit limit | `unknownLegacy` | cannot distinguish cash from card-without-bank |
| `kind == debitCard`, credit limit exists | `creditCard` | deterministic |
| `kind == debitCard`, no credit limit | `debitCard` | deterministic |
| `kind == bankAccount` | `bankAccount` | deterministic |
| `kind == deposit` + valid `DepositMeta` | `deposit` | deterministic |
| `kind == loan` + valid `LoanMeta` | `loan` | deterministic |
| `kind == debt` + direction `owedToMe` | `receivable` | deterministic |
| `kind == debt` + direction `owedByMe` | `payable` | deterministic |
| `kind == marketInvestment` + asset class stock/crypto/bond/metal | matching market product | deterministic |
| `kind == marketInvestment` with missing/invalid market meta | `unknownLegacy` | preserve engine; block subtype actions |
| `kind == manualAsset` | `unknownLegacy` | house/business/other cannot be proved from current model |
| kind/meta contradiction or failed decode | `unknownLegacy` + diagnostic reason | never guess or delete |

New legacy conversion assigns product identity from the structured legacy source before hiding it
and routes creation through the same factory boundary. An already-created core twin may use the
legacy category only when both the legacy row and a verified registry mapping to that exact core UUID
exist; the device-local registry is not sufficient evidence after restore. Legacy `Card`, `Credit`
and `Investment` rows remain compatibility inputs and do not themselves receive Account product
columns.

Newly created accounts MUST never use `unknownLegacy`. Migration MUST NOT infer product type from localized account/group name, icon, bank presence or whether a ticker lookup currently succeeds.

### 1. Identity оценки

Оценка однозначно задается ключом:

```text
ValuationKey = (
  schemaVersion,
  scopeID,
  valuationDayKey,
  valuationTimeZoneID,
  displayCurrency,
  valuationPolicyVersion,
  inputRevision
)
```

- `valuationDayKey` — Gregorian calendar day, а `valuationTimeZoneID` — IANA timezone, в которой день был создан. Timezone MUST храниться с оценкой; смена timezone устройства не переименовывает прошлый день.
- Historical point represents **end of day D**, including events with effective timestamp `<= endOfDay(D)` and excluding later events.
- Account participates iff it existed by the point, `includeInTotal == true`, and the point is strictly earlier than `min(archivedAt, deletedAt)`. Одинаковый cutoff MUST применяться в core и legacy.
- Account membership and events MUST come from persisted domain data, not from completeness/order of UI caches.
- `scopeID` is the injected `DataScope.storeConfigurationName`; it identifies the local guest or
  authenticated store without persisting a raw user identifier or relying on a store URL.
- `inputRevision` is a canonical tuple of account-set, per-account financial, event and selected
  FX/price record revisions. `productType` participates when present; its absence does not block a
  replay-compatible legacy contribution.
- Persisted product identity/version, kind and meta MUST be mutually valid under the catalog used for valuation. Contradiction or unresolved `unknownLegacy` capability required for the calculation makes the contribution incomplete rather than guessed.
- Native balance MUST be equivalent to direct event replay at `endOfDay(D)`. Daily snapshot is only a cache; cache hit and replay MUST return identical balance.
- Arithmetic MUST use `Decimal`; rounding happens only at presentation/currency boundary and MUST NOT change persisted source values.

### 2. Contribution and portfolio value

For every participating account `a`:

```text
nativeContribution(a, D) = signed balance/market value by account engine at endOfDay(D)
displayContribution(a, D) = nativeContribution(a, D) × resolvedValuation(a.currency → displayCurrency, D)
portfolioTotal(D) = Σ displayContribution(a, D)
```

- Market account resolution is two-dimensional: historical instrument price at D, then FX at D. Missing either dimension makes that contribution unresolved.
- Same-currency conversion is rate `1` and never requires a provider.
- Core and legacy MUST use one resolver and the same resolution policy. A consumer MUST NOT add a second conversion/fallback after resolver output.
- The Phase 2V exit gate applies to the new structured aggregate/resolver boundary. The existing
  bare `AccountsTotalsService.totalAt` API is a quarantined, unsafe transition/rollback API for
  pre-cutover consumers only: it MUST NOT construct or feed `HistoricalValuationResult` and MUST
  NOT be treated as a historical source of truth. Phase 4 MUST cut those consumers over to the
  structured producer; Phase 6 MUST delete the bare path only after the rollback window.
- Each logical account contributes exactly once. Existing verified legacy/core mappings determine
  predecessor selection. Overlap or gap without persisted evidence makes the result incomplete;
  creating a new predecessor/successor model is outside this initiative.

### 3. Resolution policy

Every resolved dependency returns value plus provenance, never a bare optional:

| Resolution | Meaning | Allowed for closed day | Quality |
|---|---|---:|---|
| `nativeParity` | source and display currency are equal | yes | exact |
| `exact` | provider value explicitly applicable to D | yes | exact |
| `previousClose` | latest valid close before D under the versioned weekend/holiday/provider policy | yes | fallback |
| `frozenClose` | last successfully observed value for D, persisted before closing D | yes | fallback |
| `currentEstimate` | current quote used while D is still open | no | estimate |
| `unavailable` | no value can be proved under policy | no numeric contribution | missing |

Resolution order is deterministic and versioned:

1. `nativeParity`;
2. persisted closed valuation for the exact `ValuationKey`;
3. `exact` historical value for D;
4. eligible `previousClose`;
5. persisted quote observed for D → `frozenClose`;
6. `currentEstimate` only while D is open;
7. `unavailable`.

Hard rules:

- `unavailable` MUST NOT mean zero, account absence, raw native amount, or display-currency amount.
- A current quote MUST NOT be used to synthesize an arbitrary past day. It is legal only for the open day and becomes legal historical input only if persisted as that day's `frozenClose`.
- A closed valuation is immutable for the same revision and policy version. A later exact quote MUST NOT silently overwrite it. Revaluation requires a new version with explicit reason/provenance; readers stay on the published version until a deliberate migration switches them.
- The close operation MUST be idempotent. Concurrent close attempts for the same key converge to one value/version.
- Provider/network availability after close MUST NOT change the returned value.

### 4. Open-day and close transition

- While D is open, the result is provisional even when every dependency resolves: balances and quotes can still change.
- At close, the resolver persists the values actually selected under the resolution order, their timestamps/provider identifiers, policy version and coverage manifest.
- If every expected contribution has a numeric resolution, D can close as complete. Fallback quality does not make the sum partial; it is reported separately.
- If any expected contribution is unresolved, D closes as incomplete. A partial subtotal may exist for diagnostics, but MUST NOT be presented or consumed as the portfolio total.
- A later repair produces a new explicit valuation version. It never mutates the evidence of the prior incomplete version in place.

## Completeness semantics

Completeness has three independent axes; collapsing them to one boolean is forbidden:

```text
HistoricalValuationResult
  key
  total: Decimal?                 // non-nil only when coverage is full
  diagnosticPartialTotal: Decimal
  state: complete | provisional | incomplete
  finality: open | closed
  quality: exact | fallback | estimated | mixed | unavailable
  expectedContributionCount
  resolvedContributionCount
  unresolved: [UnresolvedContribution]
  resolutions: [ResolutionSummary]
  generatedAt
```

### Derived state

| Condition | `state` | Public `total` |
|---|---|---|
| `resolved == expected`, day closed, record persisted | `complete` | present |
| `resolved == expected`, day open or result can still be replaced | `provisional` | present, explicitly provisional |
| `resolved < expected` **or account/event scope itself is not known complete** | `incomplete` | `nil` |

Additional semantics:

- `expectedContributionCount` counts participating logical accounts, including zero-balance accounts. Zero is a valid resolved contribution; absence of a rate for a non-zero foreign contribution is not.
- `quality` describes evidence, not coverage. A complete closed total may be `fallback`/`mixed`; UI may disclose this, but MUST NOT call it incomplete.
- `unresolved` MUST identify an opaque account identifier, missing dimension (`accountData`, `events`, `nativeBalance`, `marketPrice`, `fxRate`, `migrationBoundary`) and machine-readable reason. No account name, raw balance or PII goes to telemetry.
- Errors from fetch, snapshot rebuild, provider, cache decode, interrupted restore or failed
  reconciliation MUST be represented in completeness. `try?`/catch-to-zero at a valuation boundary
  is forbidden.
- Consumers (Dynamics chart/header/card, dashboard history, export) MUST propagate state/quality. They MUST NOT turn `total == nil` into zero or retain a misleading exact-looking value without stale/incomplete labeling.

## Source-of-truth and ownership

- One historical valuation producer owns scope, replay, price/FX resolution, close and completeness assembly.
- `AccountDailySnapshot` remains a rebuildable native-balance optimization, not a portfolio or valuation source of truth.
- Historical FX/asset price caches are evidence inputs. The published versioned close record is the source of truth for the displayed historical point.
- The unified Dynamics series from the related spec is a consumer of this producer. It MUST NOT independently merge legacy/core values with different fallbacks.
- Live current total may keep a separate low-latency path, but once used as the visible point for open day D its valuation inputs MUST be capturable for D's close.

## Acceptance Criteria

### P. Product identity, catalog, creation and migration

- [ ] **AC-P1 — persisted identity.** Every newly created account stores a non-`unknownLegacy`
  `AccountProductType`; export/import and encrypted backup/restore preserve it. V1 has no
  `productDefinitionVersion`.
- [ ] **AC-P2 — single catalog.** Every supported product resolves through one catalog to exactly one kind/engine, compatible meta set, opening strategy, allowed events, total policy and valuation policy. Repository-wide tests prove UI/ViewModel bridges do not maintain a second mapping.
- [ ] **AC-P3 — preset matrix.** Every visible create preset and every material subtype (debit/credit card, receivable/payable, generic market/manual choice) creates the expected product type, kind, meta, initial events and signed contribution.
- [ ] **AC-P4 — no heuristic type corruption.** Credit card without a bank remains `creditCard`; missing ticker cannot convert a market product into a manual asset; real estate/business/manual-other remain distinguishable after relaunch.
- [ ] **AC-P5 — atomic creation.** Injected failure at account/event/buy/schedule/save stages leaves zero persisted partial accounts/events. Successful creation persists the complete initial graph in one transaction.
- [ ] **AC-P6 — invalid combinations rejected.** Create/import/restore/reconciliation reject or quarantine incompatible product/kind/meta combinations without crash, silent default or data deletion.
- [ ] **AC-P7 — deterministic migration.** The full migration matrix is tested, idempotent across repeated launch/reconciliation and never changes balances/events/snapshots/lifecycle. Ambiguous rows become `unknownLegacy` with a reason.
- [ ] **AC-P8 — no in-place semantic conversion.** Ordinary edits reject changes of engine, sign or
  valuation policy. Predecessor/successor conversion is not implemented without a separate spec.
- [ ] **AC-P9 — valuation identity.** Optional product identity participates in `inputRevision` when
  present; a correction creates a new explicit valuation revision and never silently rewrites a
  published close.

### A. Reproduction and regression of the observed night jump

- [ ] **AC-A1 — defect is reproducible before the fix.** Fixture: display `RUB`; unchanged portfolio; foreign core contribution `22 507 974 ₽`; all other resolved contributions `77 125 067 ₽`; current quote for D exists; historical provider for D returns unavailable. With the old branch, the test proves `99 633 041 ₽` while D is today and `77 125 067 ₽` after midnight. The assertion must show the missing contribution, not merely unequal totals.
- [ ] **AC-A2 — fixed contract preserves the contribution.** The same fixture through the new producer persists D's observed quote and closes it as `frozenClose`; before/after relaunch and before/after midnight the closed value is `99 633 041 ₽`, `resolved == expected`, `state == complete`, `quality == fallback` or `mixed`.
- [ ] **AC-A3 — no operation, no unexplained jump.** With unchanged account/event revisions, requesting D at T−1 minute, T+1 minute, after app relaunch, and offline returns the same published valuation version. Any allowed change requires a new version and explicit reason.
- [ ] **AC-A4 — missing all legal fallbacks is visible.** If D has neither exact/previous/frozen resolution, result is `incomplete`, public `total == nil`, unresolved dimension is `fxRate`, and the foreign account is neither dropped nor treated as zero/raw RUB.

### B. Unified valuation behavior

- [ ] **AC-B1.** Contract matrix for core and legacy produces identical value, resolution, state and quality for `nativeParity`, `exact`, `previousClose`, `frozenClose`, `currentEstimate` and `unavailable`.
- [ ] **AC-B2.** Market account with known quantity but missing historical price is incomplete; known price plus missing FX is incomplete; both present yields one signed contribution.
- [ ] **AC-B3.** Each logical account contributes once across core/legacy migration boundary; test fails on overlap and on gap.
- [ ] **AC-B4.** Archive/delete cutoff is identical in core and legacy: point strictly before cutoff includes the account; point at/after cutoff excludes it; earlier closed points remain unchanged.
- [ ] **AC-B5.** Aggregated, by-account and single-account lines, scrubbed header, period header,
  total card, account/group breakdown, distribution, currency distribution, dashboard/Cashflow
  historical snapshot and export derive from one `HistoricalPortfolioSeriesResult`. They carry the
  same query/point identities and completeness; no consumer performs a second replay or FX lookup.

### C. Completeness and failure semantics

- [ ] **AC-C1.** `expected=resolved` is required for non-nil complete total. Zero-balance account counts as resolved; missing non-zero FX/price does not.
- [ ] **AC-C2.** Account fetch failure, event fetch failure, snapshot rebuild failure, corrupted cache,
  interrupted restore and failed reconciliation each produce `incomplete` with a reason; none becomes
  zero or a successful empty portfolio.
- [ ] **AC-C3.** A complete fallback valuation reports fallback provenance. A provisional open-day valuation cannot be confused with a closed complete valuation.
- [ ] **AC-C4.** No historical consumer accepts a bare numeric total without state and valuation version.
- [ ] **AC-C5.** Telemetry contains only opaque identifiers, counts, resolution kinds, policy/version and bucketed deltas; no names, exact balances or other PII.

### D. Determinism, time and cache equivalence

- [ ] **AC-D1.** Injected clock/calendar tests cover local midnight, DST transition and device timezone change. Stored `(dayKey, timeZoneID)` continues to address the same closed day.
- [ ] **AC-D2.** For start/middle/end of an event day, snapshot-backed native balance equals direct replay; a checkpoint never leaks a later same-day event into an earlier timestamp query.
- [ ] **AC-D3.** Weekend/holiday exact miss resolves by the versioned `previousClose` rule; provider recovery after close does not mutate the published value.
- [ ] **AC-D4.** Parallel process-local close requests and duplicate rows introduced by restore/import
  are deterministic: one logical winner per revision/policy key; partial data cannot publish complete.

### E. Migration and rollback safety

- [ ] **AC-E1.** New valuation storage is additive, versioned and idempotent; no Account/Event/Snapshot or legacy history is deleted or rewritten.
- [ ] **AC-E2.** Before reader cutover, old/new producers run read-only in shadow mode and expose completeness plus bucketed delta; cutover gate requires zero silent-drop cases in the agreed observation window.
- [ ] **AC-E3.** Rollback switches the reader without deleting new records. Rollback never restores silent `nil rate ⇒ drop account`; incomplete state remains mandatory.
- [ ] **AC-E4.** Backfill can resume per day/account after interruption and distinguishes complete, incomplete and not-attempted work.

## Constraints

- **Architecture:** one resolver and one historical producer; no third fallback path in UI/ViewModel.
- **Product architecture:** one product catalog and one atomic creation boundary; product selection logic does not live in SwiftUI views.
- **Data safety:** additive local schema only for rollout; old domain records remain replayable;
  repository idempotency does not claim SwiftData/CloudKit uniqueness guarantees.
- **Precision:** `Decimal` end-to-end; currency rounding only at presentation/comparison boundary.
- **Performance:** series generation must batch/prefetch inputs; no network call per account×day on the main actor. Concrete budget is set in the implementation plan after baseline measurement.
- **Privacy:** no PII or exact personal amounts in Crashlytics/telemetry.
- **Testing:** unit contract matrix plus integration tests for midnight, offline relaunch,
  archive/migration, snapshot equivalence, interrupted restore and reconciliation. Real network is
  not a test dependency.

## Edge Cases

- Empty portfolio is complete with total zero only when account scope is proved loaded; failed/unknown fetch is incomplete, not empty.
- Native zero contribution does not require FX/market lookup if zero is proven by the balance engine.
- Negative assets/liabilities preserve sign through conversion.
- Unsupported/crypto pair, provider outage, rate not yet published, weekend/holiday and stale persisted quote keep distinct provenance.
- A rate of zero, NaN/overflow-equivalent input or invalid currency code is invalid/unavailable, never a legal conversion.
- A late event, restore or reconciliation correction changes `inputRevision` and creates a new
  valuation version; it does not mutate the prior audit record.
- Existing ambiguous cash/manual accounts migrate to `unknownLegacy`; migration never guesses from names/icons and never changes their current replay balance.
- Product catalog version changes do not reinterpret stored accounts automatically.
- Display-currency change creates another key/value; it does not reinterpret a stored number as the new currency.
- Physical deletion that makes a published historical point unreplayable is incompatible with this contract and must be blocked or preceded by an explicit retention/export policy.

## Open Questions for implementation plan

These do not weaken the contract; the plan must resolve them before code:

1. Exact persisted model shape and revision/hash algorithm for account/event scope.
2. Eligibility calendar/provider metadata for `previousClose` (fiat, CBR, crypto, exchange-traded assets).
3. Product UX for `provisional`, fallback-quality complete and `incomplete` states.
4. Observation window and numeric delta buckets for shadow-read cutover.
5. Retention policy for superseded valuation versions and explicit user-triggered historical revaluation.

## Definition of Done

The work is done only when every AC is mapped to an automated test or an explicit operational gate, all historical consumers use the structured result, the pre-fix fixture proves the exact `22 507 974 ₽` disappearance, and the post-fix fixture proves that missing historical FX can no longer publish `77 125 067 ₽` as a complete total.
