# Plan: stock product vertical

## Inputs

- Research: `thoughts/research/2026-08-09-stock-product-vertical.md`
- Spec: `specs/2026-08-09-stock-product-vertical.md`

## Decision

- Chosen approach: FIFO pure replay over AccountsCore events, then typed transaction commands and specialized UI.
- Rejected alternatives: aggregate UI math; schema-first universal trading model; reuse of real-estate valuation semantics.
- Rollback strategy: new engine is additive; writer/UI integrations can be reverted independently. Persisted additions in later phases require additive migration and backward-compatible backup import.

## Phases

- [ ] Phase 1 — research inventory and characterization tests (baseline contract documented; full writer/reader inventory remains)
- [ ] Phase 2 — FIFO lot engine, financial semantics, validation and rollback tests (core slice implemented; split/tax/atomic cash remain)
- [ ] Phase 3 — specialized stock creation and position detail
- [ ] Phase 4 — buy/sell/dividend commands, linked cash and atomic Cashflow projection
- [ ] Phase 5 — price/value/P&L charts and no-look-ahead historical valuation
- [ ] Phase 6 — closed/archive/edit and transaction detail UX
- [ ] Phase 7 — additive migration/backup only for proven persisted gaps
- [ ] Phase 8 — localization, accessibility and 375/390 render audit
- [ ] Phase 9 — release tests, build, screenshots and final audit

## Verification

- Unit tests: focused StockLotEngine and AccountsCoreService suites, then AccountsCore/Finance regression suites.
- Integration/build checks: iOS build, schema/migration/backup gates, localization-key audit, `git diff --check`.
- Acceptance criteria audit: update spec checkboxes and plan status after every evidenced phase.

## Journal

- 2026-08-09: proved current oversell, fee and P&L defects; added FIFO replay and hard writer validation without schema change.
- 2026-08-09: found and fixed SwiftData inverse mutation from validating an event already attached to Account.
- 2026-08-09: `StockLotEngineTests` + `AccountsCoreServiceTests`: 29 tests passed with parallel testing disabled. A broader parallel attempt exposed pre-existing suite isolation instability and is not used as release evidence.
- 2026-08-09: added stock hero, semantic action colors, current-quote refresh/prefill, formatted high-precision trade fields, live gross preview, fee input and disabled oversell save. Reverified 29 focused tests in isolated DerivedData.
- 2026-08-09: screenshot audit fixed 375-pt action overflow, duplicate ticker/name, misleading current-price freshness, zero opening-event noise and incomplete position metrics. Added FIFO average/open basis, realized/unrealized P&L, dividends and total fees; 29 tests and Release simulator build passed.
- 2026-08-10: specialized stock edit now changes metadata and applies an absolute quantity/average-cost correction atomically. The correction is stored as a separate event, so prior trades and realized P&L remain intact. Strengthened the position summary with market-value/total-return highlights and a tinted metric card. `StockLotEngineTests`, `AccountBalanceEngineTests` and `AccountsCoreServiceTests`: 53 tests passed; Release simulator build and `git diff --check` passed.
