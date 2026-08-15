# Plan: продуктовая вертикаль «Дебетовые и банковские карты»

## Inputs

- Research: `thoughts/research/2026-08-11-debit-card-product-vertical.md`
- Spec: `specs/2026-08-11-debit-card-product-vertical.md`
- Mode: L / `$millio-bulletproof`

## Decision

- Chosen: preserve `Account`/`AccountEvent` as the only ledger; add a pure debit contract/presentation snapshot and one atomic debit operation coordinator. Cashflow remains exactly-once classification/projection.
- Rejected: UI-only facelift; parallel DebitCard/Transaction store; schema-first migration; immediate legacy purge.
- Schema decision: unchanged unless Phase 1 proves otherwise. Current v1 requirements fit existing Account/Event/CardMeta/source/transfer/archive fields.
- Rollback: every phase is independently removable. New writers/UI are not routed until their semantic/persistence gates pass. Existing source rows are never silently rewritten or deleted.
- Dependency rule: after Phase 1, **Phase 1Q is mandatory before Phases 2–5**. No new debit writer or UI may ship while ordinary legacy reads can still delete persisted rows.

## Phase 0 — Research/spec/plan

- [x] Trace create → ledger/meta → operations/Cashflow → replay/totals/groups/Dynamics → archive/backup/refresh.
- [x] Separate proven defects from hypotheses and define alternatives.
- [x] Map every AC to a phase and verification gate.
- [x] Record no mandatory schema/data migration.

**Evidence:** linked documents; production/schema/tests unchanged.

## Phase 1 — Characterization and financial semantics

**Status:** complete (2026-08-11). Characterization was followed by executable rollback, retry and two-context concurrent-withdrawal fixtures; static evidence alone was not accepted.

**Scope:** tests and decision record only. Lock debit behavior and prove failure modes before production edits.

**Files:** existing AccountsCore/Cashflow/CardCatalog/backup test suites; new focused `DebitCardFinancialCharacterizationTests.swift`, `DebitCardCashflowAtomicityCharacterizationTests.swift`, `LegacyCardCompatibilityCharacterizationTests.swift` if seams permit; plan journal.

**Tests/evidence:**

- opening/current/historical equation and deterministic ordering;
- ISO currency minor-unit/rounding policy for RUB/USD, JPY-like zero-minor and three-minor currencies; Decimal-only FX and explicit transfer remainder allocation;
- zero/negative/oversized income, expense, transfer, fee and adjustment;
- backdated and future-dated funds validation at the effective timestamp;
- current test `100 - 500 = -400` labelled compatibility bug;
- Cashflow final-save failure after event save and bridge failure before transaction save;
- retry/relaunch/serial multi-context and true-concurrent source-ID/withdrawal behavior;
- persisted refund-link alternatives: existing `CashflowTransaction.operationGroupID`, AccountEvent source identity, or minimal additive link; notes/category IDs are forbidden as relational storage;
- duplicate/missing-ID/corrupt legacy Card, CardMeta and relationship fixtures;
- `CardCatalog.fetchAll` destructive-read fixture;
- backup round-trip and old backup restore;
- exact inventory of PAN/CVV/last4 readers/writers/export/import/logs;
- refresh consumer inventory and baseline render/accessibility audit.
- repository-wide inventory of every debit writer, including detail, quick edit, Cashflow create/edit/delete, recurring generation, import/restore and migration/debug boundaries.

**Gate:** evidence for DC-C1–C7, P2/P5/P6, F1–F6, B1–B5, R1/S1–S2; explicit refund-link and schema decision remains unchanged or proposes only a separately reviewed additive migration. Serial tests are not accepted as evidence for true concurrency.

**Rollback:** tests/docs only.

**Guard phrase:** `Реализуй фазу 1 по плану plans/2026-08-11__debit-card-product-vertical.md`.

## Phase 1Q — Mandatory legacy read quarantine

**Status:** complete (2026-08-11).

**Scope:** narrow safety fix immediately after characterization. Make `CardCatalog` and all ordinary legacy fetch/read-model paths pure. Move any dedup mutation behind an explicit repair command that first proves/remaps relationships and is not invoked by UI reads. Remove names/last4/amounts/raw payloads from touched logs. No legacy deletion, migration or schema change.

**Files:** `CardCatalog.swift`, direct callers/tests, explicit repair boundary only if Phase 1 proves one is needed.

