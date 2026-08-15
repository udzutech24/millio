# Final plan: Accounts history source of truth

**Date:** 2026-08-08
**Stage:** 3 / Final implementation plan
**Status:** PHASE 0 REOPENED; PHASE 1V + 2V + 3V + 1P + 4 COMPLETE; EMERGENCY STRUCTURED READER ACTIVE; PHASE 5 OPERATIONAL ACCEPTANCE OPEN
**Mode:** L / `$millio-bulletproof`
**Code state:** implementation complete through Phase 4; emergency cache-first structured reader active; Phase 5 still waits for real observation/device evidence; Phase 6 waits for the rollback window

## Inputs and authority

- Research: `thoughts/research/2026-08-07-accounts-history-source-of-truth-audit.md`
- Spec: `specs/2026-08-07-accounts-history-source-of-truth.md`
- Independent review: `thoughts/research/2026-08-08-accounts-history-plan-review.md`
- Adversarial recheck: current code as of 2026-08-08

This plan supersedes the previous 10-phase draft with eight execution phases arranged as two
independent tracks after Phase 0. Where the current spec still requires
`productDefinitionVersion`, live CloudKit convergence, predecessor/successor conversion or
full-event SHA-256, Phase 0 must amend the spec before production implementation. Code must
not implement mutually contradictory plan/spec contracts.

## Verdict and chosen architecture

Choose simplified option C:

1. one structured historical valuation contract;
2. one FX/market resolution policy;
3. one historical portfolio producer;
4. one minimal local close repository;
5. persisted product identity, one validation catalog and one atomic creation factory;
6. valuation and product hardening are separate tracks after Phase 0.

Rejected:

- a live-rate fallback for arbitrary history;
- a bare `Decimal` historical API;
- blocking the money-bug fix on complete product migration;
- product formulas/sign logic duplicated in a catalog;
- CloudKit conflict machinery: app data uses local per-scope stores and CloudKit snapshot
  backup/restore, not live SwiftData CloudKit sync;
- full-event SHA-256 in v1;
- product conversion/predecessor-successor implementation in this initiative.

## Proven baseline

- `AccountsTotalsService.totalAt` converts fetch/replay/FX failure into zero or a skipped
  contribution.
- `Calendar.current.isDateInToday` changes the lookup branch at midnight.
- snapshot lookup by day can expose a later same-day event to an earlier timestamp query.
- market price cache forward-fills from any older row without provider-calendar eligibility.
- market creation saves Account before buy; deposit creation saves Account before schedule.
- failed `ModelContext.save()` does not by itself remove pending inserted/changed objects.
- product preset is not persisted; bridge heuristics can turn a credit card into cash and a
  generic investment into either market or manual kind.
- `LegacyAccountConversion` creates core twins outside the future factory and collapses most
  investments to `manualAsset`.
- legacy→core mapping lives in device-local `LegacyConversionRegistry` (`UserDefaults`), is not
  backup-persisted and therefore is not generally valid migration evidence after restore.
- guest and authenticated data are separate local stores. Stable scope identity is the injected
  `DataScope.storeConfigurationName`, never a store URL or raw user ID.
- the current Dynamics "single producer" covers only the unscoped aggregated line. `byAccounts`
  and `singleAccount` still call the legacy `buildTimeSeriesData`; header values are recomputed by
  `updateCurrentBalanceAndDelta`; account/group breakdown is recomputed independently; currency
  distribution performs another balance/FX pass and evaluates core accounts at `Date()` rather
  than the selected endpoint. These are multiple sources of historical chart data.

## Corrected domain decisions

### Historical result

```text
HistoricalValuationResult
  key
  total: Decimal?                // nil only when coverage is incomplete
  diagnosticPartialTotal: Decimal
  state: provisional | complete | incomplete
  finality: open | closed
  quality: exact | fallback | estimated | mixed | unavailable
  expectedContributionCount
  resolvedContributionCount
  unresolved[]
  resolutions[]
  inputRevision
  generatedAt
```

`quality`, `coverage` and `finality` are independent. A closed fallback total may be complete.
A proven zero balance counts as resolved and requires no FX/price lookup. A diagnostic subtotal
must never be published as portfolio total, but UI may show a clearly labelled last-known complete
value when the requested point is incomplete.

### Single source for every historical chart

One query defines the complete historical presentation scope:

```text
HistoricalPortfolioSeriesQuery = (
  period,
  frozenTimeZone,
  displayCurrency,
  accountScope: portfolio | groupIDs | accountIDs | singleAccountID,
  samplingPolicy,
  valuationPolicyVersion
)

HistoricalPortfolioSeriesResult
  query
  points: [HistoricalValuationResult]
  accountContributionsByPoint
  generatedAt
```

The producer resolves the account set once from persisted domain data and evaluates every point
through `HistoricalPortfolioValuator`. It is the only owner of legacy/core predecessor selection,
archive/delete cutoff, replay, sign, FX/market resolution and completeness. Scope filtering is an
input to the producer, never a second filter applied in a ViewModel after an unscoped total.

