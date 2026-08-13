# Spec: Cashflow month workspace redesign

## Problem

The current expense/income add sheet mixes month overview, transaction creation, budgets, category management, search, history, planned operations and bulk import. The hierarchy is visually noisy and functionally ambiguous. Bank statement import and month closing cannot be added safely as more buttons because they require staged workflows and persistent domain state.

## Goal

Create a native-feeling monthly cashflow workspace with transactions as the primary content, fast single entry, a separate import hub/review, and a reversible, auditable month-closing lifecycle. Preserve existing transaction correctness and do not claim backend capabilities that are not implemented.

## Acceptance criteria

### Information architecture

- [ ] Global FAB still opens a scoped single-entry flow without forcing the user through a monthly dashboard.
- [ ] Cashflow tab exposes a dedicated month workspace with one shared selected month and one explicit Expense/Income/Transfer filter.
- [ ] The workspace has a compact system-style header, summary, lifecycle status, transaction list and one prominent nondestructive Add action.
- [ ] Categories are a filter/breakdown or entry shortcut, not a grid of large zero cards before the empty state.
- [ ] Empty month shows one coherent `ContentUnavailableView`-style state with Add as primary and Upload statement as secondary.
- [ ] History, settings, budget, planned/recurring, manual bulk and statement upload have visible text labels in an appropriate menu/hub.
- [ ] Current custom neon/gradient tokens may remain as accents, but repeated nested strokes/glows do not define hierarchy.

### Presentation states

- [ ] Pure presentation logic covers loading, empty, populated, recoverable failure, backend unavailable and unsupported file/bank.
- [ ] Import states cover selecting, uploading, processing, needs review, reconciliation failure, applying and completed.
- [ ] Month states cover in progress, needs review, ready to close and closed.
- [ ] Loading/error/import state is not represented by a growing set of unrelated view-local booleans in one SwiftUI file.

### Import hub and statement review

- [ ] Import hub offers Manual bulk entry and Upload bank statement as separate labeled choices with privacy/support copy.
- [ ] File selection uses system `fileImporter`, single selection, explicit CSV/XLSX/PDF UTTypes, bounded local reads and security-scoped resource handling.
- [ ] Until backend upload/adapters exist, statement upload shows an honest unavailable/unsupported result; no fake success or local LLM substitute.
- [ ] Typed iOS DTOs mirror backend bank-statement schema v1 and decode decimal amounts without lossy `Double` at the network boundary.
- [ ] Review displays operation date, merchant/description, signed amount, category, confidence/review reasons, duplicate/transfer exclusion and reconciliation state.
- [ ] Low-confidence, uncategorized, duplicate and reconciliation-failed rows cannot be silently applied.
- [ ] Statement apply persists transaction-level operations with stable fingerprints; it does not call `persistBulkExpenseImport` or use `monthly_category_rollup`.
- [ ] Original bank documents are not retained after processing by default and are never logged.
- [ ] Existing manual bulk import remains functional and uses one shared post-review transaction-write boundary where practical.

### Month closing

- [ ] Closing scope is one complete calendar month across income, expense and transfer in the current user data scope.
- [ ] V1 allows closing completed past months only; current/future months remain in progress.
- [ ] Readiness checklist distinguishes blocking, warning and not-applicable items: unresolved import rows, duplicates, uncategorized operations, reconciliation, account/month match and pending scheduled writes.
- [ ] Closing writes an auditable append-only event/snapshot and does not mutate/delete transactions.
- [ ] Create/edit/delete, manual bulk, statement apply and scheduled auto-apply share one closed-month mutation policy.
- [ ] Closed months are read-only until explicit reopen confirmation.
- [ ] Reopen appends an audit event and restores edits without deleting close history.
- [ ] New persistence participates in SwiftData schema, backup/restore, CloudKit reconciliation/dedup and migration tests.

### Accessibility and quality

- [ ] RU/EN copy is complete; existing required zh-Hans policy is preserved where repository tests demand it.
- [ ] Dynamic Type through accessibility sizes does not clip primary actions, month title, amounts or status/checklist rows.
- [ ] VoiceOver has ordered groups, explicit labels/values/hints and announces processing/reconciliation changes.
- [ ] All interactive targets are at least 44×44 pt and keyboard/focus behavior remains usable.
- [ ] Reduce Motion replaces decorative transitions with nonspatial alternatives.
- [ ] Visual QA covers at least iPhone SE-class width and current large iPhone in empty, populated, review-error and closed states.
- [ ] Existing single-entry, budget, bulk import, history and transaction-balance regression tests remain green.

## Scope

- iOS IA/presentation refactor.
- Month workspace and transaction list composition.
- Import hub and typed statement integration boundary.
- Statement review and transaction-level apply.
- Month closure domain model, policy and UI.
- Localization, accessibility, tests and visual QA.

## Non-goals

- Implementing backend CSV/XLSX/PDF adapters or upload endpoint from the iOS repository.
- Training a local/remote categorization model.
- Supporting “any bank” before adapters and fixtures exist.
- Replacing Cashflow’s complete chart/analytics tab.
- Redesigning every financial screen or changing Millio’s global brand.
- Automatically closing months without explicit user confirmation.

## Constraints and risks

- Backend Phase 2–4 availability gates the live statement flow.
- Existing user changes in `CardCatalog.swift` and debit-card planning artifacts are out of scope and must not be modified.
- `CashflowTransaction.amount` remains `Double`; network DTOs must preserve decimal strings until an explicit, validated conversion boundary. A global money migration is separate.
- Month-close mutation enforcement is cross-cutting and must precede a “Closed” UI.
- The existing bulk sheet is 2,319 lines; extraction must be incremental and behavior-preserving, not a rewrite without tests.
