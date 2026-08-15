# Plan: Bulletproof decomposition of large iOS files

## Inputs

- Research: `thoughts/research/2026-08-13-ios-god-object-decomposition.md`
- Spec: `specs/2026-08-13-ios-god-object-decomposition.md`
- Audit: `thoughts/research/2026-08-09-codebase-top-10-audit.md`, Item 6.

## Entry gates

- Item 5 user-facing save/error boundary is green for mutation paths touched by the phase.
- Item 4 source-of-truth milestone required by the extracted code is green; legacy removal remains forbidden until all exit criteria pass.
- Current workspace builds and a fresh dirty-worktree ownership baseline is recorded.
- Only one behavioral extraction phase is active at a time.

## Architecture decision

- Keep one orchestration view model/view per screen.
- Extract pure calculations and policies first.
- Extract data loaders and mutation use cases only at real side-effect boundaries.
- Extract visual sections last, once they have narrow typed contracts.
- A phase is complete only if the original object loses a real reason to change and the new boundary has independent tests.

## Phase FD-0 — FinanceDynamics characterization

- [ ] Freeze exact start/end points, intermediate sampling density and per-calendar-day deduplication through existing public behavior.
- [ ] Cover month, year, `.all`, zero/one-day ranges, duplicate same-day events, unsorted points and fixed-timezone DST transitions.
- [ ] Record current relevant simulator baseline and known locale/order/parallel flakes separately.

## Phase FD-1 — pure `FinanceDynamicsSamplingEngine`

- [ ] Add a pure type with explicit `Calendar` for step selection, skeleton dates, intermediate dates and calendar-day deduplication.
- [ ] Preserve exact endpoints and the current last-value-per-middle-day contract.
- [ ] Wire the view model as orchestrator; it still owns balance/FX requests, but no longer owns sampling policy.
- [ ] Add independent threshold tests: `30/31/365/366` and `.all` `365/366/730/731`, reverse/zero ranges and DST.
- [ ] Do not introduce a protocol: the engine has no side effect.

## Phase FD-2 — typed `FinanceDynamicsDataLoader`

- [ ] First define read-failure semantics; do not preserve `try?`/empty-array ambiguity accidentally.
- [ ] Move SwiftData fetch ownership behind one loader boundary with a protocol because storage is a real side effect.
- [ ] Keep legacy/core reconciliation and valuation policy outside the loader.
- [ ] Prove loading errors do not masquerade as a legitimate empty portfolio.

## Phase FD-3 — pure series and breakdown builders

- [ ] Extract `FinanceDynamicsSeriesBuilder` only after input fixtures can represent resolved balances/rates without SwiftData.
- [ ] Extract `FinanceDynamicsBreakdownBuilder` for account/group rows and totals.
- [ ] Prove no double counting, stable identity, archive/history scope and localization-neutral numeric output.

## Phase FD-4 — temporary legacy anti-corruption boundary

- [ ] Start only when Item 4 permits changes to compatibility behavior.
- [ ] Encapsulate predecessor/shadow/reconciliation rules in a clearly temporary `FinanceDynamicsLegacyReconciler`.
- [ ] Preserve rollback and parity fixtures; delete the reconciler only when legacy exit criteria are demonstrated.

## Phase CF-0 — Cashflow editor characterization

- [ ] Begin only after all FinanceDynamics phases selected for the milestone are green and current concurrent Cashflow changes have a clean ownership baseline.
- [ ] Freeze invalid/non-positive amount behavior, category/account defaults, recurrence weekdays and series identity.
- [ ] Freeze same/cross-currency transfer metadata and failure behavior: no success side effects after persistence failure.

## Phase CF-1 — `CashflowEditorFormState` and pure draft factory

- [ ] Consolidate editor input into a typed form state without moving persistence into it.
- [ ] Extract `CashflowTransactionDraftFactory` that returns a validated immutable command/value.
- [ ] Move note normalization, recurrence defaults/weekdays/series identity and frozen FX metadata into independently tested policies only where separate responsibility is proven.
- [ ] Reuse existing persistence service; do not add another repository.

## Phase CF-2 — typed save use case

- [ ] Add `CashflowTransactionSaveUseCase` to coordinate draft factory and existing persistence boundary.
- [ ] Return typed validation/persistence outcomes.
- [ ] Prove failed save triggers no haptic, callback, dismiss or navigation; success triggers each exactly once.

## Phase CF-3 — narrow SwiftUI sections

- [ ] Extract only stable sections such as amount, account, category, transfer, recurrence, note and save bar.
- [ ] Each section receives a small typed model plus minimal callbacks.
- [ ] Reject any proposed component that needs the parent view model or roughly 10+ independent bindings; shrink the contract first.
- [ ] Preserve accessibility, focus, keyboard, localization and navigation behavior with focused tests/snapshots where appropriate.

## Verification per phase

- Focused unit and characterization tests for the extracted boundary.
- Full `FinanceDynamicsViewModelTests`/series invariant suites for FD phases.
- Full relevant Cashflow editor/persistence/navigation suites for CF phases.
- Simulator build and relevant full simulator test gate; compare failures with documented baseline and rerun suspected locale/order/parallel flakes in isolation.
- `git diff --check` and final review for data loss, double counting, identity mismatch, archive/history, rollback, FX, recurrence, localization and unrelated dirty changes.

## Status

- Planning complete; implementation not started.
- Exact next decomposition step after entry gates: FD-0 characterization, then FD-1 `FinanceDynamicsSamplingEngine`.