All historical UI models are projections of this one returned bundle:

- aggregated line = totals of `points`;
- by-account lines and single-account line = slices of `accountContributionsByPoint` for the same
  point identities;
- scrubbed header = the selected point from the same bundle;
- period header and total card = first/last point, never a second replay;
- account/group breakdown = aggregation of first/last per-account contributions;
- distribution chart = contributions of the selected/end point;
- currency distribution = the same point contributions grouped by native currency and using the
  already selected FX resolutions;
- dashboard/Cashflow assets historical snapshot and export = the same query/result contract, not a
  temporary `FinanceDynamicsViewModel` or bare `(start, end)` tuple.

Forecast overlays such as `depositProjectedPoints` are not historical valuation. They may remain a
separate explicitly labelled projection series, but must not overwrite, fill gaps in or become the
source for historical totals. Live-only account balance may remain separate only for an explicitly
open-day view and must not replace a historical endpoint inside a series.

No View/ViewModel consumer may call `calculateBalanceAtDate`, `AccountsTotalsService.totalAt`,
`HistoricalRateStore`, `CurrencyRateService` or market-price lookup to recompute a historical chart
number after receiving `HistoricalPortfolioSeriesResult`.

### Valuation identity

```text
ValuationKey = (
  schemaVersion,
  scopeID,
  dayKey,
  timeZoneID,
  displayCurrency,
  valuationPolicyVersion,
  inputRevision
)
```

- `scopeID` is injected from `DataScope.storeConfigurationName`.
- `dayKey` is Gregorian in the frozen IANA timezone of the valuation.
- existing event timestamps remain authoritative; persisted legacy event `dayKey` is preserved
  for cache grouping but does not replace timestamp comparison at end-of-day.
- `inputRevision` is a canonical tuple of account-set revision, per-account financial revision,
  event revision and selected FX/price record identities.
- no full-history hash in v1. Every valuation-relevant writer/import/restore/reconciliation path
  must bump or rebuild revisions. If that inventory cannot be proved, fall back to a measured
  rolling digest, not an unbounded account×day rehash.
- optional `productType` participates when present; absence does not block replay-compatible
  legacy valuation.

### Scope completeness

There is no live CloudKit sync completeness signal. Local scope is authoritative only when:

- the target store opened successfully;
- no restore/recovery/reconciliation operation is in progress or failed partially;
- account and event fetches succeeded;
- required backfill/revision migration reached a terminal local state.

A failed/interrupted backup restore or guest→user reconciliation yields incomplete/not-ready,
not an empty complete portfolio. Published closes are not copied guest→user; destination days
are rebuilt using the destination scope ID.

### Close trigger

Close is lazy. On first read/write/app activation after the frozen timezone boundary, close every
eligible unclosed day in order. No midnight timer or background execution is required for
correctness. Cold launch after several missed days is a mandatory test.

### Repository

`HistoricalPortfolioValuation` is an additive V7 model stored in the local scope and included in
encrypted snapshot backup/export/import. It is not designed for live cross-device merge.

- deterministic logical ID from `ValuationKey`;
- process-local concurrent publish converges by actor serialization plus refetch;
- one logical winner per key; duplicate physical rows after restore/import are quarantined or
  deterministically deduplicated before read;
- repair/input revision creates a new key/record; old evidence is retained in v1;
- compact Codable provenance manifest with a measured byte limit; if the limit is exceeded,
  close fails explicitly rather than truncating evidence;
- no uniqueness guarantee is claimed from SwiftData/CloudKit.

### Product identity and catalog

Persist optional `Account.productTypeRaw` plus optional diagnostic migration reason. Do not add
`productDefinitionVersion` in v1: valuation semantics are versioned by
`valuationPolicyVersion`; a future genuinely incompatible catalog change may introduce a version
with its own migration.

Minimum product types:

```text
cash | debitCard | creditCard | bankAccount | deposit | loan |
receivable | payable |
marketStock | marketCrypto | marketBond | marketMetal | genericMarketInvestment |
realEstate | business | vehicle | otherManualAsset | unknownLegacy
```

`ProductDefinitionCatalog` owns only:

- canonical kind;
- required/allowed meta validation;
- opening strategy identifier;
- allowed event/capability identifiers;
- presentation/detail capabilities.

It does not contain replay formulas, sign formulas, FX formulas or market valuation formulas.
Those remain in `AccountBalanceEngine`, `AccountTotalsContribution` and the unified valuation
resolver.

### Product migration rules

- invalid `kindRaw`, multiple incompatible meta objects, invalid required values or kind/meta
  contradiction → `unknownLegacy` with reason; never fallback to cash.
