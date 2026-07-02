# Finance Daily Snapshot Contract

Daily snapshots are the immutable accounting history for finance charts.

## Rules

1. A closed day is any day before today.
2. Snapshot state is represented only by `snapshotState`:
   - `open`: current day, mutable
   - `pendingFx`: day balance is closed, FX is not final yet
   - `closed`: balance and FX are frozen
   - `fallbackClosed`: balance is frozen with a fallback FX rate
3. `closed` and `fallbackClosed` snapshots must not be changed by user actions:
   deleting transactions, archiving accounts, changing current FX rates, or editing today's data.
4. `pendingFx` may update only FX fields:
   `fxRateToBase`, `balanceInBaseCurrency`, `rateProvider`, `rateTimestamp`, `snapshotState`, `closedAt`, `updatedAt`.
   It must not update `accountBalance`, `accountCurrency`, `dateKey`, or `accountID`.
5. Archive is not delete. Archived accounts remain part of historical charts.
6. `AccountBalanceHistoryStore.cleanup(keepingIDs:)` is forbidden for historical data.
7. Charts read days before today from SwiftData snapshots. Today is a live projection.
8. Missing snapshot data inside the known snapshot window is a gap:
   charts and sparklines must not compact `[value, nil, value]` into a fake continuous line.
9. Historical JSON/UserDefaults stores are migration sources only.
10. Replay-based chart data is allowed only as a temporary bootstrap fallback when there are
    not enough snapshots to draw a series. Once a snapshot series exists, gaps in that series
    must be surfaced instead of hidden by replay.
11. Initial historical backfill is supported only for card accounts, because cards have
    a reliable `initialBalance` plus ledger deltas. Non-card accounts may be closed from
    yesterday forward unless a dedicated historical model exists for that account type.
