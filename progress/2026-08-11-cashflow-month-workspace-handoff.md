# Handoff: Cashflow month workspace redesign

- Goal: implement all feasible phases of `plans/2026-08-11__cashflow-month-workspace-redesign.md` without faking backend statement support or exposing a writable closed month.
- Current status: Phases 1–5 and 7 complete. Phases 6 and 8 partial. The real Alfa-Bank July XLSX now passes authenticated transport contract, deterministic preview, review policy and atomic apply boundaries.
- Latest UI correction: month selection is now month/year-only and canonicalized to the first day internally; arrows move by whole months. The prior exact-day label was a domain/UI bug. Empty state no longer duplicates the persistent Add action. Statement previews are rejected before review/apply when their declared period crosses or differs from the selected month.
- Latest statement review correction: included rows are aggregated visually by category with exact decimal totals. Account attribution is optional, and statement apply never mutates the current account balance (`affectsCardBalance = false`); the UI states this guarantee explicitly.
- Completed: transaction-first month workspace; direct FAB route policy; labeled import hub; manual bulk reuse; typed schema-v1 statement DTO/client and honest unavailable state; transaction-level idempotent apply service; append-only V9 close/reopen events; readiness calculator; policy enforcement in Cashflow persistence/delete, manual bulk, statement apply and scheduled paths; RU/EN/zh fallback copy; schema and regression tests.
- Remaining: sanitized bank fixture and one real adapter/golden suite; disk-reopen/migration breadth for closure; durable empty/populated/backend-unavailable/review-failure/ready/closed screenshots and final accessibility QA.
- Decisions and reasons: close/reopen UI was restored only after direct credit-card, debit-card, deposit projection, linked-delete and category-migration paths were routed through the shared mutation policy and focused bypass tests passed.
- Changed files: new `MonthWorkspace/`, `ImportHub/`, `StatementImport/`, `MonthClosure/` files and four focused test files; targeted edits to `RootTabView.swift`, schema V9, feature registration, persistence, scheduled service and manual bulk boundary.
- Tests run and results: new menu/contract/state/closure focused gate passed; category-breakdown and unlinked-account apply tests passed on `Millio-390-QA`; relevant bulk/unified/apply/category/schema/credit/debit/deposit regression gate passed; backend bank-statement suite 30/30 and Nest build passed; Debug simulator and signed physical-device builds passed. Latest build installed and launched on `iPhone A (2)` (`com.millio.app`).
- Risks/blockers: the real file is intentionally not copied into the repository because it contains PII; the committed golden is synthetic and sanitized but matches the proven layout. Production requires a stable `BANK_STATEMENT_ACCOUNT_SCOPE_SECRET`. Durable target-state screenshots are still not proven because the UI test runner teardown leaves the simulator on its home screen.
- User workflow note: August 2026 cannot be closed on 12 August 2026 because it is still the current month. Import/review may happen during August, but closure becomes eligible only after the calendar month completes and all real checklist evidence passes.
- Real-file evidence: local Alfa XLSX produced schema-v1 `ready`, exact reconciliation and stable fingerprints on a second preview. Exact financial totals and identifiers were intentionally omitted. Transfer policy reduced the import candidates without silently mutating phone data.
- Exact next action: attach one sanitized real bank export (the original extension and complete header/technical/total rows must remain intact). Then implement only that format/template adapter and golden reconciliation suite; independently add a durable QA-state screenshot harness.

## Ownership manifest

Initial user-owned baseline (never intentionally edited):

- `millio/UI/Services/CardIndex/CardCatalog.swift`
- `millioTests/Core/AccountsCore/AccountBalanceEngineTests.swift`
- `millioTests/UI/Services/CardIndex/CardCatalogTests.swift`
- debit-card plan/spec/research/status/reflection/improvement artifacts

Concurrent user-owned changes observed during implementation and excluded from cashflow scope:

- `millio/Core/AccountsCore/DebitCard/`
- `millio/UI/Services/Finances/AccountsCore/DebitCard/`
- `AccountProductFactory.swift`, `ProductDefinitionCatalog.swift`, `AccountDetailView.swift`
- debit-card contract/coordinator tests
- concurrent edits in `AccountsCoreCashflowBridge.swift` and its tests

Cashflow plan/status/research/spec were pre-existing untracked files; only the explicitly authorized plan and status were updated.
