# Research: Phase 9 — reliable data and subscription recovery

- Date: 2026-08-22
- Scope: Millio iOS cold start, authenticated data-scope binding, CloudKit snapshot backup/restore, post-restore refresh, auto-backup scheduling, StoreKit entitlement recovery, and privacy-safe scope diagnostics.

## Reproduction and evidence

1. The scoped SwiftData configuration in `millioApp.makeModelContainer` explicitly uses `cloudKitDatabase: .none`. CloudKit is therefore a backup transport, not live model synchronization.
2. `AppLifecycleUseCase.initialize()` sends a clean install to `.onboarding` because `hasCompletedOnboarding` is stored only in `UserDefaults`.
3. `LaunchRecoveryPolicy.evaluate()` rejects recovery when onboarding is incomplete and also requires lifecycle `.ready`. `synchronizeDataScope()` calls `presentRestoreFlowIfNeeded()` after binding the authenticated scope, but a clean install is still `.onboarding`; the recovery branch is unreachable even when CloudKit contains a backup.
4. `BackupManager.restoreVersion()` downloads, decodes, clears, imports, and rolls back on import failure. It emits only coarse `restoreStarted/restoreCompleted/restoreFailed` events and returns no receipt. It does not verify imported counts against backup metadata after import.
5. `RestoreView` times out only backup discovery (8 seconds). The actual restore call has no end-to-end deadline, cancellation UI, stage state, or retry state. `BackupManagementView.restoreSelectedVersion()` has the same unbounded call and shows success based only on no thrown error.
6. Auto-backup is triggered only by `UIApplication.willResignActiveNotification`. Code uses a six-hour interval while README promises 24 hours. A foreground editing session can therefore remain unprotected until the app backgrounds, and freshness depends on lifecycle timing rather than committed changes.
7. `BackupEvent.restoreCompleted` is consumed by Finance, Finance Dynamics, and Cashflow view models, but the contract is a fire-and-forget notification. There is no central acknowledgement that Dashboard, Accounts, Analytics, and Cashflow have all reloaded against the active scope.
8. Subscription cold-start refresh reads `Transaction.currentEntitlements`. `AppStore.sync()` exists only behind the manual restore action. This is correct as a safety boundary: Apple says `sync()` can show an authentication prompt and must be called only after explicit user action. A clean install should first use current entitlements, then expose a clear user-triggered recovery action if no entitlement is found.
9. `StartupCoordinator` coalesces/cancels scope switches and `millioApp` rebuilds the root tree by incrementing `scopeIdentityToken`. Existing logs contain raw scope configuration names and do not classify requested, coalesced, cancelled, committed, or root-rebuilt transitions, so one expected guest→user transition cannot be distinguished from a loop without potentially identifying scope values.
10. The worktree already contains substantial uncommitted changes from phases 1–8. Phase 9 must avoid drive-by edits and preserve those changes.

## Current architecture and constraints

- Restore is snapshot-replace, not merge. A pre-restore temporary snapshot provides rollback if import throws.
- `BackupManager` is an actor and is the existing serialization boundary for backup operations, but UI and launch code separately own orchestration policy.
- `DataRepository` backup metadata already contains `modelCount`; export can provide an independent post-import count without reading model contents.
- Backup encryption may be device-key or passphrase based. A keychain backup from another installation may be unavailable; recovery must surface this as an actionable state, not silently skip forever.
- Recovery must target the authenticated user scope. Restoring into the initial guest scope before login risks cross-scope data placement.
- No phone deletion, reinstall, install, CloudKit mutation, or backup-content inspection is authorized in the planning stage.

## Options considered

1. Patch onboarding and both restore views separately. Rejected: duplicates timeouts/state/error mapping, keeps launch and manual restore behavior divergent, and cannot provide one verified receipt.
2. Enable SwiftData CloudKit synchronization. Rejected for Phase 9: changes the persistence/conflict model, migrations, entitlements, schema deployment, and rollback semantics. It does not repair the existing backup UX and is far beyond the proven defect.
3. Add one `RecoveryCoordinator` above `BackupManager`, with typed stages, deadlines, cancellation, retry, verification receipt, and one completion broadcast. Recommended: it preserves snapshot backup architecture while unifying launch and manual flows.

