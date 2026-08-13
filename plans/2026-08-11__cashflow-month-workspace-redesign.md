# Plan: Cashflow month workspace redesign

## Status

`PARTIALLY IMPLEMENTED` — Phases 1–5 and 7 complete; Phases 6 and 8 remain partial. Live Alfa-Bank XLSX preview/review/apply is wired and proven against the real July export; closure evidence breadth and durable screenshot matrix remain incomplete.

## Inputs

- Research: `../thoughts/research/2026-08-11-cashflow-month-workspace-redesign.md`
- Spec: `../specs/2026-08-11-cashflow-month-workspace-redesign.md`
- Backend dependency: `../../millio-back/plans/2026-08-09-bank-statement-import.md`

## Decision

- Chosen approach: separate month workspace, scoped single entry, import hub/review and month-close lifecycle. Transactions are primary content; categories are secondary navigation/filtering.
- Rejected alternative: cosmetic edit of `CashflowCategoryTransactionSheet`, because it preserves mixed responsibilities and cannot safely host persistent import/close state.
- Rejected alternative: one super-screen per expense/income/transfer tab, because closure is month-wide and transfer is structurally different.
- Rollback strategy: route changes and new features land behind internal presentation/service boundaries. Each visual phase can revert to existing `CashflowUnifiedEntryContainer`; new closure/import data is additive and must remain readable if UI is rolled back. Never roll back by deleting user transactions or closure audit events.

## Architecture target

```text
CashflowMonthWorkspaceView
  -> CashflowMonthWorkspaceViewModel / PresentationBuilder
  -> existing CashflowViewModel read APIs
  -> CashflowEntryFlow
  -> CashflowImportHub
       -> ManualBulkEntryAdapter
       -> BankStatementImportClient -> StatementReview -> StatementApplyService
  -> CashflowMonthClosureService -> CashflowMonthMutationPolicy
```

Do not add all state to `CashflowViewModel`. New presentation/import/closure responsibilities get narrow types and services; existing transaction/category/budget services remain sources.

## Phases

### [x] Phase 1 — presentation contract and navigation boundary

**Change**

- Add pure `CashflowMonthWorkspacePresentation`/state builder covering loading, empty, populated, status and action availability.
- Define navigation destinations/actions for single entry, import hub, history, budget/settings and close flow.
- Split global FAB behavior from month-workspace navigation: FAB remains fast single entry; Cashflow tab gains a month-workspace entry point.
- No new visual screen and no persistence migration yet.

**Expected files**

- New `millio/UI/Services/Cashflow/MonthWorkspace/` presentation/state files.
- Narrow edits to `RootTabView.swift`, `CashflowView.swift` and/or router types only after tests prove routing.

**Acceptance/evidence**

- Pure tests cover every required workspace state and action policy.
- Routing tests prove global FAB does not gain an extra dashboard step.
- Existing `CashflowUnifiedEntryTests` remain green.

**Rollback**

- Remove new presentation/routing types; existing unified entry route remains intact.

### [x] Phase 2 — Apple-style monthly overview

**Change**

- Build `CashflowMonthWorkspaceView`: system navigation/toolbar, explicit segmented filter, compact month picker, summary/status, transaction list, coherent empty state and primary Add action.
- Reuse existing history/editor services; extract only the row/summary adapters needed.
- Replace category grid in the workspace with compact breakdown/filter; keep category-first quick entry inside the scoped entry flow if still useful.
- Use system text styles/materials and project tokens; remove repeated nested neon strokes/glows from hierarchy.

**Expected files**

- New MonthWorkspace views/components.
- Narrow history/analytics adapters.
- `Localizable.xcstrings` and presentation/layout tests.

**Acceptance/evidence**

- Empty month has one empty state, one primary Add and one secondary statement action.
- Populated month shows transactions before category details.
- Dynamic Type layout tests cover compact and accessibility sizes.

**Rollback**

- Route back to the existing unified sheet; no data changes.

### [x] Phase 3 — import hub and manual bulk boundary

**Change**

- Add `CashflowImportHub` with labeled Manual bulk and Upload statement entries plus support/privacy copy.
- Route Manual bulk to the existing sheet while extracting a small protocol/component boundary; preserve its current persistence semantics.
- Add typed statement import client protocol and availability capability, but no fake server implementation.

**Expected files**

- New `ImportHub/` types/views.
- Minimal adaptations to `CashflowBulkExpenseImportSheet` and localization.

**Acceptance/evidence**

- Manual bulk regression suite remains green.
- Backend unavailable/feature-disabled states are explicit and testable.
- Import choices have visible text labels and VoiceOver descriptions.

**Rollback**

- Hide import hub and restore direct manual-bulk entry; no persisted schema involved.

### [x] Phase 4 — bank statement file selection and review

