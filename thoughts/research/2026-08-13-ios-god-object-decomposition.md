# Research: iOS god-object decomposition

- Date: 2026-08-13
- Scope: `FinanceDynamicsViewModel` first, then `CashflowTransactionEditorView`.
- Evidence:
  - `FinanceDynamicsViewModel.swift` mixes SwiftData loading, legacy/core reconciliation, FX, historical valuation, calendar sampling, chart construction, breakdowns and UI orchestration.
  - Calendar sampling and day deduplication are embedded in `historicalDateSkeleton`, `buildTimeSeriesData` and `dedupedByCalendarDay`; the policy cannot be tested without constructing the heavy view model.
  - `CashflowTransactionEditorView.swift` mixes rendering with draft validation, recurrence defaults, transfer FX metadata, persistence coordination and success navigation.
  - Cashflow already has real boundaries (`CashflowPersistenceService`, selectable-account resolver, input formatter), so another generic repository layer would duplicate existing architecture.
- Decision: extract stable capabilities, not arbitrary file fragments. Start with pure engines and command factories; extract UI sections only after their inputs are small and typed.
- Rejected approaches:
  - Moving code into extensions only to reduce line count: same coupling in more files.
  - Passing the whole view model/form state into extracted sections: hidden god-object dependency.
  - Adding protocols to pure calculations: needless abstraction without a side effect.
  - Extracting legacy reconciliation before Item 4 parity/rollback gates: risks changing historical semantics during cutover.
- Risks:
  - Calendar/DST and endpoint behavior can silently change during sampling extraction.
  - Transfer FX and recurring-series identity can be lost during editor extraction.
  - Concurrent Cashflow work is currently dirty; editor implementation must wait for a fresh ownership baseline.
