# Invalid historical manifest cleanup specification

## Acceptance criteria

- Cleanup examines only `HistoricalPortfolioValuation` rows belonging to the active scope.
- A row is deleted only when the canonical `decodedResult` validation fails.
- Valid rows, valid quarantined duplicates, other scopes, accounts and events are unchanged.
- Cleanup is idempotent and persists deletions atomically.
- Deleting one or more rows enqueues a full-scope rebuild marker before backfill starts.
- Rebuild force-replays old completed checkpoints and acknowledges the marker only after all planned closes complete.
- Failure or cancellation leaves the marker pending for a later activation.