**Prerequisite**

- Backend authenticated preview endpoint and at least one real adapter are implemented and contract-compatible. If absent, this phase stops at a tested unavailable state.

**Change**

- Add system `fileImporter` for one CSV/XLSX/PDF with UTType allowlist, security-scoped access and bounded read/upload.
- Add schema-v1 DTOs preserving decimal strings.
- Add staged processing/review UI with reconciliation, confidence, category edits, duplicate/transfer exclusions and retry/unsupported states.
- Persist only sanitized resumable review state if product requirements confirm resume; original files are discarded.

**Expected files**

- New `StatementImport/` client, DTO, state machine and views.
- Networking registration using existing app conventions.

**Acceptance/evidence**

- Contract fixture decoding matches backend golden fixture.
- State-machine tests cover processing, unavailable, unsupported, reconciliation failure and review.
- Security tests verify no original bytes/PII are logged or persisted.

**Rollback**

- Disable statement capability; manual import remains available and sanitized drafts can be safely discarded.

### [x] Phase 5 — transaction-level statement apply and duplicate safety

**Change**

- Add a dedicated apply service that converts approved statement operations into individual `CashflowTransaction` records.
- Persist stable backend fingerprint in a dedicated import namespace/field design; preflight duplicates atomically before balance effects.
- Share category/account/date validation with manual entry where safe.
- Do not call `persistBulkExpenseImport` and do not create category rollups.

**Expected files**

- New statement apply/domain policy files.
- Minimal `CashflowTransaction`/schema/export/import changes if a dedicated fingerprint field is required.
- Migration, backup, CloudKit/dedup and lifecycle tests.

**Acceptance/evidence**

- Reimport is idempotent; two legitimate equal-amount operations with different fingerprints both survive.
- Transfers/technical rows excluded in review do not affect cashflow totals/balances.
- Failure before save leaves no partial transactions or balance drift.

**Rollback**

- Disable apply entry point. Additive metadata remains readable; never delete imported transactions automatically.

### [~] Phase 6 — month closing domain and mutation policy

**Change**

- Add append-only `CashflowMonthClosureEvent` (close/reopen) and optional immutable close snapshot/evidence.
- Add pure readiness calculator/checklist and one `CashflowMonthMutationPolicy`.
- Enforce policy in create/edit/delete, manual bulk, statement apply and scheduled auto-apply before showing Closed UI.
- Register schema, backup/import, CloudKit merge/dedup and migration behavior.

**Expected files**

- New `MonthClosure/` model/service/policy files.
- Targeted changes to transaction persistence and scheduled service.
- `CashflowFeatureRegistration.swift`, `AppSchemaVersions.swift`, backup/reconciliation paths and tests.

**Acceptance/evidence**

- Completed past month can close only when blocking checklist items pass.
- Current/future month cannot close.
- All mutation paths reject writes to a closed month consistently.
- Reopen appends history and restores writes; previous close evidence survives.
- Disk reopen, schema migration, backup/restore and merge-dedup tests pass.

**Rollback**

- Feature flag hides close actions and mutation enforcement can be reverted only together. Closure events remain additive/readable; no destructive migration.

### [x] Phase 7 — close/reopen UI and status integration

**Change**

- Add compact lifecycle status card to workspace.
- Add close checklist sheet, confirmation dialog, closed summary and explicit reopen confirmation.
- Surface pending scheduled/import work with actionable navigation.

**Expected files**

- MonthWorkspace status components.
- MonthClosure views/localization/presentation tests.

**Acceptance/evidence**

- No primary/destructive styling confusion: Add remains primary; close/reopen are contextual and confirmed.
- Checklist exposes why closing is blocked and where to fix it.
- Closed workspace is read-only and visibly explains how to reopen.

**Rollback**

- Hide UI while retaining domain protection/events; never expose writable UI over a closed month.

### [~] Phase 8 — accessibility, localization and visual QA

**Change**

- Complete RU/EN and repository-required zh-Hans coverage.
- VoiceOver grouping/order, announcements, keyboard focus and Reduce Motion audit.
- Visual QA on SE-class and large iPhone for empty, populated, backend unavailable, review failure, ready-to-close and closed states.
- Remove obsolete visual components only after route parity and repository usage checks.

**Acceptance/evidence**

- Focused UI/presentation/localization tests and full build/test gate.
- Screenshot evidence stored under a task-specific screenshots folder.
- No clipped text, overlapping controls, unreachable actions or duplicate empty states.

**Rollback**

- Accessibility/localization fixes are retained where independent; obsolete component removal is a separate reversible commit.

## Verification

