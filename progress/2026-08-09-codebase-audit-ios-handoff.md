# Handoff: iOS codebase audit items 5 → 4 → 6 → 10

## Completed in this session

- Item 5 Phase 1: added a typed AccountsCore save boundary.
- Adopted only at proven ownership boundaries:
  - `AccountsCoreService.updateAccount` after its clean-context precondition;
  - `AccountProductFactory` in its disposable transaction context.
- Added direct and integration failure tests proving typed operation classification, rollback of fields/revisions, and no resurrection after a later save.
- Independent final review found no blocking data-loss/rollback defect in these two adopted paths.

## Verification

- Focused simulator gate on iPhone 17 / iOS 26.5: `AccountProductFactoryTests`, `AccountsCoreUpdateAccountTests`, `AccountsCoreServiceTests`, `LegacyAccountConverterTests` — `TEST SUCCEEDED`.
- Release simulator build with signing disabled — `BUILD SUCCEEDED`.
- `git diff --check` — passed.

Final rerun caveat: after new unrelated `RealEstate/` files appeared during the session, compilation stopped at `RealEstatePresentation.swift:28` (`Optional.flatMap`: generic `U` could not be inferred). This is outside the audit-owned diff and was deliberately not changed. The direct boundary test added after review has not executed in that final red workspace state.

## Why autonomous progression stopped here

Item 4 is not green: the existing accounts-history status has Phase 0 reopened, Phase 5 observation/offline/rollback/publication criteria open, and Phase 6 blocked by the rollback window. Live legacy writers/fetches also remain. Deleting legacy or declaring `Account` the sole source now would be dishonest and could lose history or break identity links.

Because the user required item 6 to start only after save-boundary and source-of-truth stabilization, no FinanceDynamics production refactor was started. Read-only design recommends the first future phase as a pure `FinanceDynamicsSamplingEngine` with explicit `Calendar` and characterization tests. Item 10 remains intentionally untouched.

## Exact next step

Implement Item 5 Phase 2: map `AccountsCorePersistenceError` to sanitized actionable UI state in the account edit/create use cases and prove failed persistence causes no dismiss, success event, haptic, or navigation. Separately close the documented Item 4 operational gates before any reader/legacy removal. Then create Item 6 research/spec/plan and extract only the sampling engine.

## Item 6 decomposition plan added on 2026-08-13

The implementation-ready phase order is now recorded in `plans/2026-08-13__ios-god-object-decomposition.md`:

1. FinanceDynamics characterization.
2. Pure `FinanceDynamicsSamplingEngine`.
3. Typed data loader with explicit read-error semantics.
4. Pure series/breakdown builders.
5. Legacy reconciler only when Item 4 gates permit it.
6. Cashflow editor characterization.
7. Typed form state and `CashflowTransactionDraftFactory`.
8. Typed save use case.
9. Narrow SwiftUI sections only after their contracts are small.

Mechanical extension/file splitting is explicitly rejected. The plan is documentation-only; implementation has not started.

## Preserved unrelated work

The repository was already dirty with real-estate, Sheets-disable, localization, schema, and finance changes; additional such files appeared while the gate ran. They were not reverted, attributed to this phase, or intentionally modified except for narrow overlapping hunks in `AccountsCoreService.swift` and its existing update tests.
