# Plan: Cashflow unified upcoming planner

## Status

`IMPLEMENTED — AWAITING UNLOCKED-IPHONE MANUAL ACCEPTANCE QA`

## Inputs

- Research: `../thoughts/research/2026-08-14-cashflow-unified-upcoming-planner.md`
- Spec: `../specs/2026-08-14-cashflow-unified-upcoming-planner.md`

## Decision

- Chosen approach: first fix the shared calendar-day classification bug, then add a narrow unified read-first Upcoming destination backed by one mixed-source presentation contract.
- Rejected alternatives: a UI-only label patch does not fix duplicated actual money; making the large legacy management view optional-kind creates conditional complexity and still risks compact/full source drift.
- Rollback strategy: Phase 1 is a pure classification correction. The unified destination is a replaceable route; legacy kind-specific management remains intact until parity is proven. No schema or destructive data changes.

## Phases

### [x] Phase 1 — fix the actual-versus-planned day boundary

- Add pure `CashflowPlannedDatePolicy` using an injected calendar: one-time planned begins at the start of tomorrow.
- Route `plannedOneTimeTransactions`, `scheduledPlannerEntries` and `scheduledCalendarEntries` through the same policy.
- Add regression tests proving an actual transaction at 00:01, 10:39 and 23:59 today is excluded, while tomorrow is included across time zones.
- Verify recurring next-occurrence behavior is unchanged.

### [x] Phase 2 — unified upcoming read model

- Extend/refine `CashflowUpcomingItem` with stable source/reference semantics for one-time, recurring and deposit-interest items.
- Add one builder API returning the complete chronological collection without compact top-3 truncation; compact card applies its own cap to that result.
- Add pure filter/group presentation for All/Income/Expenses and calendar-day sections.
- Prove compact card and full destination use the same source set.

### [x] Phase 3 — list-first unified destination

- Add `CashflowUnifiedUpcomingView` as a focused read-first screen.
- Default to List and show `All / Income / Expenses` filters.
- Group rows by date and display title, status/source, category, signed amount and currency.
- Route editable scheduled items to existing editors using explicit item references; deposit forecasts remain read-only.
- Add Add menu for Income/Expense; do not infer kind from the first item.

### [x] Phase 4 — route replacement and legacy containment

- Change `CashflowView.openUpcomingPlanner()` to open the unified destination with no `upcomingPlannerKind` state.
- If Calendar is retained, make it consume the same unified read model; otherwise keep calendar management only in the legacy secondary route.
- Keep old kind-specific management reachable only where still needed; do not delete until repository usage and behavior parity are proven.

### [~] Phase 5 — accessibility, localization and device QA

- Complete RU/EN/zh-Hans copy and VoiceOver values.
- Test Dynamic Type and narrow width for mixed currencies and long account/note names.
- Run focused scheduling/upcoming tests, wider Cashflow regression suite, simulator UI route and generic device build.
- Install on connected iPhone and verify: today's `200 RUB` is absent, both directions appear under All, deposit forecast remains visible, list opens first.

## Verification

- Unit tests: planned-date policy, builder source parity, filter/group presentation and route destination.
- Integration/build checks: existing scheduling generation/materialization, month closure, Cashflow totals, localization tests, simulator build and device build.
- Acceptance criteria audit: map every spec checkbox to a test or physical-device screenshot before completion.

## Guard phrase

Implement only after: `Реализуй фазы 1–5 по плану Cashflow unified upcoming planner`.

## Implementation journal

- 2026-08-14: Phases 1–4 implemented. Phase 5 code (RU/EN/zh-Hans, VoiceOver,
  Dynamic Type-friendly rows) implemented.
- Focused Upcoming suites and the wider `CashflowViewModelTests` gate passed on
  `Millio-375-QA`; simulator, generic iOS, and signed connected-device builds succeeded.
- The signed app was installed on `iPhone A (2)`. Launch/manual acceptance remained blocked
  because the phone was locked. Still to verify physically: today's `200 RUB` is absent, All
  contains both directions, deposit forecast is visible/read-only, and List opens first.
- 2026-08-14 follow-up: physical QA exposed disabled opacity for deposit forecasts and ambiguous
  editor routing through duplicate-capable business `uniqueID`. Forecast rows are now static but
  full-opacity with an explicit read-only label; editor references use exact SwiftData
  `persistentModelID`. Regression tests, signed device build, install and launch passed.