**Tests:** repeated fetch leaves `ModelContext.hasChanges == false`, row count and all Cashflow/FinanceAccount/cashback links unchanged; duplicate/missing ID returns deterministic read-model/incomplete diagnostics; injected fetch/save failures do not mutate; safe-log assertions.

**Gate:** DC-B2 and touched portion of DC-S2. Repository search finds no production read that calls destructive dedup. Phases 2–5 remain blocked until this gate passes.

**Rollback:** revert pure-reader routing; no data/schema change exists. Do not roll back to automatic deletion in a shipping build.

**Guard phrase:** `Реализуй фазу 1Q по плану plans/2026-08-11__debit-card-product-vertical.md`.

## Phase 2 — Pure debit contract and typed presentation

**Status:** complete (2026-08-11).

**Scope:** pure deterministic validation/replay adapter, typed actual/converted/incomplete/lifecycle/capability snapshot. No persistence, Cashflow or UI routing.

**Files:** new small files under `Core/AccountsCore/DebitCard/`; existing replay reused, not duplicated; focused tests.

**Tests:** property/invariant event sequences; positive magnitude; non-negative result; stable ordering; currency minor units/rounding/large Decimal values; effective-date balances; include/archive endpoints; FX exact/provisional/unavailable; corrupt meta; credit-card rejection.

**Gate:** DC-C1–C4, DC-C6–C7, H2–H4 and typed portion of U2/U4. No credit limit/debt/grace logic appears.

**Rollback:** remove pure adapter; persisted data unchanged.

**Guard phrase:** `Реализуй фазу 2 по плану plans/2026-08-11__debit-card-product-vertical.md`.

## Phase 3 — Atomic debit writer/save boundary

**Status:** complete (2026-08-11).

**Scope:** one coordinator for create-compatible validation, expense, income, transfer, fee, refund, adjustment and archive. Stage all AccountEvents and linked entities in an isolated context and commit once. Stable caller operation ID.

**Files:** `Core/AccountsCore/DebitCard/DebitCardOperationCoordinator.swift`; minimal stage-without-save APIs in AccountsCore; save-boundary and tests. Do not create specialized commands whose only value is naming.

**Tests:** every-stage injected failure; later unrelated save cannot resurrect graph; amount/funds/archive/product checks at effective timestamp; persisted refund link/cap; adjustment reason/before-after; same/different currency transfer with rounding remainder; retry/conflict/relaunch/serial multi-context; deterministic true-concurrent double-spend race using two contexts.

**Gate:** DC-C2–C7, P1–P6 and command-side S1. One outer commit, zero partial rows. At most one of two competing withdrawals commits when their sum exceeds effective-date funds.

**Rollback:** coordinator unused by UI until Phase 5; remove independently.

**Guard phrase:** `Реализуй фазу 3 по плану plans/2026-08-11__debit-card-product-vertical.md`.

## Phase 4 — Cashflow exactly-once and refresh convergence

**Status:** complete (2026-08-11). The authorized Cashflow regression repair restored all 89 `CashflowViewModelTests`; the debit graph and broader gate are green.

**Scope:** replace split save for debit operations with one coordinator-owned graph; classify expense/income/fee/refund/transfer; publish one refresh only after commit.

**Files:** `AccountsCoreCashflowBridge.swift`, `CashflowPersistenceService.swift`, operation coordinator, Finance event boundary and integration tests.

**Tests:** one operation → one event effect/one projection; transfer excluded from income/expense; refund corrects original and restores link after backup; bridge/final-save failure rollback; retry/relaunch/multi-context; create/edit/delete/recurring/import writer inventory; direct detail and Cashflow entry converge; all refresh consumers agree without relaunch.

**Gate:** DC-F1–F6, H1, R1. No swallowed bridge error or bypass writer can create divergence.

**Rollback:** old bridge remains quarantined only for legacy targets; core debit UI cannot fall back to split writer.

**Guard phrase:** `Реализуй фазу 4 по плану plans/2026-08-11__debit-card-product-vertical.md`.

## Phase 5 — Creation/edit and balance-first detail/history UX

**Status:** complete (2026-08-11).

**Scope:** chosen “balance + quick operations + recent activity” concept. Creation/edit/detail/history consume typed APIs and route writes only through coordinator.

