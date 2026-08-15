# Spec: usable bank statement review and categorization

## Problem

The current review makes users categorize nearly every row manually, hides the final action below a long list and represents excluded transfers as an unexplained counter/disabled row.

## Goal

Make a 50–200 row statement review fast, explainable and safe: most rows categorized automatically, ambiguous rows concentrated in one queue, transfers excluded by default and the final financial write explicit.

## Acceptance criteria

- [ ] Cashflow has no cyclic route that presents another Cashflow root inside itself.
- [ ] Root overflow contains only infrequent settings; period, chart, budgets, history and import have visible contextual entry points.
- [ ] `Month` is not duplicated as an overflow destination when the selected period already defines month context.
- [ ] Every open month persistently exposes sibling `Add operation` and `Import` actions; both inherit the selected month.
- [ ] Month detail has one back route and no duplicate analytics/import/history overflow or mini-app quick-navigation grid.
- [ ] Closed month keeps both write actions visible but disabled with one clear explanation.
- [ ] Root Cashflow is the only dashboard; month detail never contains another chart/dashboard.
- [ ] Outside `.specificMonth`, month-scoped Add/Import requires an explicit month choice and never reuses stale state.
- [ ] Backend returns deterministic non-`other` suggestions for covered fixture descriptions with taxonomy ID, confidence and source.
- [ ] iOS rejects unknown/wrong-kind category IDs and applies precedence: session override > learned local mapping > valid backend suggestion > fallback.
- [ ] Confirmed corrections can be remembered locally and improve the next import; cancelling review learns nothing.
- [ ] Learning uses a sanitized stable merchant key; an unstable full description is never used as identity.
- [ ] Review is a dedicated navigation destination, not appended below import-method choices.
- [ ] Default landing shows only rows requiring attention; user can switch to category groups or all operations.
- [ ] Category group shows count and exact amount per currency and supports changing the whole group with confirmation.
- [ ] Transfers are excluded by default and visible in a separate group. `Exclude all` is one action.
- [ ] Internal transfers remain excluded. Only an external transfer can enter Cashflow after explicit conversion to income/expense and category selection.
- [ ] Duplicate and technical rows remain non-importable; UI explains why.
- [ ] Account attribution and balance guarantee are configured in the confirmation step, not before review.
- [ ] Primary `Import N operations` action remains visible in a bottom safe-area bar and is disabled with a specific reason when invalid.
- [ ] Final confirmation shows included/excluded/reclassified counts, totals by currency, account attribution and the guarantee that account balance is unchanged.
- [ ] Statement reconciliation and proposed import totals are displayed separately.
- [ ] Existing local fingerprints are marked before confirmation; apply result distinguishes inserted and skipped rows.
- [ ] Category groups are keyed by transaction kind, category and currency.
- [ ] Account existence and open-month status are revalidated at apply; failure causes no learning or partial write.
- [ ] No statement bytes, raw PII or merchant descriptions are added to logs/analytics.
- [ ] VoiceOver, Dynamic Type and compact-width acceptance pass for 0, 1, 52 and 200 rows.

## Scope

- Cashflow root/month information architecture and route ownership.
- Alfa XLSX rule categorization and shared taxonomy contract.
- iOS category resolver, learned mapping integration, dedicated review navigation and transfer policy.
- Unit, contract, integration, layout/accessibility tests and physical-device acceptance.

## Non-goals

- LLM/cloud AI categorization.
- Automatic mutation of current account balances.
- Automatic matching of both sides of an internal transfer in this phase.
- Additional bank formats without sanitized fixtures.

## Constraints and risks

- Financial writes still require final explicit user confirmation.
- Category totals never sum different currencies together.
- Rules must be explainable and conservative; low confidence goes to `Needs attention`.
- Confidence thresholds and attention reasons are named domain policy, not UI constants.
- Existing user-owned dirty worktree changes remain untouched.
