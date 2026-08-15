# Research: Cashflow unified upcoming planner

- Date: 2026-08-14
- Scope: correct the false inclusion of completed-today transactions in Upcoming and replace kind-specific planner navigation with one truthful income/expense forecast list. Research/spec/plan only in this task.

## Reproduction and evidence

The physical-device screenshot shows a `-200 RUB` expense in both current-period Expenses and Upcoming on 14 August.

The duplication is deterministic in `CashflowScheduledService.scheduledPlannerEntries`:

```swift
let baseline = Calendar.current.startOfDay(for: referenceDate ?? now())
// ...
transaction.transactionDate > baseline
```

A normal transaction saved at 10:39 on 14 August is greater than 14 August 00:00, so it is classified as `.oneTimePlanned` even though it has already been posted. The same boundary exists in `scheduledCalendarEntries`. `plannedOneTimeTransactions` compares against the actual `now`, so the three APIs do not even share one definition of planned.

Navigation is also structurally misleading:

- `CashflowView.openUpcomingPlanner()` chooses `upcomingItems.first?.kind`.
- `CashflowScheduledTransactionsView` requires exactly one `CashflowCategoryKind`.
- Therefore `All` opens either income or expense based on whichever event sorts first; it is not an all-items list.
- Deposit-interest forecasts are merged only by `CashflowUpcomingSectionBuilder`. The full planner reads scheduled transactions directly, so the compact card and destination do not have source parity.
- The full planner defaults to `.calendar`, while the user explicitly needs the list first.

## Current architecture and constraints

- Actual transactions and future-dated planned rows share `CashflowTransaction`; there is no explicit `isPlanned` flag for one-time items.
- Calendar date, not time-of-day, is the product-level scheduling unit. The editor exposes a date picker, so a same-day one-time item cannot honestly represent “later today”.
- Recurring templates are identified explicitly by recurrence metadata.
- Deposit interest forecasts are `AccountEvent` projections exposed through `AccountsCoreDepositCashflowBridge.UpcomingInterestEvent`.
- `CashflowUpcomingSectionBuilder` already merges scheduled income, scheduled expense and deposit forecasts and now preserves source/category/account semantics.
- Existing `CashflowScheduledTransactionsView` is a large management screen with kind-specific creation/editing and calendar logic. Expanding every branch to optional kind would raise regression risk.

## Options considered

### A. Patch only the day boundary

Use tomorrow start instead of today start in the two planner APIs.

- Benefit: removes the visible `200 RUB` duplicate.
- Failure: `All` still opens only one kind; deposit forecasts still disappear; list-first requirement remains unmet.
- Verdict: necessary Phase 1, insufficient alone.

### B. Make the existing management view accept optional kind

Change `kind` to optional and add branches throughout calendar, totals, creation, empty states, titles and editors.

- Benefit: superficially reuses one screen.
- Failure: turns an already large kind-specific management view into a conditional super-screen and couples read-only forecasts to mutation flows.
- Verdict: rejected as fragile.

### C. Add a unified read-first Upcoming planner and keep kind-specific management behind it

Create a narrow unified destination backed by one builder/presentation contract. Default to List; filter `All / Income / Expenses`; include one-time, recurring and deposit-interest forecast rows. Selecting an editable scheduled row opens its editor; deposit forecast opens account/context details or remains read-only. Creation asks income/expense only when the user taps Add. Existing kind-specific management can remain as a secondary compatibility route until parity is proven.

- Benefit: matches the user's mental model and separates forecast reading from management.
- Cost: requires a stable item identity/destination contract and focused navigation tests.
- Verdict: recommended. It is simpler and safer than infecting the legacy view with optional-kind branching.

## Recommended semantics

```text
Completed / actual
  transaction date <= end of today
  never appears in Upcoming

One-time planned
  non-recurring transaction on tomorrow or later

Recurring forecast
  next generated occurrence from a recurring template

Deposit-interest forecast
  future AccountEvent interest projection
```

Unified destination:

```text
Upcoming
├── default presentation: List
├── filter: All | Income | Expenses
├── rows grouped by date
│   ├── title/source/category
│   ├── signed amount/currency
│   └── status: one-time | recurring | forecast
├── optional switch: Calendar
└── Add -> choose Income or Expense -> existing editor
```

## Risks and unknowns

- Existing future-dated actual transactions are indistinguishable from planned transactions. This plan intentionally preserves the existing rule that tomorrow-or-later non-recurring rows are planned; an explicit lifecycle/status migration is a separate feature.
- Time-zone/day-boundary behavior must use one injected calendar and one pure policy to avoid device/test disagreement.
- Editing recurring templates must not edit a generated forecast occurrence as though it were a persisted transaction.
- Deposit forecasts must never be materialized or affect actual cashflow totals merely because they appear in the unified list.
- Mixed currencies must remain separate; no fake aggregate total across currencies.

## Relevant files/tests

- `millio/UI/Services/Cashflow/CashflowScheduledService.swift`
- `millio/UI/Services/Cashflow/Upcoming/CashflowUpcomingSectionBuilder.swift`
- `millio/UI/Services/Cashflow/Upcoming/CashflowUpcomingCard.swift`
- `millio/UI/Services/Cashflow/CashflowScheduledTransactionsView.swift`
- `millio/UI/Services/Cashflow/CashflowView.swift`
- `millioTests/UI/Services/Cashflow/CashflowViewModelTests.swift`
- `millioTests/UI/Services/Cashflow/CashflowUpcomingSectionBuilderTests.swift`