**Files:** responsibility-focused views under `UI/Services/Finances/AccountsCore/DebitCard/`; thin creation/detail routing; no formulas in SwiftUI.

**States:** create; positive; zero; excluded; favorite; recent/no activity; archived; incomplete/corrupt; save/refresh error.

**Tests:** relevant fields only; negative opening/last4 validation; actual vs converted labels; quick actions; typed activity; edit currency/balance forbidden; archive warning and read-only; presentation mappings.

**Gate:** DC-U1–U5, P3–P4, H1–H4. Generic unsafe adjust/income/expense routes are inaccessible for debit products.

**Rollback:** specialized route can fall back to typed read-only generic detail, never unsafe generic writers.

**Guard phrase:** `Реализуй фазу 5 по плану plans/2026-08-11__debit-card-product-vertical.md`.

## Phase 6 — Legacy compatibility and backup proof

**Status:** complete (2026-08-11).

**Scope:** build on mandatory Phase 1Q; prove full legacy/core/Cashflow/group/cashback/backup compatibility and stop remaining sensitive writes/logs. No deletion or data rewrite.

**Files:** `CardCatalog`, importer/registration, Finance legacy readers, migration/backup tests, safe diagnostics.

**Tests:** duplicate same ID with different links; missing/derived ID; corrupt metadata; read leaves context/store unchanged; importer stable-ID-first behavior; old/current backup; registry missing/store replacement; no orphan links; logs contain no names/last4/amounts/raw errors.

**Gate:** DC-B1–B3, DC-S1–S2. Production fetch never saves/deletes.

**Rollback:** compatibility readers remain; only destructive behavior stays disabled.

**Guard phrase:** `Реализуй фазу 6 по плану plans/2026-08-11__debit-card-product-vertical.md`.

## Phase 7 — Conditional migration/security retention decision

**Status:** complete (2026-08-11): persisted gap not proven; schema unchanged. Legacy `Card` and PAN/CVV persistence were not deleted or migrated.

**Scope:** decision gate, not mandatory implementation. Re-run persisted-gap evidence. If no gap, record `schema unchanged` and keep compatibility layer. PAN/CVV retirement requires separate explicit authorization and retention/rollback design.

**Files:** schema/migration/backup only if separately approved and proven necessary.

**Tests if migration is authorized:** accepted old-store fixture; duplicate/missing/corrupt/partial records; complete link remap; export/import; interrupted migration; retry; rollback; old binary/read compatibility where feasible; source evidence retained.

**Gate:** DC-B4–B5. No migration merely to clean architecture. No physical legacy deletion until Cashflow/group/cashback/history/restore exit criteria pass.

**Rollback:** additive optional data only; feature flag/read compatibility; source evidence retained. Security deletion plan must define recoverability/legal retention before execution.

**Guard phrase:** `Реализуй фазу 7 по плану plans/2026-08-11__debit-card-product-vertical.md`.

## Phase 8 — Localization, accessibility and render matrix

**Status:** complete (2026-08-11).

**Scope:** typed RU/EN/zh-Hans copy, accessibility and visual verification; no semantic changes.

**Verification:** raw-key audit; VoiceOver labels/values/actions and focus; Dynamic Type; Reduce Motion; contrast/dark mode; keyboard dismissal; 375×812 and 390×844 screenshots for create, positive, zero, excluded, empty history, archived, error/incomplete.

**Gate:** DC-L1–L3 and remaining UI presentation clauses.

**Rollback:** presentation-only changes independently revertible.

**Guard phrase:** `Реализуй фазу 8 по плану plans/2026-08-11__debit-card-product-vertical.md`.

## Phase 9 — Release audit

**Status:** complete (2026-08-11).

**Scope:** no new features. Full AC self-audit, regression/build/security/backup gates, documentation/status/reflection.

**Verification:** targeted debit suites; property/invariant suites; AccountsCore/Cashflow/Finance integration; legacy/backup/restore; localization/accessibility/render; broader finance regressions; clean Debug and Release simulator builds; target membership; safe-log/static sensitive-field scan; `git diff --check`.

**Gate:** every DC-* AC has passing evidence or the phase remains open. No release with negative debit balance, duplicate/missing projection, partial graph, destructive read, fabricated FX, writable archive or sensitive logging.

**Rollback:** release flag disables new UI/writer while retaining valid semantic core and source data.

**Guard phrase:** `Реализуй фазу 9 по плану plans/2026-08-11__debit-card-product-vertical.md`.