- Unit tests: presentation builder, import state machine, DTO contract, duplicate/apply policy, readiness calculator and mutation policy.
- Persistence tests: disk reopen, migration, backup/import, CloudKit-style dedup and atomic failure behavior.
- UI/layout tests: compact/large width, Dynamic Type, empty/populated/error/closed states and action routing.
- Regression: existing unified entry, editor, budget, history, manual bulk, scheduled transactions and balance-effect suites.
- Build gates: focused tests first, then simulator build/full relevant suite; zero new failures against documented dirty baseline.
- Acceptance audit: each phase journal maps spec ACs to test/screenshot evidence before marking complete.

## Stress-check

- Security/privacy: bank bytes/PII stay transient; logs contain only safe codes/counts.
- Data integrity: statement apply and closure mutations are atomic; fingerprints and close events dedup.
- Offline: manual entry/import remains available; statement service shows unavailable without data loss.
- Concurrency: prevent double apply/close; background/resume does not duplicate operations.
- UX/accessibility: no horizontal page-swipe dependency, 44 pt targets, semantic labels, Dynamic Type fallback layouts.
- Release/rollback: import and closure capabilities independently gateable; additive schema only.

## Journal

- 2026-08-11: repository route/state/data audit completed; Apple HIG checked; research/spec/plan created. No production code changed. Phase 1 awaits guard phrase.
- 2026-08-11: Phases 1–3 implemented and tested: dedicated transaction-first month workspace, direct FAB routing, labeled import hub, manual bulk adapter and honest backend-unavailable statement state. Focused presentation/contract/unified-entry gate passed.
- 2026-08-11: Phase 4 stopped at its documented prerequisite: backend plan is at Phase 1 and has no authenticated upload endpoint or real bank adapter. No fake parsing/success was added.
- 2026-08-11: Phase 5 transaction-level apply boundary implemented with decimal-to-domain validation, stable fingerprint namespace, atomic preflight and idempotency tests; live review/apply route remains blocked by Phase 4.
- 2026-08-11: Phase 6 append-only V9 close/reopen event, readiness calculator, backup importer/dedup and mutation policy added. Enforcement covers editor persistence/delete, manual bulk, statement apply and scheduled paths. Self-review found concurrently added direct AccountsCore debit-card write paths outside that boundary; close UI was therefore removed and Phase 6 remains partial.
- 2026-08-11: Phase 7 blocked until every AccountsCore/direct write path uses the shared mutation policy. Phase 8 localization/accessibility foundations and simulator builds completed, but target-state screenshots could not be produced without onboarding/notification automation; launch screenshots are evidence only, not acceptance evidence.
- 2026-08-11: Stable debit-card coordination surface audited. Shared mutation policy now guards new credit/debit operations, staged debit edits/transfers/deletes, deposit projections, linked Cashflow deletes and category migrations touching historical transactions. Focused card/deposit bypass gate passed.
- 2026-08-11: Phase 7 enabled with live SwiftData status, completed-month readiness sheet, explicit close/reopen confirmations and read-only controls for closed months. Phase 8 UI screenshot tests pass on QA simulators, but runner teardown prevents durable target-state capture; home-screen captures are explicitly rejected as evidence.
- 2026-08-12: Restored the legacy `CashflowView` as the actual Cashflow tab root and added one 44 pt trailing actions menu. Currency moved into the menu; typed routes now reach month/closure, import, history, analytics and expense/income budgets. Global FAB remains direct unified entry.
- 2026-08-12: Replaced the false iOS schema-v1 fixture with the backend contract, added system file importer, authenticated bounded multipart client, explicit processing/unsupported/reconciliation/error/review states, category edits, default exclusion of transfers/technical/duplicate rows, and live atomic transaction-level apply. Backend now exposes a JWT/throttled/bounded preview endpoint returning explicit unsupported until a real fixture-backed adapter exists.
- 2026-08-12: Device screenshot audit found the month domain rendered as an arbitrary day (`12 Aug 2026`). Replaced it with a canonical month/year picker plus 44 pt previous/next controls, removed the duplicate empty-state Add action, and added a hard statement-period boundary: a preview whose first or last operation period is outside the selected calendar month cannot reach review/apply. Focused month/import tests pass. A true bank E2E/reconciliation proof remains blocked because no sanitized export file is present in the workspace or supplied attachment.
- 2026-08-12: Expanded search found a real Alfa-Bank July XLSX on Desktop. Backend production adapter confirmed exact declared/computed reconciliation and stable repeated-preview fingerprints; exact financial totals and identifiers were intentionally omitted from documentation. iOS now excludes both internal and external transfers by default. Raw file/PII was not copied, logged or persisted.
- 2026-08-12: Mutation self-audit closed additional category-merge and legacy linked-transaction purge bypasses. Added repeated-close idempotency and backup-import dedup tests. Real bank adapter/golden parsing and six target-state screenshots remain unproven because the required sanitized statement fixture is absent and no durable QA-state harness exists yet.
