# Plan: Cashflow primary screen hierarchy

**Status:** COMPLETE — Phases 1–3 implemented and verified.

## Inputs

- Research: `thoughts/research/2026-08-15-cashflow-primary-screen-ui.md`
- Spec: `specs/2026-08-15-cashflow-primary-screen-ui.md`

## Decision

- Chosen approach: keep the existing mirror-bar/net-line chart and introduce a compact selected-period summary in its card; reduce compact-chart height and replace the wide expansion label with a labelled icon control. Rebalance the two month-context actions into primary add and secondary workspace navigation.
- Rejected: cosmetic spacing only; chart replacement; modifying finance calculation or data sources.
- Rollback: retain the current `cashflowChartContent` and `monthContextActions` composition. No data migration or persisted preference changes are involved.

## Phases

- [x] **Phase 1 — compact chart header and period summary**
  - Add a pure presentation policy, with tests, that uses the authoritative period result and transaction totals. Do not reconstruct result from chart income/expense because that omits asset revaluation.
  - Reduce the compact chart's visual height without changing `CashflowChartVariantALayout` scale/minimum-bar behaviour.
  - Move full-screen expansion to a compact, VoiceOver-labelled 44 pt icon action within chart chrome.
- [x] **Phase 2 — action and balance hierarchy**
  - Make “Add transaction” the single visually prominent context action; keep the month workspace labelled and secondary.
  - Tighten the asset summary card: retain all five factual rows, but give “Result” a stronger, less redundant visual ending.
  - Apply `.monospacedDigit()` to every monetary `Text` in the compact summary and asset card, preserving the existing numeric transition without horizontal digit jitter.
  - Use one fixed trailing control slot in every asset-card row, then right-align every amount in the remaining shared value column; show the expand button only where the row is actionable.
  - Preserve existing `cashflow.action.add` and `cashflow.action.month` identifiers.
- [x] **Phase 3 — verification and visual QA**
  - Run focused presentation/layout tests and the Cashflow screenshot test at regular and accessibility text sizes.
  - Audit all acceptance criteria, including zero income/expense, negative result, custom range, closed month and long localized labels.

## Verification

- Unit tests: selected-period summary policy, compact metrics policy, existing chart geometry suite and action layout suite.
- Integration/build checks: focused Cashflow tests, screenshot UI test, iOS build once unrelated `BackendAvailability.swift` compile failure is resolved.
- Acceptance criteria audit: record evidence for every criterion in `specs/2026-08-15-cashflow-primary-screen-ui.md`.

## Phase 1 verification — 2026-08-16

- `swiftc -parse` passed for the changed Cashflow Swift files.
- Focused tests passed on `Millio-390-QA`: `CashflowHeroPresentationTests`, `CashflowInsightsControlsStyleTests`, and `CashflowChartVariantALayoutTests`.
- The build emitted existing Swift 6 warnings in unrelated tests; they did not fail the focused run.

## Phase 2 verification — 2026-08-16

- `swiftc -parse` and `git diff --check` passed for the changed production and test files.
- `CashflowPrimaryScreenLayoutPolicyTests`, `CashflowHeroPresentationTests`, `CashflowActionButtonsLayoutTests`, and `CashflowMonthWorkspacePresentationTests` passed on `Millio-390-QA`.
- Existing action identifiers and routing policy were preserved. The build emitted unrelated pre-existing Swift 6 warnings only.

## Phase 3 verification — 2026-08-16

- Corrected the hero contract to transaction difference (`income - expenses`); asset revaluation remains in the lower balance result.
- Removed the `ViewThatFits` vertical fallback that caused the approved horizontal hero to stack on a real phone.
- Focused unit/layout suites passed, including zero and negative cashflow cases.
- `ScreenshotTests.testScreenshot03Cashflow` passed on 375 pt and 390 pt QA simulators; an additional 375 pt run passed with `accessibility-large` content size.
- The first 375 pt screenshot attempt hit a transient simulator `SpringBoard` preflight-busy error; rebooting that isolated QA simulator resolved it and the retry passed.
