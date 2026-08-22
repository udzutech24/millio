# First-frame startup

## Evidence

`initializeColdStart` keeps the root route in `.launching` until `synchronizeDataScope` invokes its callback. That callback performed synchronous legacy-to-core migration before `AppLifecycleUseCase.initialize()` could set `.ready`. In addition, a cached authenticated session used the default 2.2-second launch-splash duration.

The previous ordering prevented a temporary core total of zero, but it made a potentially expensive local migration a hard dependency of the first interactive frame. That trade-off is wrong for offline resilience.

## Chosen approach

1. A cached authenticated session receives no artificial splash delay.
2. The historical-readiness gate starts before the app reaches `.ready`, so incomplete core data cannot be published as final balances.
3. The migration itself yields until after the first frame and runs once the scope reconciliation completes.
4. A successful deferred migration recreates the scoped root tree so Finance view models calculate from the migrated core store.

## Rejected approach

Increasing network or splash timeouts only hides the failure. Removing readiness would reintroduce the known transient zero-total bug.
