# First-frame startup specification

## Acceptance criteria

- A locally cached authenticated session has zero artificial splash duration.
- The app enters its ready route before legacy migration begins.
- Historical valuation remains non-ready from before the ready route until migration reaches a terminal state.
- Deferred migration runs only for the still-active scope and refreshes the scoped UI after completion.
- Runtime scope swaps retain their existing synchronous migration guard.
- Unauthenticated startup retains the existing splash behavior.
