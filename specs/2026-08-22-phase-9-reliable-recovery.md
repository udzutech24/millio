# Spec: Phase 9 — reliable data and subscription recovery

## Problem

After reinstall, Millio can bind an empty authenticated scope and still show onboarding without offering an existing CloudKit backup. Manual restore can wait indefinitely and declares success without a verified import receipt. Backups are lifecycle-timed rather than change-driven, refresh completion is not coordinated across primary screens, scope transitions are not diagnosable as expected versus looping, and subscription recovery lacks a guided clean-install state.

## Goal

Make data and entitlement recovery explicit, bounded, verifiable, scope-safe, privacy-safe, and consistent across cold start and Profile.

## Acceptance criteria

- [ ] **R9-01 Authenticated pre-onboarding recovery:** after successful login binds an empty user scope, backup discovery runs before onboarding content regardless of the local onboarding flag. No restore is offered into guest or stale scope.
- [ ] **R9-02 Safe eligibility:** a non-empty local store is never automatically replaced. Unknown local count blocks destructive recovery and produces an actionable error.
- [ ] **R9-03 Single coordinator:** launch recovery, `RestoreView`, and `BackupManagementView` use one coordinator and one typed state machine: search, download, validate, import, verify, finish.
- [ ] **R9-04 Bounded execution:** each remote stage and the overall operation have explicit deadlines. Timeout cancels cancellable work and never leaves a hidden task mutating data. Retry starts a new generation and stale callbacks cannot update UI.
- [ ] **R9-05 Cancellation contract:** search/download/validation can be cancelled. Once snapshot replacement crosses the destructive boundary, UI says it is finishing safely and does not promise cancellation until import/rollback settles.
- [ ] **R9-06 Explicit confirmation:** restore requires a confirmation showing backup date, size, expected model count when available, destination scope label without identifier, and the fact that local data will be replaced.
- [ ] **R9-07 Verified receipt:** success contains expected backup model count, local count before, local count after, duration, and migrated/deduplicated adjustment if applicable. Success is impossible when verification fails.
- [ ] **R9-08 Rollback:** import or verification failure restores the pre-restore snapshot and reports whether rollback succeeded. A rollback failure is a distinct highest-severity error.
- [ ] **R9-09 Unified refresh:** after verified restore, Dashboard, Accounts, Analytics, and Cashflow reload against the same active scope generation. Completion is observable and tested; one generic fire-and-forget event is insufficient proof.
- [ ] **R9-10 Change-driven auto-backup:** committed relevant data changes schedule one debounced backup. Repeated changes coalesce; restore/reconciliation/empty/unknown stores block it; backgrounding requests a safe flush/fallback.
- [ ] **R9-11 Freshness truth:** code, backup screen, README, and schema documentation describe the same change-driven behavior and maximum-staleness fallback. The current 6h/24h contradiction is removed.
- [ ] **R9-12 Backup concurrency:** backup, restore, and scope reconciliation cannot mutate/export the same scope concurrently. A scope-generation change cancels pending debounce work.
- [ ] **R9-13 Scope diagnostics:** logs record transition generation, reason, requested/coalesced/cancelled/committed/root-rebuilt state, and elapsed time without user IDs, emails, raw scope names, store filenames, backup record names, or model data.
- [ ] **R9-14 Jank classification:** tests and manual diagnostics distinguish the one expected cold-start guest→authenticated transition from repeated scope commits/root rebuilds; repeated transitions in a bounded window emit a non-PII diagnostic warning.
- [ ] **R9-15 Subscription verification:** startup checks `Transaction.currentEntitlements` with explicit checking/resolved/degraded state and updates the app snapshot without requiring manual sync in the normal case.
- [ ] **R9-16 Subscription recovery:** when entitlement is absent or uncertain, UI offers a clear user-triggered Restore Purchases action. Only that action calls `AppStore.sync()` and reports success, no active entitlement, cancellation, offline, and verification failure distinctly.
- [ ] **R9-17 Privacy and localization:** all new UI strings are localized in supported languages; logs and diagnostics pass PII guards; accessibility labels and Dynamic Type are covered for confirmation, progress, retry, cancellation, receipt, and subscription states.
- [ ] **R9-18 Regression gates:** focused unit tests pass, the existing backup/import/reconciliation/startup/subscription suites pass, and a signed archive is built and entitlements/signature are verified. Device install and manual clean-install checklist require a separate explicit user authorization.

## Scope

- App-layer recovery state machine and integration with authenticated startup/onboarding.
- Typed restore progress, deadlines, cancellation boundary, retry, errors, receipt, verification, and refresh acknowledgement.
- Change-driven auto-backup scheduling with background fallback.
- Privacy-safe scope transition instrumentation and loop classification.
- StoreKit clean-install verification and explicit restore-purchases UX.
- Unit/integration tests, localization, backup/runbook documentation, signed-build verification.

## Non-goals

- Enabling SwiftData CloudKit live synchronization.
- Merge restore or per-model user selection.
- Reading or displaying backup contents beyond safe metadata/counts.
- Deleting/reinstalling the app, deleting phone or CloudKit data, or installing a build without explicit authorization.
- App Store upload/review, production CloudKit schema mutation, backend changes, commit, or push.

## Constraints and risks

- Snapshot replacement remains the canonical restore semantic.
- Coordinator must remain bound to one authenticated scope generation.
- Verification rules must account for documented migration/dedup effects; a hand-waved equality check is not acceptable.
- `AppStore.sync()` must remain user initiated because it can present an App Store authentication prompt.
- Existing uncommitted phases 1–8 changes are user-owned and must be preserved.

