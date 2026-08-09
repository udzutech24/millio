# Accounts history Phase 6 — cleanup preparation

**Status:** STATIC READY; destructive source cleanup is deliberately deferred.

**Prerequisite:** Phase 5 accepted and its rollback/observation window completed. This document is
an inventory, not permission to remove a still-active rollback or shadow path.

## Evidence retained by design

- V7 `HistoricalPortfolioValuation` rows, manifests and backfill checkpoints are financial evidence;
  Phase 6 does not delete them.
- `Account`, events, `AccountDailySnapshot`, legacy Card/Credit/Investment history and migration
  evidence remain source data. Physical source-data cleanup is outside this initiative.
- `.compatibility` remains a structured producer mode. Rollback must never re-enable a bare numeric
  result or `nil dependency => omit account` semantics.

## Deferred source deletions after the rollback window

The following code is still executable today and therefore must not be removed before Phase 5
acceptance. Delete it only in one bounded cleanup change after a repository search proves that no
non-test caller remains.

1. `Core/AccountsCore/AccountsTotalsService.swift`
   - `totalAt(_:in:participatingOnly:)` — quarantined bare numeric historical reader;
   - `seriesBetween(start:end:currency:)` — bare series assembled from `totalAt`;
   - preserve structured `historicalValuation` and the live/scoped APIs needed by current-value UI.
2. `UI/Services/Finances/FinanceDynamicsViewModel.swift`
   - shadow-only legacy series/replay: `buildTimeSeriesData`, `calculateBalanceAtDate` and their
     private replay helpers/caches;
   - compatibility aggregation that calls `accountsTotalsService.totalAt`;
   - legacy/core independent breakdown helpers (`legacyAccountDynamicsRows`,
     `coreAccountDynamicsItems`, `coreContributionWithLegacyPredecessor`) only after every visible
     projection is sourced from `HistoricalPortfolioSeriesResult`;
   - old header, group and distribution recomputation branches guarded by `.shadow`.
3. `UI/Services/Cashflow/CashflowViewModel+Categories.swift`
   - `resolveCompatibilityAssetsSnapshot` and temporary `FinanceViewModel` /
     `FinanceDynamicsViewModel` construction after shadow observation ends.
4. `UI/Services/Finances/FinanceViewModel.swift`
   - `computeDashboardDeltaViaAnalytics` and its temporary Dynamics replay after dashboard history
     consumes the producer;
   - the `newCoreTotalProvider -> totalAt(Date())` path is a current-value exception until a typed
     live total replaces it. Do not remove it merely because its callee name is historical.
5. `Core/AccountsCore/HistoricalValuation/HistoricalPortfolioSeries.swift`
   - `.shadow`, shadow configuration fallback and the UserDefaults key only after the observation
     window;
   - keep `.compatibility` as the data-safe rollback mode unless release policy explicitly retires
     rollback as part of the completed window.

## Product heuristics audit

`AccountProductFactory`, `ProductDefinitionCatalog`,
`FinanceProductCreationCommandResolver` and verified migration evidence are canonical and stay.
Do not broadly delete `AccountsCoreAdditionBridge`: it still owns meta construction used by the old
form. The specifically obsolete candidates are duplicate preset-to-kind inference helpers such as
`assetKind`/`depositKind`/money-obligation kind selection, but only when repository search proves all
production creation routes resolve an `AccountProductType` first. Migration-only inference in
`AccountProductIdentityMigrator` is not a creation heuristic and must remain deterministic and
fail-closed to `unknownLegacy`.

## Tests and source-contract cleanup

- Keep `HistoricalPortfolioReaderCutoverTests` and
  `CashflowHistoricalPortfolioCutoverTests`; tighten them after deletion to ban production
  references to `totalAt`, `buildTimeSeriesData`, `calculateBalanceAtDate` and temporary Dynamics
  calculation services.
- Replace `FinanceDynamicsHistoricalLineageBaselineTests`: it intentionally asserts the old
  divergence and wraps the desired result in known issues. Once Phase 4 is accepted, retaining that
  test would preserve obsolete architecture rather than protect it.
- Move behavioural coverage currently calling `totalAt` for account replay, lifecycle and migration
  to structured valuation/producer APIs before deleting `totalAt`. Tests are callers too; deleting
  the API first would throw away useful coverage.
- Final source gate must distinguish live-current APIs from historical consumers. A blind grep for
  `totalAt` is insufficient while dashboard/current group totals still intentionally use current
  values.

## Documentation updates required at final cleanup

- `docs/CURRENCY_POLICY.md`: resolver provenance, frozen close and incomplete behaviour.
- `docs/BACKUP_RESTORE_SCHEMA.md`: V7 close/manifest/checkpoint payloads, restore readiness and
  duplicate winner policy.
- schema architecture documentation: V5/V6 frozen compatibility and additive V7 ownership.
- reconciliation documentation: scope readiness, revision rebuild and no publication during partial
  merge/restore.
- historical architecture document: one producer, point identity, consumer projections, structured
  compatibility rollback and explicit live-only exceptions.
- mark superseded plans as historical evidence; do not rewrite their recorded baselines as if they
  described the new implementation.

## Final Phase 6 source gates

Run after the deferred deletion, together with focused suites, schema fixtures, clean build and
device smoke:

```text
production historical consumers of totalAt / seriesBetween                     = 0
production references to buildTimeSeriesData / calculateBalanceAtDate           = 0
temporary FinanceDynamicsViewModel instances used as calculation services       = 0
bare numeric historical values accepted by UI/ViewModel                         = 0
shadow-only compatibility producer/replay paths                                 = 0
product creation paths bypassing ProductDefinitionCatalog + AccountProductFactory = 0
destructive deletion of source or superseded close evidence                     = 0
```

The gate is semantic: comments and archived plans may name removed APIs, and structured
`.compatibility` is allowed. Every executable match must be classified, not suppressed with a
broader regex.

## Exit evidence still deferred

- accepted Phase 5 observation summary and classified delta inventory;
- proof that the rollback window ended;
- focused and full relevant test result bundles;
- V6→V7 fixture and backup/restore gates;
- clean build and device smoke;
- final AC matrix for E1–E3 and Definition of Done.