- `cash + creditLimit > 0` → `creditCard`.
- `cash + nil creditLimit` → `unknownLegacy` unless persisted creation evidence proves cash/card.
- `cash + non-positive creditLimit` → invalid/unknown.
- `debitCard + creditLimit > 0` → `creditCard`; without limit → `debitCard`.
- valid `bankAccount`, `deposit`, `loan` → matching product.
- `debt + owedToMe/owedByMe` → `receivable/payable`.
- valid market meta → matching asset-class product; missing/invalid meta → unknown.
- direct existing `manualAsset` → unknown: house/business/vehicle/other is not recoverable from
  current core meta.
- new legacy conversion assigns product from the structured legacy source before the source is
  hidden and routes through the factory.
- an already-created twin may use legacy category only when both the legacy row and verified
  registry mapping to that exact core UUID exist. Because the registry is device-local and not in
  backup, missing evidence → unknown, never a guess.
- legacy Card/Credit/Investment records themselves remain compatibility inputs until removed;
  they do not receive Account product fields.
- `unknownLegacy` may replay and value using validated existing kind/meta/events. Only capability
  requiring the unknown subtype is blocked. Unknown subtype alone is not incomplete valuation.

### Atomic creation

One factory builds Account, opening event, optional market buy and deposit schedule/pending marker
without internal saves. One outer save commits the graph.

On validation/build/save failure:

- no persistent rows remain;
- the calling context has no pending inserts/updates/deletes for the failed graph;
- a second unrelated save cannot resurrect it.

Use a disposable child/background context or explicit rollback/cleanup with tests. Refactor
`DepositInterestScheduler` to build a batch without calling `upsertInterestEvent` save per event.
Post-save cache reload/UI refresh is an explicit side effect after successful commit only.

### Lifecycle and conversion boundaries

- historical participation is `date < min(archivedAt, deletedAt)`.
- restore clears archive cutoff and invalidates/rebuilds affected derived closes.
- physical deletion of replay-required source data remains outside this initiative and must be
  blocked while retained closes depend on it.
- product/engine/sign conversion in place is forbidden.
- predecessor/successor conversion, transfer-leg migration and strict non-overlap require a
  separate spec/model; this initiative provides the guard, not a fake half-implementation.
- group deletion is a separate proven risk: it currently performs per-account saves with ignored
  errors. Add characterization and track a follow-up; do not expand this plan into group CRUD.

## Phase map

Only one phase may be implemented per explicit user command. Phase 0 is mandatory. After Phase 0,
Track V and Track P may proceed independently. Phase completion requires its tests, exit gate,
rollback note and AC audit.

### Phase 0 — Contract reconciliation and red baseline

**Goal:** make spec and plan consistent, then prove every current defect without production changes.

**Documentation first:**

- amend AC-P1/P8/P9 for no product-definition version and guard-only conversion;
- replace partial CloudKit sync with failed/interrupted restore/reconciliation;
- replace cross-device CloudKit arrival AC with process-local concurrency + restore/import dedup;
- define `scopeID`, lazy close, local-store authority and product migration rules above;
- broaden AC-B5 from only graph/header/card to every historical line mode, scrub state,
  account/group breakdown, distribution, currency distribution, dashboard/Cashflow snapshot and
  export; require identical query/point IDs and completeness;
- record product and valuation tracks as independent.

**Tests first:**

- exact synthetic `99 633 041 ₽ → 77 125 067 ₽` midnight disappearance with missing
  `22 507 974 ₽` contribution;
- fetch/replay/rate failures currently collapse to zero/drop;
- snapshot direct-replay mismatch at start/middle/end of event day;
- unrestricted market forward-fill characterization;
- all visible create presets and material subtypes, including savings deposit and debt direction;
- credit card without bank, generic investment with/without ticker;
- market Account saved before buy and deposit saved before schedule;
- failed save followed by unrelated save proves pending-context resurrection risk;
- LegacyAccountConversion paths and loss of subtype/link after restore;
- characterize current chart-source divergence: aggregated versus by-account/single-account,
  filtered core scope, header recomputation, breakdown recomputation, currency distribution using
  `Date()` at a historical endpoint, and Cashflow constructing a temporary Dynamics ViewModel;
- group deletion partial-archive characterization, logged as out-of-scope follow-up.

**Exit gate:** failures are for the intended semantic reasons; corrected spec has no contradiction
with this plan; baseline commands/results are recorded.

**Rollback:** tests/docs only; no production rollback.

**AC:** A1; baseline for P2–P7, B1, C2, D2/D3.

### Phase 1V — Pure valuation contract, time and replay correctness

**Goal:** introduce structured value types and make native replay reliable, without persistence or
consumer cutover.

**Implementation:**

- result/state/finality/quality/provenance/unresolved types;
- injected clock, Gregorian calendar and frozen timezone context;
- typed fetch/replay/cache failures;
- snapshot checkpoint timestamp compatibility; direct replay for earlier same-day queries;
- revision value types and inventory of every valuation-relevant writer;
- local scope-readiness contract for restore/reconciliation/backfill states.

**Tests first:** state matrix, zero contribution, empty-versus-failed scope, timezone/DST/device TZ,
snapshot equivalence, invalid currency/rate/value, writer-revision inventory.

