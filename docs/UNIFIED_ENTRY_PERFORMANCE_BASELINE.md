# Unified Entry performance baseline

Date: 2026-08-16
Plan: `plans/2026-08-16__unified-entry-redesign.md`, Phase 0

## Reproducible workload

Set `MILLIO_UNIFIED_ENTRY_PERF_MODE=1` only in a local Debug/UI-test launch.

The mode:

- disables Firebase through the existing testing boundary;
- uses guest/local storage;
- replaces Cashflow transactions with 1,152 deterministic synthetic RUB operations;
- covers 18 calendar months and both income/expense types;
- opens Unified Entry on Income through the existing app deep-link state;
- contains no user-derived names, amounts, account IDs, or financial records.

Implementation: `millio/Core/App/UnifiedEntryPerformanceFixtureSeeder.swift`.

## Instruments boundaries

Subsystem: `com.millio.app` (or the runtime bundle identifier)

Category: `CashflowUnifiedEntry`

Intervals:

- `TabTransition`: from selection change through the existing 250 ms page transition;
- `MonthlySnapshotLoad`: current sequential total/category/budget load, including cancellation outcome and aggregate category count.

No PII or financial values are written to signpost metadata.

## Automated baseline command

```sh
xcodebuild test-without-building \
  -project millio.xcodeproj \
  -scheme millio \
  -destination 'platform=iOS,id=00008150-001E029C0CE3401C' \
  -only-testing:millioUITests/UnifiedEntryPerformanceTests
```

`UnifiedEntryPerformanceTests` records:

- cold launch with `XCTApplicationLaunchMetric`;
- ten Income↔Expense switches with clock, CPU, and memory metrics.

## Current evidence

- Focused unit gate passed on `Millio-375-QA`: history status/link/order tests and deterministic fixture test (`Test-millio-2026.08.16_13-08-50-+0300.xcresult`).
- Simulator cold-launch harness passed once. The first switch scenario correctly failed before measurement because its original navigation prerequisite was unstable; the harness now enters Unified Entry through deterministic deep-link state.
- Target `iPhone A (2)` was initially paired/available, but the runner could not bootstrap while the device was locked (`code 74`). The device later became unavailable.
- A fresh rebuild is independently blocked by the existing dirty `millioStatementShareExtension`: missing simulator build settings and an App Group provisioning profile. Phase 0 did not alter that unrelated work.

## Post-redesign verification

- One-pass snapshot, bounded-cache, sorting, status-contract and deterministic-fixture focused tests pass.
- Full simulator `build-for-testing` passes with temporary command-line overrides required by the unrelated in-progress Share Extension.
- The broader Cashflow regression run passed all selected category, budget, history and localization coverage; one pre-existing stateful ViewModel test was flaky under parallel duplicate execution (passed on one clone and failed on another), with no Unified Entry code in its path.
- The post-change switch UI harness still cannot be treated as evidence: the shared simulator guest store accumulated unrelated test residue and did not finish fixture replacement before the UI wait. Physical comparison remains the authoritative gate.

## Gate status

Implementation is complete. Performance sign-off remains blocked: designated target `iPhone A (2)` is unavailable. Do not claim a measured speedup until both physical tests pass on that same unlocked device and the resulting `.xcresult` metrics are recorded here.
