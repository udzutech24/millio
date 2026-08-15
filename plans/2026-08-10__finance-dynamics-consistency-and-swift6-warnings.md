# Finance Dynamics consistency and Swift 6 warnings

Status: phases 1–5 implemented; full test execution blocked by an unrelated test compile error.

## Problem proof

1. The screenshot shows `+63 142 099 / +174.0%`, while the visible weekly line moves only from roughly 97.8M to 99.4M. Header and chart therefore consume different historical results.
2. `historicalScopedSeries` mutates shared `historicalPortfolioSeries` before `updateChartDataAsync` checks `expectedRevision`. A stale task can overwrite the bundle after a newer task has committed `chartData`; header and breakdown then read the stale bundle.
3. `structuredDynamicsBreakdown` requires every account ID to have both a first and last contribution. Accounts created inside the selected period are dropped instead of receiving a zero endpoint.
4. Core `AccountGroup` metadata is mapped to legacy `FinanceGroup` by name. On a core-only portfolio `state.groups` can be empty, so valid core groups lose identity and group rows disappear.
5. The four reported compiler warnings are confirmed in:
   - `HistoricalValuationBackfill.swift`: two `@Sendable` closures capture non-Sendable `UserDefaults`.
   - `DataRepository.swift`: a nonisolated protocol requirement is implemented by actor-isolated SwiftData-backed methods.
   - `LegacyHistoricalValuator.swift`: a main-actor singleton is referenced from a default-argument/nonisolated context.

## Acceptance criteria

- [x] Chart, hero balance, absolute delta, percentage and breakdown are committed from the same revision and the same `HistoricalPortfolioSeriesResult`.
- [x] A stale async request cannot mutate any visible series-derived state.
- [x] For an account absent at one endpoint, breakdown uses the financial zero contribution at that endpoint; it does not drop the row.
- [x] Core-only accounts appear under their real `AccountGroup`; accounts without a group appear once under Ungrouped.
- [x] Groups and Accounts totals reconstruct the same selected endpoint.
- [x] Percentage is finite and truthful; zero baseline with a non-zero delta has an explicit presentation policy rather than a magic `999999%` sentinel.
- [x] The four Swift 6 concurrency warnings are eliminated without `@unchecked Sendable` on mutable objects merely to silence the compiler.
- [ ] Relevant unit tests and a warning-filtered iOS build pass.
- [x] Invalid historical close records in the active scope are deleted without touching valid closes, other scopes, accounts or events.
- [x] Any cleanup enqueues a durable full-scope rebuild and stale completed checkpoints are force-replayed before the marker is acknowledged.
- [x] Hero, delta, groups and accounts use the first and last renderable chart points rather than incomplete requested boundaries.

## Implementation plan

### Phase 1 — atomic Dynamics projection

- [x] Make historical producer helpers return the structured bundle alongside projected chart points without mutating view-model state.
- [x] After the existing revision guard, atomically commit bundle, chart points, hero values and breakdown on `MainActor`.
- [x] Add a deterministic delayed-producer/revision regression test proving stale completion cannot overwrite current UI state.

### Phase 2 — account/group endpoint semantics

- [x] Build breakdown over the union of endpoint contribution IDs and use zero for an absent endpoint.
- [x] Introduce presentation group identity that supports both core `AccountGroup.id` and legacy `FinanceGroup.groupUniqueID`; do not join unrelated entities by display name.
- [x] Add core-only, account-created-mid-period, ungrouped, and Groups==Accounts invariant tests.
- [x] Replace the `999999` percent sentinel with an explicit optional/undefined percentage presentation contract and tests for zero/near-zero baselines.

### Phase 3 — Swift 6 warnings

- [x] Capture a sendable checkpoint/rebuild storage adapter rather than `UserDefaults` in `@Sendable` closures.
- [x] Align `DataRepositoryProtocol` isolation with its SwiftData implementation using a MainActor-isolated production conformance while keeping the neutral protocol, test doubles and worker methods off-main.
- [x] Move singleton default resolution into the main-actor initializer body for `LegacyHistoricalValuator`.
- [x] Compile the affected test suites and run the warning-filtered build. Test execution remains blocked by the unrelated ledger-style test compile error.

### Phase 4 — invalid close cleanup and full rebuild

