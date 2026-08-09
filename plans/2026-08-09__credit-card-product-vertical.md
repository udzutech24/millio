# Plan: продуктовая вертикаль «Кредитная карта»

## Inputs

- Research: `thoughts/research/2026-08-09-credit-card-product-vertical.md`
- Spec: `specs/2026-08-09-credit-card-product-vertical.md`

## Decision

- Chosen approach: AccountsCore remains the ledger; credit-card-specific pure semantics and commands sit above AccountEvent, with one atomic coordinator for linked Cashflow/transfer writes. Target canonical value is signed net position, but legacy rows are not reinterpreted without a migration fixture.
- Rejected: UI-only adapter over available-balance ledger; parallel credit-card transaction store.
- Rollback: each phase is independently revertible. No schema phase proceeds without export fixture, migration test and restore/rollback proof. Feature UI stays unreachable until semantic gates pass.

## Phases

- [x] Phase 1 — research and characterization of current contract. Evidence: baseline trace + targeted suites pass.
- [x] Phase 2 — spec, architecture decision and phased plan. No production code by guard phrase.
- [ ] Phase 3 — financial semantics/event contracts: add failing characterization/contract tests first; decide compatibility marker/migration; implement pure credit-card balance/presentation semantics and allowed typed events; verify current/historical totals and overpayment.
- [ ] Phase 4 — specialized creation/detail/edit UX: dedicated drafts, validation, `CreditCardDetailSection`, `CreditCardEditSheet`, atomic metadata update; unit + render fixtures.
- [ ] Phase 5 — purchase/refund/repayment/Cashflow: atomic coordinator, stable links/idempotency, source-account policy, insufficient funds, refund cap, once-only expense recognition and rollback tests.
- [ ] Phase 6 — payment/grace/reminders: pure injected-calendar policy, month-end/timezone tests, honest empty states, reuse NotificationManager only.
- [ ] Phase 7 — migration/backup only if Phase 3 proves persisted contract cannot be safely versioned without schema. Add schema version, fixtures, round-trip/corrupt rollback gates; otherwise record `schema unchanged`.
- [ ] Phase 8 — RU/EN/zh-Hans typed presentation, accessibility, raw-key audit, 375/390 render matrix, simulator screenshots for creation/detail/edit/operations/empty/normal/overdue/overpaid/archived.
- [ ] Phase 9 — release audit: targeted + integration + schema/migration/backup/localization/build gates, `git diff --check`, acceptance self-audit, status/handoff/reflection.

## Phase commands

Implementation must be requested literally one phase at a time, beginning with: `Реализуй фазу 3 по плану plans/2026-08-09__credit-card-product-vertical.md`.

## Verification

- Unit: dedicated `CreditCard*Tests`, balance/totals, calendar, validation, localization mappings.
- Integration: AccountsCore/Cashflow/Finance refresh, transaction rollback/idempotency, backup/schema/migration.
- Build/render: app build and simulator matrix on `Millio-375-QA` and `Millio-390-QA`.
- Final gates: no raw keys, wrong debt sign, double Cashflow, inconsistent historical total, partial save or writable archive.

## Status journal

- 2026-08-09: Phase 1–2 completed on dirty user baseline. No production code/schema changed. Baseline targeted tests succeeded. Blocked by required explicit Phase 3 command.
