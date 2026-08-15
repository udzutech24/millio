# Invalid historical manifest cleanup research

Device evidence shows `manifestSemanticallyInvalid`, `close_repository_failed` and repeatedly incomplete backfill. `HistoricalValuationRepository.resolveWinner` quarantines an unreadable row but leaves it physically present; a later `publish` sees the existing logical key and fails on the same row, so ordinary retry cannot heal the cache.

## Alternatives

1. Delete the entire historical table. Rejected: unnecessarily discards valid immutable closes and increases offline/network rebuild cost.
2. Ignore persisted closes and use live totals. Rejected: hides corruption and breaks chart/hero lineage.
3. Validate rows in the active scope with the canonical decoder, delete only unreadable derived rows, enqueue a full rebuild, and force checkpoints. Chosen: smallest repair that removes the publication blocker while preserving source data and valid evidence.

## Risks and mitigations

- Concurrent publication: use the repository publication critical section for cleanup.
- Interrupted rebuild: durable marker remains until all forced checkpoints complete.
- Cross-user deletion: predicate is restricted to the active scope and covered by tests.
- Offline/missing market evidence: invalid rows stay removed, marker remains pending, and future activation retries.
