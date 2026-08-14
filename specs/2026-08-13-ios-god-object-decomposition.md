# Spec: Bulletproof decomposition of large iOS files

## Goal

Reduce real reasons to change `FinanceDynamicsViewModel` and `CashflowTransactionEditorView` while preserving financial, historical, recurrence and navigation behavior.

## Acceptance criteria

- [ ] AC1: characterization tests freeze behavior before each extraction.
- [ ] AC2: every extracted calculation/policy component is independently unit-tested without SwiftUI or SwiftData.
- [ ] AC3: view models/views orchestrate typed inputs and outputs instead of calculating domain results.
- [ ] AC4: protocols exist only for actual side-effect boundaries such as SwiftData loading/persistence.
- [ ] AC5: extracted SwiftUI sections accept narrow typed inputs/callbacks, not the parent view model or an uncontrolled collection of bindings.
- [ ] AC6: failed Cashflow persistence produces no haptic, callback, dismiss or navigation.
- [ ] AC7: legacy/core reconciliation is not moved or removed until Item 4 parity, observation and rollback exit criteria pass.
- [ ] AC8: focused tests, relevant full simulator gate, build and `git diff --check` pass after every completed phase.

## Non-goals

- No mechanical file splitting or arbitrary line-count target.
- No legacy-model deletion inside decomposition work.
- No simultaneous FinanceDynamics and Cashflow behavioral refactors.
- No redesign of UI copy or layout unless separately specified.
