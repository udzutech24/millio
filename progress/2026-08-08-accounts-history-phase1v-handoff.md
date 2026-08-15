# Accounts history source of truth — handoff

## Completed

- Phase 0 contract reconciliation and baseline audit.
- Exact `99 633 041 ₽ → 77 125 067 ₽` characterization with `22 507 974 ₽` missing.
- Same-day snapshot defect characterized and fixed by direct replay on the checkpoint day.
- Pure structured valuation result and frozen timezone primitives added.
- Phase 2V unified FX/market resolver and the production structured aggregate boundary completed.

## Verified

- Phase 0 focused suites: 44/44, `/tmp/millio-accounts-history-phase0-pass.xcresult`.
- Phase 1V final focused gate: 38/38, `/tmp/millio-phase1v-editor-final2.xcresult`.
- Phase 2V fresh focused gate: 98/98, `/tmp/millio-phase2v-final-20260808.xcresult`;
  independent review verdict: **ACCEPT** after all findings were resolved.

## Current gate

Phase 1V and Phase 2V are complete. Phase 2V exit scope is the new structured aggregate/resolver:
it contains no external fallback chooser and never consumes the legacy bare total. The bare
`AccountsTotalsService.totalAt` API remains quarantined and unsafe, solely as a transition/rollback
API for old consumers. Phase 4 must cut those consumers over; Phase 6 deletes the bare path only
after the rollback window.

The next valuation phase is **Phase 3V — Minimal V7 close repository**, because product identity
occupies V6. Do not start its V6→V7 migration work until the Phase 1P schema-safety gate completes.
Phase 1P remains `in_progress`, not complete.

## Dirty-worktree safety

Pre-existing user changes listed in the Phase 0 journal were not reverted. Files changed by this
execution are limited to the authorized accounts-history implementation and the accounts-history
spec/plan/status/handoff. Older user plans were not edited.
