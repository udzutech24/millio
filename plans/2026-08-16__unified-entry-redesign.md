# Unified Entry redesign and performance

Status: IMPLEMENTED — code and simulator gates complete; target-device performance comparison pending because the designated iPhone is unavailable.

Research: `thoughts/research/2026-08-16-unified-entry-ux-performance-audit.md`

## Phase 0 — Baseline and contract

- [x] Add signposts for selected-tab transition and monthly snapshot loading.
- [x] Create a realistic local performance fixture without personal financial data.
- [ ] Record cold open and repeated expense↔income switch baseline on target iPhone. Blocked on 2026-08-16: `iPhone A (2)` became locked/unavailable; the current dirty Share Extension also prevents a clean rebuild because its App Group provisioning is incomplete.
- [x] Lock history/status semantics: upcoming, paid, all; define how a scheduled item links to its completed transaction.

Evidence: `docs/UNIFIED_ENTRY_PERFORMANCE_BASELINE.md`.

Gate: measured baseline plus unit-tested status classification. No visual changes.

## Phase 1 — One-pass data pipeline

- [x] Introduce a single monthly entry snapshot calculation.
- [x] Remove duplicate category aggregation inside budget summary.
- [x] Add cancellation/latest-request protection and a bounded cache keyed by visible revisions.
- [x] Add focused cache/isolation/zero/large-fixture tests.

Gate: focused tests green; profile demonstrates reduced work. No redesign bundled into this phase.

## Phase 2 — Navigation and history discoverability

- [x] Replace the ambiguous clock action with a labelled `History`/workflow control.
- [x] Add `Upcoming | Paid | All` status filtering and deterministic ordering.
- [x] Preserve month, operation type, and category context when opening history.
- [x] Add filter contract, empty states, and accessibility identifiers.

Gate: paid operations reachable in at most two taps and never disappear without an explanatory filtered empty state.

## Phase 3 — Visual hierarchy and category entry

- [x] Adopt the current Accounts/Cashflow quiet surface language.
- [x] Remove nested decorative strokes and icon-only category-management actions.
- [x] Preserve compact two-column cards; active/non-zero cards lead and zero cards are quieter.
- [x] Add persisted per-kind sort (`activity`, `amount`, `manual`, `name`), pinned-first and stable-after-save behavior.
- [x] Consolidate reorder/settings/create into category management; remove the floating category `+`.
- [x] Keep one tab transition animation and support Reduce Motion.

Gate: screenshot tests on 375/390 pt and accessibility sizes; VoiceOver audit; target-device interaction check.

## Phase 4 — Regression and rollout

- [x] Run focused Unified Entry, category, budget, scheduled/history, localization, and Cashflow regression suites.
- [ ] Compare performance profile to Phase 0 baseline on the designated physical iPhone (device unavailable).
- [x] Preserve existing add/import/plan/recurring routes and historical month behavior in the compiled navigation graph.
- [x] Update technical documentation and implementation history.

Gate: no data/persistence migration, no lost route, measured improvement reported with the same fixture/device.