**Exit gate:** pure contract cannot represent incomplete with public total; snapshot-backed result
equals direct replay; no valuation-boundary catch-to-zero.

**Rollback:** new APIs unused by production readers.

**AC:** A4, C1–C3, D1–D2.

### Phase 2V — Unified FX and market resolver

**Goal:** one typed resolver for core and compatibility contributions.

**Implementation:**

- `nativeParity`, exact, eligible previous close, frozen close, open-day current estimate,
  unavailable;
- current quote only for open day;
- previous close only through explicit source/exchange-calendar policy;
- existing unrestricted market forward-fill is removed from aggregate use or returned with typed
  fallback provenance only when policy proves eligibility;
- batch unique `(day,pair)` and `(day,instrument)` dependencies;
- no network request per account×day and no network work on MainActor.

**Tests first:** full core/compatibility matrix, weekend/holiday/weekday miss, crypto 24×7, known/missing
price×FX, same currency, invalid/zero rate, shared dependency batching.

**Exit gate:** scoped to the new structured aggregate and resolver: no code in that boundary chooses
a fallback outside the resolver, and arbitrary stale price/current FX cannot become structured
closed history. The bare `AccountsTotalsService.totalAt` API is quarantined as an unsafe
transition/rollback path for pre-cutover consumers. It does not feed `HistoricalValuationResult`,
does not satisfy this gate, and must not be described as historical source of truth.

**Rollback:** the quarantined bare reader remains temporarily callable for old consumers; resolver
has no persisted aggregate writes. Phase 4 must cut those consumers over to the structured producer,
and Phase 6 removes the bare path only after the rollback window.

**AC:** A2/A4 resolver part, B1–B2, C3, D3.

### Phase 3V — Minimal V7 close repository

**Goal:** persist local immutable close results safely.

**Implementation:**

- build a real accepted-V6 fixture infrastructure first;
- add additive `HistoricalPortfolioValuation` and honest AppSchemaV7;
- add valuation-revision Account columns as optional/default automatic-lightweight changes and
  verify them with the V6→V7 fixture; the staged V7 transition itself owns only the new valuation
  model. Product identity already occupies V6 and remains owned by Phase 1P;
- repository actor with deterministic key, process-local idempotency and restore/import dedup;
- compact manifest byte limit and corrupted-manifest failure;
- encrypted backup/export/import registration;
- exclude guest close rows from guest→user copy and enqueue rebuild;
- no live CloudKit sync/winner machinery.

**Tests first:** real V6→V7 fixture counts/samples, relaunch round-trip, parallel local publish,
duplicate import winner, corrupted/oversized manifest, interrupted restore readiness, backup
round-trip, guest→user exclusion/rebuild.

**Exit gate:** an accepted V6 store migrates without destructive fallback; duplicate logical records cannot
produce divergent reads; no Account/Event/Snapshot rewrite.

**Rollback:** reader flag ignores V7 records; records remain for diagnosis; V6 source data remains.

**AC:** A3 persistence, C2 persistence, D4 corrected, E1/E3/E4 storage.

### Phase 1P — Product identity, catalog and atomic factory

**Goal:** stop creating lossy or partial product graphs without blocking Track V.

**Implementation:**

- `AccountProductType`, optional product field and migration reason; Phase 1P exclusively owns
  these V6 product columns and their automatic lightweight-migration fixture test. Its schema-safety
  gate remains in progress and must pass before V6 is accepted as the Phase 3V migration source;
- narrow validation/capability catalog with no financial formulas;
- `CreateProductCommand` and build-without-save factory;
- batch deposit schedule builder;
- route form, bulk import, restore validation, reconciliation, seeder and
  `LegacyAccountConversion` through validation/factory-compatible boundaries;
- assign structured legacy subtype at conversion time;
- idempotent existing-account migration using corrected matrix;
- reject in-place kind/engine/sign/valuation-policy mutation;
- no predecessor/successor implementation.

**Tests first:** product-column migration from a copied V5 store into product V6, followed by the
V6→V7 valuation fixture; catalog/preset matrix, all writer paths, invalid meta combinations,
migration twice, restore without registry, factory failure at every stage plus unrelated second save, market
Account+opening+buy, deposit Account+opening+schedule, post-save side effects only after success.

**Exit gate:** every new account is non-unknown and valid; every existing account is classified or
explicitly unknown; unknown replay-compatible accounts still value; failed creation leaves clean
context and store.

**Rollback:** optional fields ignored; old kind/meta/events untouched; old creation path retained
behind writer flag for one release but may not re-enable known type corruption.

**AC:** P1–P7; P8 guard; P9 optional fingerprint participation.

### Phase 4 — Portfolio producer, lazy close and shadow consumers

**Requires:** 1V, 2V, 3V. Phase 1P is not required; product identity is optional input.

**Goal:** make one series producer own scope, replay, resolution, completeness and close; integrate
all historical chart projections and other historical consumers behind flags.

