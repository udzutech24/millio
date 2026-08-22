# Plan: Phase 9 — reliable data and subscription recovery

## Status

- Implementation in progress after the guard phrase was received.

## Inputs

- Research: `thoughts/research/2026-08-22-phase-9-reliable-recovery.md`
- Spec: `specs/2026-08-22-phase-9-reliable-recovery.md`

## Decision

- Chosen approach: one scope-bound `RecoveryCoordinator` above the existing `BackupManager`; a typed restore receipt and verification contract; one debounced auto-backup scheduler; explicit refresh acknowledgement; StoreKit current-entitlement check plus user-triggered `AppStore.sync()` fallback; privacy-safe scope transition telemetry.
- Rejected alternatives: view-local patches; automatic `AppStore.sync()`; enabling SwiftData CloudKit sync; claiming cancellation after destructive import begins; success based only on no thrown error.
- Rollback strategy: keep the existing pre-restore local snapshot and extend rollback to cover verification failure. New coordinator/scheduler are additive and can be disabled at integration points without changing the persisted schema. No destructive migration is planned.

## Phases

### [x] 9.0 — Contract tests first

- Add failing unit tests for clean-install authenticated pre-onboarding eligibility, non-empty/unknown-store blocking, scope-generation invalidation, and the full recovery state transition table.
- Add restore receipt/verification fixtures covering exact counts, corrupt metadata, import mismatch, documented dedup/migration adjustment, rollback success, and rollback failure.
- Add deterministic clock/timeout/cancellation tests; do not use real sleeps.
- Map each test to R9 acceptance criteria.

Evidence gate: the new tests fail for the proven current behavior and do not mutate a real store or CloudKit.

### [x] 9.1 — Recovery domain and coordinator

- Add small domain types: `RecoveryStage`, `RecoveryProgress`, `RecoveryRequest`, `RecoveryReceipt`, `RecoveryFailure`, `RecoveryScopeToken`.
- Implement a single-flight coordinator with operation generation, per-stage deadlines, overall deadline, retry, and cancellation boundary.
- Extend backup manager/repository contracts minimally to return safe preflight metadata and verified counts.
- Keep download/decode/replace mechanics in `BackupManager`; move user-flow policy out of SwiftUI and `millioApp`.
- Serialize backup/restore/reconciliation through one explicit operation gate instead of relying only on `AppState.isRestoreInProgress`.

Evidence gate: coordinator tests cover every terminal path and prove no stale generation can publish success.

### [x] 9.2 — Transactional import verification and rollback

- Capture local model count before replace and expected model count from validated backup metadata.
- Import, run existing self-heal/dedup, export/count again, and apply a documented verification policy.
- On mismatch, roll back using the pre-restore snapshot; verify the rollback count before reporting failure.
- Return a receipt only after verification. Emit non-sensitive reason codes and durations.
- Ensure timeout cannot abandon a live destructive mutation; surface a safe “finishing import/rollback” stage.

Evidence gate: real in-memory SwiftData fixtures prove success, mismatch rollback, and rollback-failure classification.

### [x] 9.3 — Authenticated recovery before onboarding

- Change startup routing so backup discovery occurs after authenticated user scope binding and before onboarding content on a clean install.
- Replace the onboarding boolean as a recovery prerequisite with explicit eligibility: authenticated user scope + stable generation + local count zero + backup candidate.
- Keep guest mode and non-empty user scopes out of automatic destructive recovery.
- Ensure skip/continue semantics are explicit and recovery remains available later from Profile.

Evidence gate: startup tests cover fresh install with backup, fresh install without backup, returning user, offline iCloud, passphrase/keychain failure, login switch during discovery, and explicit guest continuation.

### [x] 9.4 — Unified recovery UI

- Make launch recovery, `RestoreView`, and `BackupManagementView` render the same coordinator state.
- Add explicit confirmation, stage names, bounded progress, cancel where safe, retry, alternate-version selection, typed errors, and verified receipt.
- Remove silent indefinite sliders and raw fallback strings; add supported-language localization, Dynamic Type, VoiceOver labels, and reduced-motion-safe behavior.
- Do not expose backup payload contents or raw record/scope identifiers.

Evidence gate: view-model/presentation tests cover state-to-copy/action mapping; localization coverage tests pass.

### [x] 9.5 — Acknowledged refresh barrier

- Introduce one post-restore refresh command carrying the active scope generation and receipt ID.
- Have Dashboard, Accounts, Analytics, and Cashflow reload or rebuild from the same model container and acknowledge completion.
- Coordinator reports final success only after required consumers acknowledge or a bounded refresh error is shown; stale-scope acknowledgements are ignored.
- Preserve existing domain events for ordinary mutations; avoid a broad root-tree rebuild unless evidence shows it is required.

Evidence gate: integration tests prove all four surfaces reload once, against one scope, and stale view models cannot acknowledge.