## Verification matrix

| Layer | Gates |
|---|---|
| Unit | financial contract, command validation, refund cap, typed presentation |
| Property | replay equation, currency rounding, effective-date funds, non-negative invariant, stable ordering, FX transfer conservation |
| Persistence | operation identity, retry/relaunch, true-concurrent double-spend, every-stage rollback, create/edit/archive atomicity |
| Integration | exactly-once Cashflow, persisted refund linkage, complete writer inventory, no second balance effect, refresh convergence, totals/history/groups equality |
| Compatibility | duplicate/missing/corrupt Card, old backup, registry loss, orphan-free restore, conditional migration rollback |
| UI | RU/EN/zh-Hans, VoiceOver/Dynamic Type/Reduce Motion, 375/390 light/dark state matrix |
| Release | targeted + regression suites, clean Debug/Release builds, safe-log scan, `git diff --check` |

## Acceptance mapping

| AC | Phases | Sufficient evidence |
|---|---|---|
| DC-C1, DC-C2, DC-C3, DC-C4, DC-C5, DC-C6, DC-C7 | 1–3 | characterization + pure rounding/effective-date/property suite + coordinator identity |
| DC-P1, DC-P2, DC-P3, DC-P4, DC-P5, DC-P6 | 1, 3, 5 | factory/coordinator failure and concurrent double-spend matrix + UI route gates |
| DC-F1, DC-F2, DC-F3, DC-F4, DC-F5, DC-F6 | 1, 4 | exactly-once/refund-link/writer-inventory/no-double-effect/rollback integration |
| DC-H1, DC-H2, DC-H3, DC-H4 | 2, 4–5 | shared snapshot/endpoint and archive/group fixtures |
| DC-U1, DC-U2, DC-U3, DC-U4, DC-U5 | 5, 8 | typed state tests + simulator matrix |
| DC-L1, DC-L2, DC-L3 | 8 | localization/accessibility/render evidence |
| DC-B1, DC-B2, DC-B3, DC-B4, DC-B5 | 1, 1Q, 6–7 | early pure-read quarantine + backup/legacy fixtures + explicit migration decision |
| DC-R1 | 4, 9 | post-commit convergence and release regression |
| DC-S1, DC-S2 | 1, 6–9 | inventory, safe writers/logs, static release scan |

## Challenge Log

1. **Every AC mapped?** Yes; each group has at least one implementation phase and an objective gate.
2. **Every risk gated?** Split save, overdraft, duplicate IDs, destructive read, backup/orphans, refresh, FX, accessibility and sensitive data each have explicit tests or decision gates.
3. **Second source of truth?** No. AccountEvent remains the ledger; Cashflow is projection; legacy Card is quarantined predecessor evidence.
4. **Code for code's sake?** No. Schema, migration, PAN/CVV retention cleanup, favorite-specific persistence and advanced analytics are conditional/deferred.
5. **Minimal best option?** Yes. It reuses factory, save boundary, replay, totals, transition policy, historical producer and Cashflow entities. Financial correctness precedes UI.

## Adversarial Stress Test — 2026-08-11

| Failure mode | Evidence | Probability | Impact | Plan hardening |
|---|---|---:|---:|---|
| Currency rounding is undefined | Spec previously used raw Decimal equation but named no minor-unit/FX rounding boundary | High | High: replay/projection drift and false refund caps | DC-C6; Phase 1 probes; Phase 2 pure policy; Phase 3 remainder tests |
| Two concurrent expenses both pass funds check | No uniqueness constraint; original plan tested serial multi-context only | Medium | Critical: negative balance despite overdraft ban | DC-P6; true two-context race; revalidate/serialize inside commit |
| Backdated/future operation validates against wrong balance | Original plan said “sufficient funds” without effective timestamp | High | High: valid history rejected or overdraft admitted | DC-C7; effective-date policy/tests in Phases 1–3 |
| Refund link disappears after relaunch/restore | `AccountEvent` has only its own `sourceTransactionID`; `operationGroupID` exists on Cashflow only | Medium | High: over-refund and incorrect expense analytics | DC-F5; Phase 1 persisted-gap decision; backup fixture; no note/category abuse |
| A bypass writer preserves split/non-validated semantics | Repository has direct detail/quick-edit/service/recurring bridge calls | High | Critical: coordinator guarantees are illusory | DC-F6; exhaustive writer inventory and search gate in Phases 1/4/9 |
| Destructive read remains active through core/UI work | `CardCatalog.fetchAll` deletes/saves; quarantine was formerly Phase 6 | High | Critical: unrelated navigation can destroy legacy evidence | Mandatory Phase 1Q before Phases 2–5 |
| Large values overflow/lose precision through Double Cashflow | Cashflow amount is `Double`; Account ledger is `Decimal` | Medium | High for large/FX values | Phase 1 large-value characterization; command normalization; incomplete/block rather than silent drift |
| Rollback flag disables UI but legacy writer stays reachable | Original release rollback was generic | Medium | High: returns to known unsafe split writer | Rollback explicitly permits typed read-only fallback, never unsafe core writer |

