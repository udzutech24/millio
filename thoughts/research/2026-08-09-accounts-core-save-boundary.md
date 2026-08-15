# Research: AccountsCore typed save boundary

- Date: 2026-08-09
- Scope: iOS AccountsCore interactive mutations needed by the account-model cutover.
- Reproduction/evidence:
  - `AccountsCoreService.saveOrRollback()` rolls back correctly but rethrows an arbitrary raw error.
  - `AccountsCoreService.updateAccount` duplicates the same raw save/rollback policy.
  - `AccountProductFactory` owns another save closure and also rethrows raw persistence failures.
  - Callers therefore cannot reliably distinguish a rejected domain command from a failed durable commit.
- Current architecture and constraints:
  - AccountsCore mutations are `@MainActor` and use SwiftData `ModelContext`.
  - Rollback is safe only when the mutation boundary owns the pending context changes; `updateAccount` already enforces a clean-context precondition, while the factory uses a disposable context.
  - Existing dirty changes in `AccountsCoreService.swift` belong to the real-estate vertical slice and must be preserved.
- Options considered:
  1. Add repositories/protocols for every entity: rejected as speculative abstraction and excessive cutover scope.
  2. Map errors separately in every view: rejected because rollback and error taxonomy would diverge.
  3. One small typed commit boundary with an injectable save operation: chosen; it centralizes the real side effect and remains testable.
- Recommended option and why: `AccountsCoreSaveBoundary` performs save, rollback, and typed error mapping with an operation tag. Services retain domain orchestration.
- Risks and unknowns:
  - `rollback()` discards all pending changes, so callers must keep exclusive ownership guarantees.
  - Background market-price cache writes are not interactive account mutations and stay outside this first phase.
  - UI presentation of the typed error is a later consumer phase; this phase establishes the safe contract first.
- Relevant files/tests:
  - `millio/Core/AccountsCore/AccountsCoreSaveBoundary.swift`
  - `millio/Core/AccountsCore/AccountsCoreService.swift`
  - `millio/Core/AccountsCore/ProductCatalog/AccountProductFactory.swift`
  - `millioTests/Core/AccountsCore/AccountsCoreSaveBoundaryTests.swift`