- [x] Add a repository repair operation that validates every close in the active scope with `decodedResult`, deletes only unreadable derived rows, and saves atomically.
- [x] Run repair before ordinary historical maintenance; when rows were deleted, enqueue a durable rebuild marker and force-replay every planned daily close.
- [x] Preserve valid/quarantined duplicate evidence, other scopes, accounts and events.
- [x] Add unit coverage for scope isolation, valid-row preservation and idempotency; existing runner tests cover forced checkpoints and marker acknowledgement. Execution is blocked by the unrelated ledger-style test compile error.

### Phase 5 — visible chart endpoint projection

- [x] Define one ordered set of structured points whose valuation total is renderable.
- [x] Derive hero balance/delta and group/account breakdown from the first and last points in that set.
- [x] During chart scrubbing, select the nearest renderable point rather than an incomplete requested point.
- [x] Add a regression test with incomplete outer dates and valid inner chart points. The test source compiles; execution is blocked by the unrelated ledger-style test compile error.

## Verification

- Focused Dynamics series, breakdown, core contribution and presentation test suites.
- Historical valuation backfill tests and DataRepository backup/import tests.
- `xcodebuild` for the `millio` scheme with warnings filtered for the four touched types.
- Manual simulator check of 1W Dynamics: hero delta equals last-minus-first visible point; both tabs contain rows.

## Rollback

Phases 1–3 are projection/concurrency changes. Phase 4 deletes only locally derived close rows that fail the canonical decoder; source accounts/events remain intact and a durable marker makes rebuild retryable. Revert phase 4 to stop future cleanup; deleted invalid cache rows are intentionally recoverable only by rebuild, not rollback.

## Journal

- 2026-08-10: screenshot and source tracing proved stale-series mutation, endpoint intersection loss, legacy-name group mapping, and four Swift 6 warning sources. No production code changed because the required guard phrase was not provided.
- 2026-08-10: phase 1 implemented. `HistoricalDynamicsProjection` is now the immutable producer output and `commitHistoricalProjection` is the sole post-revision mutation boundary. Added a delayed-loader regression test. Production build passed on iPhone 17 / iOS 26.5. The test target is currently blocked before execution by pre-existing user changes in `FinanceOverviewLedgerStyleTests.swift` referencing a missing `balanceComposition`; the new test file itself compiled successfully.
- 2026-08-10: phase 2 implemented. Endpoint rows use the union with financial zero for an absent contribution. Group aggregation uses typed core/legacy identity instead of a name join, includes core-only groups and emits one Ungrouped row. Percentage is `Double?`; zero baseline plus non-zero delta is explicitly undefined and omitted in UI. Added endpoint/group/invariant and undefined-percentage tests. Production build passed on iPhone 17 / iOS 26.5. Focused tests remain blocked before execution by the same unrelated `FinanceOverviewLedgerStyleTests.balanceComposition` compile error; all phase-2 test sources compiled without their own diagnostics.
- 2026-08-10: phase 3 implemented. Rebuild marker access now crosses an actor adapter instead of capturing `UserDefaults` in sendable closures. `DataRepository` uses a MainActor-isolated production conformance; the neutral protocol avoids actor-isolating mocks, while static reconciliation/worker helpers remain explicitly nonisolated. `LegacyHistoricalValuator` resolves the shared currency service inside its MainActor initializer. Release build passed and the warning filter for all four original diagnostics returned no matches. Relevant test suites compile, but execution remains blocked by the unrelated missing `FinanceOverviewLedgerStyle.balanceComposition` contract.
- 2026-08-10: device logs proved persisted semantic corruption (`manifestSemanticallyInvalid`) and incomplete closes (`2/8`, `9–10/31`, `11/97`). Owner authorized phase 4: targeted invalid-cache cleanup plus full rebuild; implementation started.
- 2026-08-10: phase 4 implemented. Repository cleanup uses the canonical decoder under the publication lock and deletes only invalid rows in the active scope. Production maintenance enqueues `invalid_historical_close_cleanup` and forces the durable rebuild path. Added scope/preservation/idempotency coverage. iPhone 17 / iOS 26.5 production build passed. Test execution remains blocked before running by the pre-existing `FinanceOverviewLedgerStyle.balanceComposition` compile error.
- 2026-08-10: owner clarified that the visible chart is already correct; phase 5 authorized to project hero, delta and breakdown from the same renderable endpoints instead of failing on incomplete requested boundaries.
- 2026-08-10: phase 5 implemented. `structuredVisiblePoints` is the shared endpoint policy for hero, scrub selection and breakdown. Added an incomplete-outer/valid-inner regression test. Production build passed on iPhone 17 / iOS 26.5; the new test compiles, but test execution remains blocked by `FinanceOverviewLedgerStyle.balanceComposition`.
