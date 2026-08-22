# Analytics resume cache — research (2026-08-21)

## Evidence

On a physical device, locking and reopening the phone repeatedly renders Analytics as `0 ₽`, an empty chart and `No groups`, then the same screen fills with existing local data seconds later. The persisted SwiftData user store is not empty; this is a startup publication race, not data loss or unavailable FX.

`FinanceDynamicsViewModel` begins asynchronous chart, balance and breakdown work after its synchronous store fetch. The view renders the empty state while those outputs are absent. The UI has no distinction between “initial local projection is pending” and “the scope genuinely has no groups.”

## Decision

Persist the last complete, unscoped Analytics presentation as a protected local file keyed by the SwiftData scope. Restore it synchronously when a general Analytics VM is created, then replace it only after a complete current projection succeeds.

## Rejected alternatives

- `UserDefaults`: wrong storage for financial amounts; it offers no file protection contract.
- A global snapshot: can expose one user's values in another user's scope.
- Reusing the aggregate snapshot for a single group/account: semantically wrong.
- Showing `No groups` while loading: demonstrably false and misleading.