## Recommended option

Keep `BackupManager` responsible for transport/decode/replace/rollback, and add an app-layer recovery coordinator responsible for the user-visible workflow. Extend the restore result to a non-sensitive receipt containing backup metadata count, local count before restore, local count after import/self-heal, selected version identity reduced to safe metadata, duration, and outcome. Successful completion requires count verification, not merely an error-free import.

Route clean-install recovery after successful authenticated scope binding and before onboarding content. Recovery discovery may run while onboarding is nominally incomplete; onboarding completion is no longer a prerequisite. The user must explicitly confirm snapshot replacement, may cancel discovery/download/validation before destructive import, and may retry after bounded errors. Once destructive import begins, UI cancellation must become unavailable unless repository cancellation is proven atomic; pretending it is cancellable would be unsafe.

Use mutation events already emitted by finance/cashflow as the first dirty signal for a debounced auto-backup scheduler, plus a foreground/background fallback. Coalesce changes, serialize with restore/reconciliation, skip empty or uncertain stores, and retain a maximum-staleness fallback. Align code and UI/documentation on one freshness contract; recommended contract is change-driven debounce plus background flush, not a misleading fixed “every N hours” promise.

For StoreKit, do not call `AppStore.sync()` automatically. Run bounded `currentEntitlements` verification at startup; if the user expected PRO but none is found, show a clear “Restore purchases” action that invokes `sync()` explicitly and reports checking/success/no active subscription/cancelled/offline states.

## Risks and mitigations

| Failure mode | Impact | Mitigation |
|---|---:|---|
| Restore targets guest/old scope during auth transition | Critical | Bind coordinator to immutable scope generation; abort before import if generation changes. |
| Timeout returns while underlying destructive import continues | Critical | Deadline/cancellation must be enforced inside the coordinator/manager task boundary; do not merely race a UI timer. Shield the atomic replace section and report `finishingImport` until it settles. |
| Post-import count differs after migrations/dedup | High | Define verification policy per receipt: exact total count before self-heal where stable, then allowed typed deltas for documented migrations; otherwise fail and roll back. Phase 1 fixtures must prove the policy. |
| Auto-backup captures partial mutation or runs beside restore | High | Debounce after committed domain events, single-flight actor, restore/reconciliation lock, and non-empty verified export. |
| Old backup overwrites newer local data | High | Never auto-replace a non-empty store; show backup date/count and explicit destructive confirmation. |
| Passphrase/keychain unavailable | High | Typed actionable error; allow passphrase retry or alternate version; never label it corruption without evidence. |
| Scope logging leaks identifiers | Medium | Log opaque per-process tokens/hashes, transition reason, generation, and state only; no user ID, email, store filename, model data, or record name. |
| `AppStore.sync()` prompts unexpectedly | Medium | Invoke only from explicit button per Apple guidance. |
| Root refresh loop causes Accounts jank | Medium | Instrument request/commit/root-rebuild separately; assert one normal cold-start transition and detect repeated generation changes in a bounded window. |

## Relevant files and tests

- `millio/millioApp.swift`
- `millio/Core/Backup/BackupManager.swift`
- `millio/Core/Backup/LaunchRecoveryPolicy.swift`
- `millio/Core/Backup/AutoBackupPolicy.swift`
- `millio/Core/Repository/DataRepository.swift`
- `millio/Core/AppState/StartupCoordinator.swift`
- `millio/Core/AppState/AppRefreshCoordinator.swift`
- `millio/Core/Subscription/SubscriptionManager.swift`
- `millio/UI/Restore/RestoreView.swift`
- `millio/UI/Profile/BackupManagementView.swift`
- `millio/UI/Dashboard/DashboardView.swift`
- Finance, Finance Dynamics, and Cashflow view models
- Existing backup, launch recovery, refresh, subscription, and scope-swap tests under `millioTests/`