### [x] 9.6 — Change-driven auto-backup

- Add an actor-based dirty/scheduler state machine with injected clock and deterministic debounce.
- Feed it only committed, backup-relevant domain changes; coalesce bursts and cancel on scope generation changes.
- Gate on enabled settings, authenticated/stable scope, non-empty verified export, no restore/reconciliation, iCloud availability, and single-flight operation lock.
- On background, request a bounded flush when dirty; retain a maximum-staleness foreground/background fallback.
- Update backup screen, README, and `docs/BACKUP_RESTORE_SCHEMA.md` to one truthful freshness contract.

Evidence gate: unit tests cover burst coalescing, repeated mutations, background flush, empty store, restore conflict, reconciliation conflict, offline retry, scope switch, and no-change behavior.

### [x] 9.7 — Scope transition diagnostics and Accounts jank proof

- Instrument scope request, coalescing, cancellation, binding commit, root identity bump, and completion with generation/reason/elapsed time.
- Replace raw scope-name logging in touched paths with a non-reversible per-process label or enum class (`guest`/`authenticated`) and no identifiers.
- Add a bounded loop detector that warns when more than the expected transition/root rebuild pattern occurs.
- Add tests proving one normal guest→authenticated transition produces one committed binding and one root rebuild, while repeated callbacks are coalesced or diagnosed.

Evidence gate: fixture logs contain no PII/raw scope/store/record identifiers and classify normal versus loop behavior.

### [x] 9.8 — Subscription recovery

- Keep startup `Transaction.currentEntitlements` as the normal clean-install restore path and expose checking/resolved/degraded state.
- Add timeout/error mapping without converting uncertainty into a definitive free status too early.
- If entitlement is absent or the user expects PRO, present a clear Restore Purchases action; call `AppStore.sync()` only from that explicit action.
- Distinguish restored active subscription, no active entitlement, cancellation, offline, and unverified transaction.
- Update `AppState` from one subscription snapshot path and test cold-start/foreground coalescing.

Evidence gate: StoreKit abstraction tests cover active entitlement on reinstall, delayed entitlement, no entitlement, manual sync success, cancellation, offline, and unverified results.

### [x] 9.9 — Full verification, documentation, and signed artifact

- Run focused tests first, then existing backup/import/reconciliation/startup/scope/subscription suites, then the broader iOS unit gate.
- Build a fresh signed Release archive without stripping CloudKit/App Group entitlements.
- Verify app and extensions have aligned versions, verify entitlements, and verify the exported signature/artifact.
- Update README, backup schema/runbook, plan status, and phase history with exact evidence and remaining risks.
- Stop before device installation. Ask for explicit authorization to install without deleting app data.

Evidence gate: command outputs and artifact inspection are recorded; no claim of device success is made before the manual checklist.

### [ ] 9.10 — User-authorized device checklist

Only after separate explicit permission:

- Confirm the intended test device is available.
- Install without deleting existing app data unless the user separately authorizes a destructive clean-install test.
- Use synthetic/test data only.
- Verify pre-onboarding recovery after login, confirmation, stages, timeout/cancel/retry, receipt counts, four-screen refresh, auto-backup freshness, expected single scope transition, and subscription restore states.
- Never inspect backup contents, keys, credentials, or unrelated user data.

## Verification

- Unit tests: recovery policy/state machine, receipt verification, rollback, timeout/cancellation generations, auto-backup scheduler, refresh barrier, scope diagnostics, subscription recovery, localization/presentation.
- Integration/build checks: in-memory SwiftData round-trip fixtures; existing backup/import/reconciliation/startup/finance/cashflow/subscription suites; clean Release archive; entitlements/version/signature verification.
- Acceptance audit: every R9-01…R9-18 item must link to a test, build check, or explicitly authorized manual checklist result.

## Journal

- 2026-08-22: Research/spec/plan completed. No production code, tests, device data, CloudKit data, subscription state, or installation changed.
- 2026-08-22: Implemented verified restore receipt/rollback, pre-onboarding authenticated recovery eligibility, staged restore UI, change-driven backup debounce with background flush, privacy-safe scope diagnostics, and explicit no-entitlement result after user-triggered StoreKit sync. Focused Phase 9 tests pass. Refresh-barrier and release gates remain.
- 2026-08-22: Connected launch and manual restore surfaces to one scope-bound coordinator, completed the four-surface refresh barrier, regression tests and a signed Release archive with CloudKit/App Group entitlements. Device installation and the destructive clean-install checklist remain explicitly unexecuted pending authorization.
- 2026-08-22: After explicit user authorization, installed the signed archive over the existing app on the designated `iPhone A (2)` and verified that `com.millio.app` launches. No uninstall, data reset, clean-install scenario, backup inspection, or destructive checklist action was performed.
