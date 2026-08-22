# Analytics resume cache — specification

## Acceptance criteria

1. General Analytics restores the last successful local chart, totals and breakdown immediately after app relaunch/resume for the same scope.
2. A snapshot never crosses a SwiftData scope boundary and never applies to group/account detail modes.
3. A partial/empty recalculation never overwrites a valid snapshot.
4. Without a snapshot, the screen reports loading local data rather than `No groups` until the first calculation completes.
5. Real empty scopes still show the existing empty state after the initial calculation completes.
6. Financial snapshot bytes use an Application Support file protected with `completeUntilFirstUserAuthentication`.
7. Unit tests cover scope isolation, corrupted data, round-trip restore and state hydration.