**Implementation:**

- `HistoricalPortfolioValuator` over authoritative local account/event scope;
- add `HistoricalPortfolioSeriesQuery/Result`; resolve scoped account membership once and build all
  requested points plus per-account contribution slices from the same valuation results;
- archive/delete cutoff and legacy/core migration boundary alignment;
- each logical account contributes exactly once; overlap/gap is incomplete;
- lazy sequential close after app activation/read/write, including multi-day gaps;
- aggregated/by-account/single-account lines, scrubbed header, period header, total card,
  account/group breakdown, distribution and currency distribution derive from one series bundle;
- dashboard history, Cashflow assets historical snapshot and export call the same producer directly;
  they must not instantiate `FinanceDynamicsViewModel` as a calculation service;
- cut every remaining pre-cutover consumer off the quarantined bare `AccountsTotalsService.totalAt`
  path; no structured result may ever be assembled from that compatibility output;
- documented live-only exception for `newCoreBalanceToday`;
- incomplete point renders gap or labelled stale last-known value, never diagnostic subtotal;
- non-PII shadow comparison using counts, reasons and bucketed deltas.

**Tests first:** exact night fixture, offline/relaunch/multi-day lazy close, archive/delete/restore
boundaries, legacy/core overlap/gap, market/FX matrix, same-currency/zero/liability; query/account-set/
point-ID equality across aggregated, by-account, single-account and filtered scopes; scrub/header/card
identity; breakdown sums and both distribution charts reconstruct the same selected endpoint; Cashflow
snapshot/export identity; incomplete point propagates to every projection; nil-not-zero presentation,
accessibility/localization and logging guards.

**Exit gate:** `77 125 067 ₽` cannot be published complete in the fixture; repository-wide search
finds no historical bare-numeric consumer and no UI/ViewModel historical recomputation through
`buildTimeSeriesData`, `calculateBalanceAtDate`, direct totals/FX/market calls or temporary Dynamics
ViewModels; every historical chart projection carries the same query/point identity and completeness;
warm-cache performance does not regress beyond the measured Phase 0 budget.

**Rollback:** switch to structured compatibility reader, never to the current silent-drop reader.

**AC:** A2–A4, B1–B5, C1–C5, D1–D4.

### Phase 5 — Backfill, observation and cutover

**Requires:** Phase 4. Product Phase 1P may cut over independently after its own gates.

**Implementation/operations:**

- resumable per-scope/day backfill: not-attempted/complete/incomplete;
- accelerated clock suite plus at least two real device transitions, one offline;
- classify every non-zero shadow delta;
- product migration diagnostics distinguish direct rows, verified legacy twins and unknown rows;
- cut over readers only after explicit approval of incomplete/fallback UX.

**Gates:** zero silent-drop, exact regression stable, no unexplained account-set mismatch, no partial
restore/reconciliation published complete, all deltas classified, V6→V7 cold launch green, rollback
drill green.

**Rollback:** structured compatibility reader; retain V7 rows and backfill checkpoints.

**AC:** E2–E4 and operational completion of all A criteria.

### Phase 6 — Cleanup and documentation

**Requires:** successful Phase 5 plus completed rollback window.

**Implementation:** after the rollback window, delete the quarantined bare `totalAt` historical path
and remove other obsolete historical silent-drop paths and product heuristics only where
their replacement already passed cutover; retain superseded close records; update currency,
schema, backup, reconciliation and architecture docs; record final AC audit and test evidence.

**Exit gate:** focused suites, schema fixture tests, clean build, device smoke and final AC matrix are
green; every failure is either fixed or proven pre-existing by baseline.

**Rollback:** cleanup is delayed until rollback window ends; no destructive data cleanup.

**AC:** E1–E3 and Definition of Done.

### 2026-08-08 — Device-log remediation: FX sampling and market-price backfill

- Physical-device diagnostics proved that 7/8 short-period and 183/184 long-period points were
  incomplete, primarily because historical market closes were absent and FX prefetch dates did not
  match producer dates.
- Dynamics now warms the exact chart skeleton dates for legacy and core FX dependencies.
- `AccountMarketPriceService` reuses the existing authenticated market chart endpoint, performs at
  most one request per missing symbol, and appends immutable historical closes before replay.
- Incomplete closed results bypass repository publication, preserving their primary reason codes.
- Focused simulator gate passed for market cache, resolver, and portfolio producer suites. Backend
  Jest execution remains unavailable locally because dependencies are not installed.
- Phase 5 remains operationally open until the matching backend limit is deployed and physical-device
  logs show zero unexplained incomplete points, including an offline repeat.

## Dependency graph

```text
Phase 0
  ├─→ 1V → 2V → 3V → 4 → 5 → 6
  └─→ 1P ────────↗   (independent writer/product cutover)
```

No historical close waits for product migration when current kind/meta/events are replay-compatible.
No consumer cutover precedes repository/replay/resolver gates. Cleanup never removes rollback before
the observation window ends.

