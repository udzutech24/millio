# Debit card product vertical — release handoff

Date: 2026-08-11

## Outcome

Phases 1, 1Q and 2–9 completed in order. Debit operations use the existing `AccountEvent` ledger and one coordinator-owned AccountEvent + Cashflow commit. Credit-card debt/limit/grace/repayment semantics remain separate.

## Release evidence

- Cashflow regression: 89/89 passed (`Test-millio-2026.08.11_20-34-38-+0300.xcresult`).
- Combined debit, AccountsCore, Cashflow, Finance, backup and localization regression passed (`Test-millio-2026.08.11_20-51-28-+0300.xcresult`).
- Debug and Release simulator builds passed.
- Render matrix: 32 PNGs in `screenshots/2026-08-11-debit-card-render-matrix/`.
- Localization JSON, static writer/sensitive-log scans and `git diff --check` passed.

## Data decision

Schema unchanged. Existing backed-up `CashflowTransaction.operationGroupID` carries refund linkage. Legacy `Card` and its PAN/CVV fields remain persisted; no deletion or migration was authorized or performed. New debit paths accept only optional validated last4 and do not log it.

## Reflection

The useful failures were gate failures, not noise. The Cashflow recurrence hang exposed a missing cursor advance; mutable clock capture caused nondeterminism; the 375-pt render exposed clipped incomplete copy; the broader Finance suite exposed omitted legacy credit debt. Each fix landed in the shared production path while test contracts stayed unchanged. The remaining architectural debt is the retained legacy `Card` security surface, which requires a separately authorized migration rather than opportunistic cleanup.

## Residual risk

The release is locally ready. Remaining risk is operational/device-level validation outside this workspace and the explicitly retained legacy PAN/CVV schema. The DEBUG QA harness is opt-in via `MILLIO_DEBIT_CARD_QA=1` and is absent from Release compilation.
