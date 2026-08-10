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
- [x] Phase 3 — financial semantics/event contracts: legacy available-balance semantics characterized; pure signed snapshot and typed persisted events implemented; current/historical contribution remains one shared path; schema migration proven unnecessary.
- [x] Phase 4 — specialized creation/detail/edit UX: credit-card draft and persisted terms, strict creation validation, `CreditCardDetailSection`, `CreditCardEditSheet`, atomic metadata update and rollback tests. Final localized copy/render matrix remains Phase 8; operation flows remain Phase 5.
- [x] Phase 5 — purchase/refund/repayment/Cashflow: atomic coordinator, stable links/idempotency, source-account policy, insufficient funds, refund cap, once-only expense recognition and rollback tests.
- [x] Phase 6 — payment/grace/reminders: pure injected-calendar policy, month-end/timezone tests, honest empty states, reuse NotificationManager only; debt-first adjustment and formatted limit inputs added from product feedback.
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
- 2026-08-09: Phase 3 completed. Added `CreditCardFinancialContract`, typed purchase/refund/repayment/fee/interest event types and a guarded service writer. Schema unchanged: `AccountEvent.typeRaw` already safely persists additive enum raw values. Serial semantic/catalog/revision suites: 23 tests passed, including historical event-boundary replay. Backup/schema/migration suites passed; full totals gate retains two pre-existing stale characterization failures (`missingHistoricalFX...`, old `.cash` expectation for bankless credit card) unrelated to Phase 3.
- 2026-08-10: Phase 4 completed. Creation persists issuer/last4/limit/debt-derived opening balance/statement and due days/fixed minimum/grace/note/includeInTotal and rejects invalid limit/last4/terms before save. Detail uses canonical debt, available limit, overpayment, utilization, fees and interest. Dedicated edit sheet commits Account + CardMeta atomically and keeps currency read-only; archived cards reject edits. 18 targeted credit-card tests passed before the final creation assertions; clean Debug app build passed after all changes. Re-running the test target is blocked by unrelated committed `FinanceOverviewLedgerStyleTests` references to removed `balanceComposition`, recorded as baseline debt rather than patched in this phase.
- 2026-08-10: Phase 5 completed. Added one atomic `CreditCardOperationCoordinator` for typed card events plus Cashflow projection/repayment legs. Stable caller-owned operation IDs provide retry idempotency and reject conflicting reuse. Purchases/fees/interest create one expense, refunds require an original purchase and reduce that expense up to its remaining amount, repayments accept only active same-currency cash/debit/bank sources with sufficient funds and never enter income/expense totals. Six targeted scenarios passed, including whole-graph rollback; the same gate compiled the app and test target successfully. Schema unchanged.
- 2026-08-10: Phase 6 completed with product feedback. Credit-card balance adjustment now accepts the debt amount and converts it through the canonical compatibility contract. Edit UI uses grouped `AmountTextField` inputs for limit/minimum payment and supports either anchor date + grace days or an exact payment date, plus none/day-of/1/3/7-day reminders and time. A pure injected-calendar policy covers short months, timezone, overdue and empty states; `NotificationManager` schedules one stable one-time request. Payment preferences remain outside the financial schema in typed UserDefaults until the Phase 7 backup decision. 5 calendar-policy tests, the debt conversion test, 4 editor tests and the dedicated notification test passed; app/test compilation passed. Two pre-existing Cashflow reminder assertions remain stale against current localized copy (`Плановый...` / `计划...`) and were not weakened.