## Acceptance mapping

| AC | Phase | Sufficient gate |
|---|---|---|
| P1–P7 | 0 baseline, 1P | writer inventory + matrix + atomic failure suite |
| P8 | 1P | in-place semantic edit rejected; conversion deferred explicitly |
| P9 | 1P, 3V | optional product participates in input revision when present |
| A1 | 0 | exact synthetic pre-fix disappearance |
| A2–A4 | 2V, 3V, 4, 5 | frozen close + missing-resolution + relaunch/offline |
| B1–B2 | 2V, 4 | shared resolver cross-matrix |
| B3–B4 | 4 | overlap/gap and cutoff/restore boundary tests |
| B5 | 0 spec correction, 4 | query/point-ID and completeness equality across every historical chart projection and downstream consumer |
| C1–C3 | 1V–4 | structured coverage/failure tests |
| C4–C5 | 4 | API/search gate + telemetry privacy tests |
| D1–D3 | 1V, 2V, 4 | time/snapshot/provider-calendar suites |
| D4 | 3V, 4 | local concurrency + restore/import duplicate tests |
| E1 | 3V, 6 | additive fixture migration; no source rewrite |
| E2 | 4, 5 | shadow observation gate |
| E3 | 3V, 5, 6 | structured-reader rollback drill |
| E4 | 3V, 5 | interrupted/resumed backfill |

## File impact forecast

New files should remain responsibility-focused:

- `Core/AccountsCore/HistoricalValuation/HistoricalValuationModels.swift`
- `.../HistoricalValuationResolver.swift`
- `.../HistoricalPortfolioValuator.swift`
- `.../HistoricalPortfolioSeries.swift`
- `.../HistoricalValuationRepository.swift`
- `Core/AccountsCore/ProductCatalog/AccountProductType.swift`
- `.../ProductDefinitionCatalog.swift`
- `.../CreateProductCommand.swift`
- `.../AccountProductCreationService.swift`

Existing paths explicitly in scope include Account/Event/meta/kind/replay/totals/snapshot, currency
and market services, Dynamics consumers, AppSchemaVersions, feature registration/import/export,
backup/restore, reconciliation DTO/copy paths, `FinanceAddAccountView`,
`AccountsCoreAdditionBridge`, `LegacyAccountConversion`, `LegacyAccountConverter`, bulk import and
all related tests. Exact files are confirmed by repository search in each phase; forecast is not an
excuse to miss a writer.

## Definition of done

- no missing dependency can silently become zero/account absence/display-currency raw amount;
- closed valuation is stable across midnight, relaunch and offline use for the same input revision;
- snapshot and replay are observationally equivalent;
- no new account can persist a partial initial graph or incompatible product/kind/meta state;
- rollback never restores the known silent-drop reader;
- V6→V7 fixture migration, backup/restore and guest→user rebuild pass without deleting source data;
- every corrected AC has an automated test or explicit operational gate;
- no cleanup of superseded financial evidence occurs in this initiative.

## Execution journal

### 2026-08-08 — Phase 0 exit gate

- Spec reconciled with the final plan: no V1 `productDefinitionVersion`, no fake live CloudKit
  sync, `scopeID = DataScope.storeConfigurationName`, guard-only semantic conversion, local
  concurrency/restore dedup, and AC-B5 expanded to every historical consumer.
- Added exact characterization fixture: `99 633 041 ₽ → 77 125 067 ₽`, with the missing
  contribution asserted as `22 507 974 ₽`.
- Added same-day snapshot characterization: direct noon replay is `100`, while the current
  day-only checkpoint path returns `150` after an 18:00 event.
- Existing market characterization proves unrestricted previous-row forward fill. Independent
  audits confirmed multi-save market/deposit creation, device-local legacy mapping, partial group
  archive risk and the multiple Dynamics/Cashflow calculation paths.
- Fetch/rebuild failure injection is not honestly possible without a production seam because
  `AccountsTotalsService` owns concrete `ModelContext`/`AccountSnapshotRebuilder`. The typed seam is
  therefore an explicit first deliverable of Phase 1V; Phase 0 does not fake corruption tests.
- Focused gate: 44/44 passed on iPhone 17 Pro simulator (iOS 26.5), result bundle
  `/tmp/millio-accounts-history-phase0-pass.xcresult`.

### 2026-08-08 — Phase 1V in progress

- Added structured valuation key/result/state/finality/quality/unresolved/provenance types and a
  frozen Gregorian/IANA timezone context.
- `HistoricalValuationResult` derives its public total from coverage: incomplete coverage always
  produces `total == nil`; finality and quality remain independent.
- Fixed same-day snapshot leakage with the minimal safe rule: a day-only checkpoint is used only
  for a strictly earlier day; queries inside its own day replay timestamped events directly.
- Focused gate: 17/17 passed on iPhone 17 Pro simulator (iOS 26.5), result bundle
  `/tmp/millio-accounts-history-phase1v-pass.xcresult`.
