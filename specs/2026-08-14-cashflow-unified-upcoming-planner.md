# Spec: Cashflow unified upcoming planner

## Problem

The current Upcoming section can classify an already completed transaction from today as planned because it compares its timestamp with the start of today. Its `All` action then opens only the kind of the first row, while deposit-interest forecasts are omitted from the destination. The UI therefore duplicates actual money and does not provide one complete forecast list.

## Goal

Make Upcoming a truthful, list-first forecast across income and expenses, with consistent source semantics between the compact card and full destination.

## Acceptance criteria

- [ ] A non-recurring transaction dated today never appears in Upcoming, regardless of its save time.
- [ ] A non-recurring transaction dated tomorrow or later appears once as a one-time planned item.
- [ ] Recurring templates expose only their next valid occurrence and are clearly labeled recurring.
- [ ] Future deposit-interest projections appear as read-only forecast items with account name and never affect actual totals.
- [ ] `All` opens one unified destination containing both income and expense items plus deposit-interest forecasts.
- [ ] The destination opens in List mode by default.
- [ ] Visible filters are `All`, `Income`, and `Expenses`; filtering never changes or deletes data.
- [ ] Rows are sorted chronologically and grouped by calendar date.
- [ ] Each row exposes title, source/status, category where applicable, signed amount and currency.
- [ ] An editable planned/recurring row routes to the correct existing editor/template; a deposit forecast is not editable as a Cashflow transaction.
- [ ] Add from the unified destination explicitly chooses Income or Expense before opening the existing editor.
- [ ] Calendar mode, if retained, uses the same unified item source and never becomes a second definition of Upcoming.
- [ ] Mixed currencies are not summed into a meaningless total.
- [ ] RU/EN/zh-Hans copy and VoiceOver labels describe type, direction, date and amount.
- [ ] Unit tests cover today/tomorrow boundaries, time zones, all filters, mixed-source sorting, source parity and navigation destinations.
- [ ] Existing scheduled generation, month closure and actual Cashflow totals remain unchanged.

## Scope

- Pure planned-date classification policy.
- Unified upcoming item/read model.
- Unified list-first planner destination and filters.
- Navigation from compact Upcoming card.
- Focused localization, accessibility, tests and device QA.

## Non-goals

- Adding an explicit persisted one-time planned status/migration.
- Combining different currencies into one total.
- Rewriting recurring generation or deposit interest calculation.
- Changing actual transaction history or month totals.
- Deleting the legacy kind-specific management screen before route parity is proven.

## Constraints and risks

- Date-only planning means same-day future scheduling is intentionally unsupported; today is actual, tomorrow starts planned.
- The unified read model must not own persistence or duplicate scheduling calculations.
- Dirty unrelated AccountsCore and Phase 9 changes must be preserved.
