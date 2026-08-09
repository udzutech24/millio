# Phase 5 preparation — accounts history

Status: emergency structured reader active; operational acceptance remains open.

## Emergency correctness activation — 2026-08-08

- A no-override production reader now defaults to `.structured`, so historical presentation reads
  local FX/market evidence and persisted V7 closes instead of publishing shadow compatibility
  pixels with silent omissions.
- Explicit `.shadow` remains available for evidence collection. Explicit `.compatibility` remains
  the safe structured rollback. Runtime `.structured` overrides still require an accepted gate.
- Expanded simulator gate: 58/58,
  `/tmp/millio-emergency-cutover-expanded.xcresult`.
- This activation does not complete Phase 5. Real-device contribution diagnosis, the observation
  window, physical transitions, UX approval and rollback drill are still mandatory.

## Implemented independently

- Durable rollout checkpoints keyed by scope, frozen `(dayKey, timeZoneID)`, currency, policy and
  optional opaque account ID.
- Resumption skips complete units, retries incomplete units and leaves an interrupted current unit
  not-attempted. State is persisted after every evaluated unit.
- Shadow observations classify structured incompleteness, account-set mismatch, unavailable
  compatibility output, expected resolver correction and unexplained numeric delta.
- Cutover gate is fail-closed: a non-empty window is required; silent drops, account-set mismatch
  and unexplained numeric deltas reject cutover.
- Rollback remains the existing structured compatibility reader. V7 rows and operational
  checkpoints are not deleted or rewritten.

## Phase 4 integration seam

After the Phase 4 bundle contract is frozen, create work keys from its sampled point IDs and opaque
account contribution IDs. The executor must call that same producer, publish only closed complete
results through `HistoricalValuationRepository`, and return `false` for incomplete coverage. It
must not call `AccountsTotalsService.totalAt` or perform a second FX/market lookup.

Shadow wiring must submit, per identical point ID:

1. structured result and expected/resolved counts;
2. compatibility value and contribution count;
3. an explicit resolver-correction classification derived from provenance, never guessed from the
   numeric delta.

No reader switches to `.structured` until `HistoricalPortfolioCutoverGate.isApproved` and UX for
incomplete/fallback points has explicit product approval.

## Device and rollback operations still requiring physical execution

1. Close an Istanbul day, switch the device to Los Angeles, relaunch offline and verify the stored
   Istanbul `(dayKey, timeZoneID)` is unchanged and readable.
2. Repeat across one 23-hour and one 25-hour DST day; reconnect only after the offline read and
   verify a published close does not mutate.
3. Interrupt backfill between two units, terminate/relaunch, verify the completed unit is skipped
   and the current unit resumes.
4. Run shadow observation window; every non-zero delta must have a reason and zero silent drops.
5. Switch `.structured → .compatibility → .structured`; verify both modes remain structured,
   incomplete stays nil (never diagnostic subtotal), and V7/checkpoints remain intact.

These are release operations, not claims established by simulator-only unit tests.