- Exit gate remains open: typed fetch/rebuild/cache boundaries, scope-readiness integration and the
  complete valuation-writer revision inventory are not implemented yet.

### 2026-08-08 — Phase 1V exit gate

- Added typed account/event/snapshot/cache seams and readiness recheck; the new boundary has no
  catch-to-zero path.
- Added publication as an independent axis and custom validated decoding, so corrupted payloads
  cannot inject an incomplete public total.
- Both structured and compatibility readers now use timestamped direct replay. Existing lexical
  snapshots are checked as derived cache evidence only and are not a balance source until a future
  checkpoint timestamp/frozen-timezone schema exists.
- Same fixed D is tested at injected 23:59/00:01; the missing FX result is incomplete with nil
  public total, never a complete `77 125 067 ₽`.
- Explicit IANA, Istanbul/Los Angeles, 23-hour/25-hour DST, cross-timezone snapshot and later-day
  market price regressions are green.
- Final focused gate: 38/38 passed, iPhone 17 Pro simulator iOS 26.5,
  `/tmp/millio-phase1v-editor-final2.xcresult`; independent review findings and root re-review are
  resolved. Phase 2V may start.

### 2026-08-08 — Phase 2V exit gate

- Added the unified typed FX/market resolver with ordered one-result-per-input output, full
  provenance, explicit calendar-policy eligibility, current-day guards, checked Decimal
  multiplication and unique dependency batching.
- The production structured `AccountsTotalsService.historicalValuation` boundary now consumes that
  resolver and local typed evidence; it does not choose a second FX/market fallback.
- The exit gate is deliberately scoped to that structured boundary. Bare `totalAt` remains an
  unsafe quarantined transition/rollback API for old consumers until the mandatory Phase 4 cutover;
  it is not a source for `HistoricalValuationResult` and is deleted only in Phase 6 after rollback.
- Fresh focused gate: 98/98 passed, 0 failed, 0 skipped, iPhone 17 Pro simulator iOS 26.5,
  `/tmp/millio-phase2v-final-20260808.xcresult`. All independent-review findings were resolved;
  independent verdict: **ACCEPT**.
- Product identity occupies V6, so the next close-repository phase is Phase 3V/V7. Phase 1P remains
  `in_progress` until its schema-safety gate proves the V5→V6 product migration.

### 2026-08-08 — Phase 4 implementation gate and Phase 5 operational hold

- Dynamics (all line modes, header/scrub, breakdown and distributions), dashboard/overview and
  Cashflow now project from `HistoricalPortfolioSeriesResult`. Missing legacy/core predecessor
  coverage is explicit and incomplete; it is never published as a diagnostic subtotal.
- The producer resolves portfolio and per-account slices in one batched core pass per point. Legacy
  evidence is prepared once per query, and verified predecessor/successor boundaries participate
  exactly once.
- Persisted closes are hidden whenever live scope readiness or its generation token changes.
  Activation now awaits terminal snapshot backfill before missed-day historical maintenance, so a
  later readiness generation cannot invalidate freshly written closes while leaving completed
  checkpoints behind.
- Backfill and rebuild acknowledgement are durable and resumable. A rebuild generation forces
  replay instead of trusting an older completed checkpoint.
- Simulator evidence on the final implementation is recorded in
  `/tmp/millio-phase45-postreview-final.xcresult`: 67/67 tests passed across nine Phase 4/5 suites.
  Independent post-fix review verdict for Phase 4 code: **ACCEPT**.
- Phase 5 is an operational hold, not unfinished algorithm code. Structured cutover requires the
  production policy of 30 observations over 7 civil days, two real device transitions including an
  offline transition, explicit approval and a rollback drill. Simulator tests must not manufacture
  that evidence. The reader therefore remains `.shadow`, and Phase 6 deletion remains blocked until
  the real rollback window ends.

### 2026-08-08 — Emergency cache-first reader activation (Phase 5 remains open)

- A real-device screenshot proved that the `.shadow` default still published the known unsafe
  compatibility pixels: `100 069 565 RUB` at the live endpoint versus `76 922 172 RUB` for the
  unchanged previous day. The visible loss was `23 147 393 RUB`; the screenshot alone does not
  identify whether the unresolved dimension was FX, market price or native replay.
- The shipping default now selects `.structured` when no explicit reader override exists. This path
  reads local `HistoricalRate`/`HistoricalAssetPrice` evidence and persisted V7 closes and performs
  no network lookup in the presentation boundary. Incomplete coverage produces no numeric point;
  it never falls back to the silent-drop compatibility pixels.
- Explicit `.shadow` remains available for observation. Explicit `.compatibility` remains the
  data-safe rollback and still uses the structured producer rather than bare `totalAt`. Runtime
  attempts to persist `.structured` remain protected by the operational approval gate.
