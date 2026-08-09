# Plan: AccountsCore typed save boundary

## Inputs

- Research: `thoughts/research/2026-08-09-accounts-core-save-boundary.md`
- Spec: `specs/2026-08-09-accounts-core-save-boundary.md`

## Decision

- Chosen approach: one concrete typed commit boundary around the SwiftData save side effect, injected only for deterministic failure tests.
- Rejected alternatives: repository-per-entity abstractions; view-local error mapping; global ModelContext extensions with implicit rollback.
- Rollback strategy: revert this additive boundary and restore direct saves; no schema/data migration exists.

## Phases

- [x] Phase 1 — add boundary and failure tests; adopt only in clean-context `AccountsCoreService.updateAccount` and disposable-context `AccountProductFactory`; focused gate and build green.
- [ ] Phase 2 — map typed persistence failure in critical user-facing account mutation use cases; only after Phase 1 is green.
- [ ] Phase 3 — prove one bounded Account source-of-truth cutover slice with parity fixtures; legacy remains intact until exit criteria pass.

## Verification

- Unit tests: `AccountsCoreSaveBoundaryTests`, `AccountsCoreServiceTests`, `AccountProductFactoryTests`, `AccountsCoreUpdateAccountTests`.
- Integration/build checks: relevant simulator tests, `xcodebuild build`, `git diff --check`.
- Acceptance criteria audit: record exact commands/results and update checkboxes after the gate.

## Journal

- 2026-08-09: Research/spec/plan created after tracing three duplicated raw save-error paths. Phase 1 authorized by the session guard phrase.
- 2026-08-09: Independent review rejected broad service adoption: existing shared-context rollback can discard unrelated pending edits. Phase 1 narrowed to proven ownership boundaries.
- 2026-08-09: Phase 1 complete. Focused four-suite test gate succeeded; release simulator build succeeded; direct boundary, factory resurrection, and update rollback/revision tests are green. Item 4 remains blocked by the existing observation/rollback-window criteria, so phases 2/3 and item 6 were not started.
- 2026-08-09: A final rerun after concurrent real-estate files appeared could not reach tests: unrelated `RealEstatePresentation.swift:28` fails to compile (`Optional.flatMap` generic `U` not inferred). The earlier focused gate/build was green before that concurrent change. The new direct boundary test is therefore present but not executed in the final workspace state; no unrelated fix was attempted.
