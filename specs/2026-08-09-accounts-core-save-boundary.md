# Spec: AccountsCore typed save boundary

## Problem

AccountsCore commit failures are rolled back in some paths but escape as unrelated raw errors. Critical callers cannot classify persistence failure consistently, and duplicated save policy can drift during the legacy-to-Account cutover.

## Goal

Provide one narrow typed commit boundary for AccountsCore interactive mutations without changing successful domain behavior.

## Acceptance criteria

- [x] AC1: A failed save is exposed as `AccountsCorePersistenceError.saveFailed` with a stable operation tag.
- [x] AC2: A failed save rolls back staged changes so a later unrelated save cannot resurrect them.
- [x] AC3: `AccountsCoreService.updateAccount` uses the shared boundary after its clean-context precondition.
- [x] AC4: `AccountProductFactory` uses the same boundary for its disposable transaction context.
- [x] AC5: Domain validation and non-save staging failures keep their original typed errors.
- [x] AC6: Focused unit tests and iOS build pass; `git diff --check` is clean.

## Scope

- Shared AccountsCore save/error boundary.
- AccountsCoreService and AccountProductFactory adoption.
- Failure-path unit tests.

## Non-goals

- No legacy-model deletion or reader cutover.
- No broad cleanup of every `try? save()` in the application.
- No event/lifecycle adoption until each path has an explicit transaction-ownership strategy; shared-context rollback is not safe by default.
- No market gateway, Google Sheets, CloudKit, schema, or production-data migration changes.
- No new repository protocols.

## Constraints and risks

- Rollback is only valid where the boundary owns the context's pending changes.
- Error payload must remain local and must not log user financial data.
- Existing unrelated dirty worktree changes must remain intact.