- Focused cutover/shadow gate passed. Expanded cache/resolver/repository/producer/Dynamics/Cashflow
  gate passed 58/58 on iPhone 17 Pro simulator iOS 26.5:
  `/tmp/millio-emergency-cutover-expanded.xcresult`.
- This is an emergency correctness activation, not Phase 5 acceptance. Real-device diagnosis of the
  `23 147 393 RUB` delta, 30 observations across 7 observation days, two physical transitions
  including offline, explicit UX approval and the rollback drill remain open. Phase 6 remains
  blocked.

### 2026-08-08 — Shared historical FX cache-first loading (Phase 5 remains open)

- Core compatibility totals now use the same persisted `HistoricalRateStore` as legacy replay;
  exact direct/inverse cache hits avoid provider calls and feed the structured local-evidence reader.
- Dynamics prefetch includes both legacy product currencies and core account currencies.
- RUB-involved historical cache misses query CBR first and fall back to Frankfurter; non-RUB pairs
  continue to use Frankfurter directly.
- Production and test targets compile successfully. Two focused test attempts produced result
  bundles (`/tmp/millio-phase5-cache-first.xcresult` and
  `/tmp/millio-phase5-cache-first-retry.xcresult`) but the iOS 26.5 simulator rejected the cloned
  test runner with `launchd job spawn failed`; no test execution is claimed.
- Phase 5 operational gates remain unchanged and open.

### 2026-08-08 — Core-only Dynamics empty-scope correction

- Real-device screenshots disproved the initial FX-only diagnosis: Accounts showed
  `100 070 752 RUB`, while Dynamics showed `0 RUB` and `No products`.
- Root cause was upstream of FX. After the core-primary group flip, Accounts read
  `AccountGroup/Account`, but `coreAccountsForDynamics()` still seeded its scope from legacy
  `FinanceGroup`. A core-only profile therefore produced an empty structured query scope.
- Dynamics now fetches participating `Account` rows directly. Unfiltered mode includes grouped and
  ungrouped core accounts; group filters accept native core UUIDs and retain a legacy-name bridge.
- Added a regression fixture with one grouped core account and zero `FinanceGroup`/`FinanceAccount`
  rows; it asserts non-zero header, chart endpoint and account breakdown.
- `build-for-testing` compiles production and all test targets successfully. Runtime simulator test
  execution remains blocked by the separately recorded cloned-runner launch failure.
- Added a non-PII `HistoricalPortfolio` warning for incomplete series: point count, requested core
  count, coverage, unresolved dimensions and reason codes. It intentionally excludes IDs, names and
  balances and is the device-console evidence needed to distinguish FX/market/cache/readiness gaps.

### 2026-08-09 — Physical-device visual acceptance

- The real portfolio renders the 1W Dynamics chart after exact-date cache-first FX/market warming;
  the acceptance log no longer reports the former manifest semantic, revision-reason, or RUB
  historical-fetch failures.
- Historical consumers agree exactly: `98,898,259 + 958,897 = 99,857,156` in Dynamics and
  Cashflow. The current Accounts/Dashboard balance is `99,967,312`, leaving a `110,156 RUB`
  live-versus-historical-close basis difference. It is recorded, not hidden by forward-fill.
- The grouped legacy migration regression was fixed by committing the newly created group
  prerequisite before entering the converter's clean-context atomic boundary; the focused
  migration and historical suites pass.
- This is device visual acceptance, not the full Phase 5 operational exit. Thirty observations over
  seven civil days, an offline transition, explicit rollback drill, and backend publication remain
  mandatory. Phase 6 deletion is still blocked.

### 2026-08-11 — Archive history access and single entry point

- Device feedback showed that archived core data still participated correctly before `archivedAt`,
  but the archive row did not navigate to `AccountDetailView`; operation history was therefore
  inaccessible and appeared deleted. Archived rows now open the read-only detail/history screen.
- Finance settings now expose one «Архив» entry. Core and legacy stores are routed internally;
  when both contain rows, one archive hub identifies the previous-version storage explicitly.
- Existing archive historical-total invariants and the new exhaustive archive-route test pass.

### 2026-08-11 — Archived core accounts restored to Dynamics history

- Physical-device feedback disproved the earlier lower-level-only acceptance: `AccountsTotalsService`
  preserved pre-archive values, but Dynamics built its structured account scope from accounts that
  participated today. An archived core account was therefore removed before the time-aware valuator
  received the request.
- `coreAccountsForDynamics(scope:)` now distinguishes current and historical selection. Historical
  intervals include every core account whose lifetime overlaps the interval; current summaries keep
  excluding archived accounts.
- Historical FX and market-price warming use the same historical core scope.
- Added a core-specific regression: a 60,000 archived account plus a 30,000 live account produces
  90,000 before `archivedAt` and 30,000 after it. The new test passes. Six of eight tests in the
  surrounding invariant suite pass; two pre-existing one-point-series assertions remain unrelated.
- Debug device build succeeded and was installed on `iPhone A (2)`. Automatic launch was denied only
  because the phone was locked; installation itself completed successfully.