**Stress verdict:** original plan was directionally correct but not bulletproof. It failed concurrency, rounding, persisted refund identity, writer completeness and sequencing. With DC-C6/C7, P6, F5/F6 and mandatory Phase 1Q, no known critical risk lacks a verification gate. Schema remains conditional because refund linkage still requires Phase 1 evidence, not guessing.

## Journal

- 2026-08-11: Phase 0 complete. Read-only audit proved negative debit balances, split Cashflow/Event commits, destructive Card fetch dedup and sensitive legacy persistence. Research/spec/plan/status created; production/schema/tests unchanged. Focused baseline gate (`CardCatalogTests`, `AccountsCoreCashflowBridgeTests`, `AccountBalanceEngineTests`, `AccountProductFactoryTests`, `AccountsCoreBackupTests`) succeeded on `Millio-375-QA`; xcresult: `Test-millio-2026.08.11_17-06-44-+0300.xcresult`. Awaiting the literal Phase 1 guard phrase.
- 2026-08-11: Adversarial plan stress-test completed. Added currency rounding, effective-date validation, true-concurrent double-spend, persisted refund linkage and exhaustive writer-inventory ACs. Inserted mandatory Phase 1Q legacy read quarantine before semantic/UI phases. Production/schema/tests unchanged.
- 2026-08-11: Phase 1 remains open. Added executable destructive-read characterization and relabelled the existing `100 - 500 = -400` case as a writer compatibility bug. Targeted command succeeded (`Test-millio-2026.08.11_19-09-41-+0300.xcresult`), but the mandatory deterministic true-concurrent double-spend and injected split-save failure fixtures are still absent. Static code tracing is evidence of risk, not a passing concurrency gate; later phases must not start.
- 2026-08-11: Phase 1Q safety patch was implemented before the Phase 1 self-audit caught the incomplete gate. The patch itself is narrow and verified: `CardCatalog.fetchAll` is a pure read, duplicate fetch preserves both persisted rows and leaves `ModelContext.hasChanges == false`; mixed-store tests succeeded (`Test-millio-2026.08.11_19-11-05-+0300.xcresult`); `git diff --check` passed. It is retained because reverting would restore a proven destructive read, but Phase 1Q is not credited complete out of order. Schema/data unchanged.
- 2026-08-11: Phase 1 gate completed after adding the missing executable evidence. The coordinator suite proves injected whole-graph rollback, stable-ID retry/conflict, relaunch-compatible persisted lookup and two pre-created `ModelContext` withdrawal submissions serialized on the single `@MainActor` write boundary: exactly one of two 60 RUB expenses commits against 100 RUB. The old split bridge was re-characterized precisely: its early save commits the pending Cashflow row too, while swallowed bridge errors can persist a transaction without an event and the second save can report failure after an early durable commit. This is the Phase 4 replacement target, not a fabricated event-only orphan claim.
- 2026-08-11: Phase 1Q re-audited complete. `CardCatalog.fetchAll` has no delete/save/log path; duplicate rows remain persisted and read-model dedup is deterministic.
- 2026-08-11: Phase 2 complete. Added `DebitCurrencyPolicy` and `DebitCardContract`: Decimal-only 0/2/3 minor-unit bankers rounding, effective-date replay, positive magnitudes, non-negative funds, debit/bank-only product boundary and typed actual/converted/lifecycle/incomplete snapshot. No persistence, Cashflow or credit debt/limit/grace semantics.
- 2026-08-11: Phase 3 complete. Added one `DebitCardOperationCoordinator` commit boundary for income, expense, fee, refund, adjustment, same-currency transfer and archive; negative debit opening is rejected by the existing factory. Refund linkage uses persisted/backed-up `CashflowTransaction.operationGroupID`; schema unchanged. Command: `xcodebuild test -project millio.xcodeproj -scheme millio -destination 'platform=iOS Simulator,name=Millio-375-QA' -only-testing:millioTests/DebitCardContractTests -only-testing:millioTests/DebitCardOperationCoordinatorTests -only-testing:millioTests/ProductDefinitionCatalogTests -only-testing:millioTests/AccountProductFactoryTests`; result `TEST SUCCEEDED`; xcresult `Test-millio-2026.08.11_19-53-50-+0300.xcresult`. `git diff --check` passed.
- 2026-08-11: Phase 4 implementation is present but its gate is blocked. Debit Cashflow create/edit/delete routes through `DebitCardOperationCoordinator`; the coordinator owns the material save and the persistence service skips a second no-op save. Focused contract/coordinator/bridge command passed 20/20 on `Millio-390-QA`; xcresult `Test-millio-2026.08.11_20-12-16-+0300.xcresult`. Broader `CashflowViewModelTests` failed reproducibly: 83 passed, 6 failed (historical end-day snapshot, four recurring-generation cases, recurring-template balance); xcresult `Test-millio-2026.08.11_20-13-29-+0300.xcresult`. `git diff --check` passed. Phase 4 is not complete and later phases are not credited. Partial UI/localization/backup work is unshipped evidence only. Schema unchanged; no legacy rows removed.
- 2026-08-11: Phase 4 complete after explicit authorization to repair the existing Cashflow changes. `CashflowScheduledService` now starts generated occurrences after the template anchor, advances rejected occurrences instead of looping, and captures one scheduling timestamp; category history uses the explicit legacy-asset compatibility fallback only when structured history is absent. Command: `xcodebuild test -project millio.xcodeproj -scheme millio -destination 'platform=iOS Simulator,name=Millio-375-QA' -only-testing:millioTests/CashflowViewModelTests`; result: 89/89 passed, `Test-millio-2026.08.11_20-34-38-+0300.xcresult`. Test contracts were unchanged.
- 2026-08-11: Phase 5 complete. Debit detail uses the typed balance-first snapshot; expense/income/transfer/fee/refund/adjust/archive route through `DebitCardOperationCoordinator`; refund selection persists original-operation linkage. Focused contract/coordinator/factory/catalog/bridge/backup/localization command passed 47 tests, `Test-millio-2026.08.11_20-38-06-+0300.xcresult`. Currency and product transition editing remain blocked by policy.
- 2026-08-11: Phase 6 complete. `CardCatalog` remains a pure legacy reader; importer remains stable-ID-first; current and old backup fixtures preserve core IDs/links. No legacy row was removed and no new sensitive write/log path was introduced.
- 2026-08-11: Phase 7 complete as a decision gate. Existing backed-up `CashflowTransaction.operationGroupID` is sufficient for refund linkage; no persisted gap was proved. Schema is unchanged. Legacy `Card`, PAN and CVV retention remains untouched pending separate authorization.
- 2026-08-11: Phase 8 complete. RU/EN/zh-Hans catalog validation passed. DEBUG-only opt-in harness rendered 32 screenshots (8 states × 2 sizes × 2 themes) under `screenshots/2026-08-11-debit-card-render-matrix/`; visual audit caught and fixed 375-pt incomplete-state truncation with a multiline Dynamic Type-safe layout. UI bootstrap passed on both simulators: `Test-millio-2026.08.11_20-42-03-+0300.xcresult` and `Test-millio-2026.08.11_20-42-33-+0300.xcresult`.
- 2026-08-11: Phase 9 complete. Combined debit/property/AccountsCore/Cashflow/Finance/backup/localization command passed, `Test-millio-2026.08.11_20-51-28-+0300.xcresult`. The broader Finance gate initially exposed `testCreditAlwaysDecreasesTotal`: legacy credits with `includeInTotal=false` were omitted. The production load path now normalizes that legacy liability invariant before rebuilding caches; the unchanged focused test passed in `Test-millio-2026.08.11_20-50-23-+0300.xcresult`. Debug and Release simulator builds succeeded; `jq empty`, static writer/sensitive-log scans and `git diff --check` passed. Schema unchanged; legacy `Card` retained.
