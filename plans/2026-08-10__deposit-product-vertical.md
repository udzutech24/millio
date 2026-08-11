# Plan: продуктовая вертикаль «Вклады»

## Inputs

- Research: `thoughts/research/2026-08-10-deposit-product-vertical.md`
- Spec: `specs/2026-08-10-deposit-product-vertical.md`

## Decision

- Chosen approach: keep `Account`/`AccountEvent` as the only ledger; add a pure deposit financial/presentation contract and one deposit operation coordinator. Cashflow remains a one-way exactly-once projection.
- Rejected alternatives: UI-only facelift; parallel Deposit/DepositTransaction store; recurring Cashflow template; schema-first universal bank rules.
- Rollback strategy: every phase is independently revertible. New UI remains behind existing product routing until core gates pass. No persisted change without old-store/export/import/rollback fixtures. Existing generated events are never silently rewritten.

## Phase 0 — research/spec/plan

- [x] Trace create → meta/events → replay/totals/history → Cashflow → UI → backup.
- [x] Identify proven failures, hypotheses, alternatives and recommended architecture.
- [x] Align numbered AC with phases and verification gates.
- Evidence: documents above; no production/schema/test edits.

## Phase 1 — characterization and schema decision

- [x] Current formulas, rounding, ACT/365, month-end, timezone/day-key and deterministic replay characterized.
- [x] Forecast-to-fact, unsafe magnitude/availability, inert lifecycle flags and corrupt-meta behavior reproduced.
- [x] Serial and serial multi-context Cashflow projection deduplication verified; true concurrent insertion retained as Phase 4 risk.
- [x] Early-close failure injection proved unreachable at the current save boundary; per-stage atomic matrix deferred to the Phase 3 coordinator that can expose those stages.
- [x] Schema decision recorded: **unchanged**.

**Scope:** tests and decision record only. Lock the current contract before changing it.

**Files:** existing deposit test suites; optional new `DepositFinancialContractCharacterizationTests.swift`; research/spec/plan journal.

**Tests/evidence:**

- none/monthly/quarterly calculations and per-period rounding;
- leap interval and explicit ACT/365 behavior;
- Jan 28/29/30/31, Istanbul/UTC/Los Angeles DST and same-day ordering/day key;
- future generated interest crossing `now` and entering accrued/Cashflow;
- negative/oversized expense and transfer;
- injected failures across every early-close stage;
- maturity, `autoRollover`, `remindEnd`, `payoutDay` reachability;
- serial and multi-context duplicate projection fixtures;
- backup/restore of generated IDs and corrupt DepositMeta.

**Acceptance gate:** AC-C1, evidence for C3/P2/P4/P5/F2/B1/B2. Every proven behavior is labelled desired, compatibility debt or bug. Explicit decision: schema unchanged or minimal additive fields/event type with fixtures.

**Rollback:** tests/docs only.

**Guard phrase:** `Реализуй фазу 1 по плану plans/2026-08-10__deposit-product-vertical.md`.

## Phase 2 — typed financial and presentation contract

- [x] Added an injected Gregorian/timezone/day-count calendar policy.
- [x] Added typed amount provenance, lifecycle, capabilities and safe unresolved reason codes.
- [x] Separated principal, confirmed interest, due estimates, future estimates, current and projected balances.
- [x] Confirmed interest suppresses the generated estimate for the same calendar period.
- [x] Missing/corrupt metadata, invalid values and unsupported provider rules return unavailable/incomplete state.
- [x] No writer, UI, Cashflow, schema or persisted event changed.

**Scope:** pure, deterministic policy over existing events/meta. Separate principal, confirmed, estimated due, future and incomplete values. No UI and no writer changes.

**Files:** new responsibility-focused `Core/AccountsCore/Deposit/DepositFinancialContract.swift`, `DepositCalendarPolicy.swift`, tests; move existing scheduler only if needed without broad refactor.

**Tests:** property/invariant replay; stable ordering; month-end/DST; confirmed-versus-generated source IDs; unsupported day-count/variable-rate state; zero/corrupt inputs.

**Acceptance gate:** AC-C2, the read-model/deduplication portion of AC-C3, and AC-C4–C5. The Cashflow clause of AC-C3 cannot honestly close in this read-only phase and remains an explicit Phase 4 gate. Current/historical persisted values remain observationally compatible.

**Rollback:** remove pure adapter; ledger unchanged.

**Guard phrase:** `Реализуй фазу 2 по плану plans/2026-08-10__deposit-product-vertical.md`.

## Phase 3 — atomic deposit operation coordinator

**Scope:** sole typed writer for top-up, supported withdrawal, term edit, interest confirmation/upsert, maturity, rollover and early close. Fix the proven two-save close and enforce availability/terms.

**Files:** new `Core/AccountsCore/Deposit/DepositOperationCoordinator.swift`; minimal staging APIs in `AccountsCoreService`/scheduler/save boundary; dedicated tests.

**Tests:** positive magnitude, active state, capability, sufficient funds, past-preservation/future-regeneration, stable operation IDs, retry, every-stage save failure, unrelated later save cannot resurrect a partial graph.

**Acceptance gate:** AC-P1–P6 and the command-side portion of AC-C3. One outer disposable-context commit per graph; zero partial rows after failure. Cashflow exactly-once enforcement remains Phase 4.

**Rollback:** old UI is not routed to new commands until Phase 5; coordinator can be removed independently.

**Guard phrase:** `Реализуй фазу 3 по плану plans/2026-08-10__deposit-product-vertical.md`.

## Phase 4 — Cashflow projection and refresh consistency

**Scope:** route eligible confirmed/explicit-auto-post interest through one exactly-once projection; publish one refresh only after successful outer commit.

**Files:** `AccountsCoreDepositCashflowBridge.swift`, finance event boundary, Cashflow/Finance integration tests.

**Tests:** one event → one row; no balance effect; retry/relaunch/catch-up/multi-context duplicate; terms edit preserves past rows; failed operation publishes nothing; detail/list/groups/dashboard/Dynamics/Cashflow converge without relaunch.

**Acceptance gate:** AC-F1–F4, AC-H1, AC-H4.

**Rollback:** compatibility bridge behind one policy switch; never enable recurring template fallback.

**Guard phrase:** `Реализуй фазу 4 по плану plans/2026-08-10__deposit-product-vertical.md`.

## Phase 5 — specialized creation, detail, edit and lifecycle UX

- [x] Creation provides a live ACT/365 estimate, typed validation and keyboard dismissal.
- [x] Detail is driven only by `DepositPresentationSnapshot` and visually labels estimates.
- [x] Deposit actions are capability-driven and route only through `DepositOperationCoordinator`.
- [x] Terms edit and early-close sheets preview impact before committing.
- [x] Matured, archived and incomplete states have explicit read/write policy.
- [x] Focused presentation/contract/coordinator/archive gate passed.

**Scope:** implement chosen “progress to date and income” concept using the typed snapshot and coordinator.

**Files:** dedicated small views under `UI/Services/Finances/AccountsCore/Deposit/`; thin routing changes in creation/detail; no formulas in SwiftUI.

**States:** creation preview, normal, savings, due-soon, matured-needs-action, early-close preview, archived, error/incomplete.

**Tests:** typed presentation mappings, capability-driven actions, edit preview, early-close amounts/destination, archived read-only, focus/keyboard policy.

**Acceptance gate:** AC-U1–U6 and AC-H2–H3. Generic income/expense/adjust are inaccessible where semantically invalid.

**Rollback:** specialized route can fall back to generic read-only detail, not generic unsafe writers.

**Guard phrase:** `Реализуй фазу 5 по плану plans/2026-08-10__deposit-product-vertical.md`.

## Phase 6 — maturity reminders and rollover

- [x] AccountsCore maturity reminders schedule/cancel/reschedule through a dedicated namespace.
- [x] Permission denial and past maturity stay unscheduled; create/edit/archive/close paths are wired.
- [x] Auto-rollover remains hidden because no background execution engine exists; explicit rollover stays coordinator-only.

**Scope:** wire existing notification infrastructure to AccountsCore and implement only the maturity/rollover behavior whose persisted contract Phase 1 approved.

**Files:** deposit lifecycle policy/coordinator, `NotificationManager`, typed preferences/meta mapping, tests.

**Tests:** schedule/cancel/reschedule, permission denial, past date, timezone/short month, edit/archive/close cleanup, rollover retry/rollback.

**Acceptance gate:** AC-P5 and relevant AC-U2/U6. No visible toggle is decorative.

**Rollback:** cancel new notification namespace; financial ledger remains valid.

**Guard phrase:** `Реализуй фазу 6 по плану plans/2026-08-10__deposit-product-vertical.md`.

## Phase 7 — tax/FX completeness

- [x] Owner-wide yearly tax input uses one allowance and event-date direct/inverse RUB FX.
- [x] Missing/invalid FX or settings returns typed incomplete; raw foreign nominal amounts are never labelled RUB.
- [x] Forecast events do not enter historical tax facts; legal defaults were not changed.

**Scope:** build owner-wide event-date RUB normalization and typed incomplete tax presentation. Do not update legal defaults without a separately sourced policy decision.

**Files:** deposit tax read model, historical FX resolver/store adapters, detail presentation, tests.

**Tests:** multiple deposits/currencies/years, direct/inverse rate, missing FX, no per-account allowance, forecast crossing year boundary, no raw foreign amount labelled RUB.

**Acceptance gate:** AC-T1–T4.

**Rollback:** hide tax amount and show unavailable; never fall back to current FX/raw amount.

**Guard phrase:** `Реализуй фазу 7 по плану plans/2026-08-10__deposit-product-vertical.md`.

## Phase 8 — conditional migration and backup gate

- [x] Phase 1 schema decision revalidated: schema unchanged; operation identity reuses backup-compatible event source IDs.
- [x] Account/meta/event round-trip, old backup, restore integrity and corruption gates passed.
- [x] No migration or source rewrite was introduced.

**Scope:** only if Phase 1 proves a persisted gap. Otherwise record `schema unchanged` and run existing backup/restore/corruption gates.

**Files:** schema/migration/feature registration/backup only when required.

**Tests:** V(n-1)→Vn fixture, optional/default decoding, export/import, corrupt rollback, restore idempotency, orphan-free projection rebuild.

**Acceptance gate:** AC-B1–B3. No source data rewrite and no destructive cleanup.

**Rollback:** old binary reads old fields; new optional fields ignored; retain source events.

**Guard phrase:** `Реализуй фазу 8 по плану plans/2026-08-10__deposit-product-vertical.md`.

## Phase 9 — localization, accessibility, render and release audit

- [x] New copy has RU/EN/zh-Hans entries; raw-key localization suites passed.
- [x] VoiceOver containment/actions, Dynamic Type and Reduce Motion are covered by the presentation render gate.
- [x] Required states render through `ImageRenderer` at 375×812 and 390×844.
- [x] Debug and Release simulator builds, diff check, target inclusion and safe-log scan passed.

**Scope:** typed RU/EN/zh-Hans copy, accessibility and full release verification.

**Verification:** raw-key audit; VoiceOver; Dynamic Type; Reduce Motion; 375×812 and 390×844 screenshots for every required state; focused and regression suites; clean Debug/Release simulator builds; `git diff --check`; safe-log scan; AC self-audit.

**Acceptance gate:** AC-L1–L3, AC-B4 and every remaining AC. No release with clipped primary action, fabricated value, duplicate Cashflow row, partial graph or writable archive.

**Rollback:** presentation-only changes independently revertible; semantic core retained.

**Guard phrase:** `Реализуй фазу 9 по плану plans/2026-08-10__deposit-product-vertical.md`.

## Verification matrix

- Unit: financial/calendar policy, property invariants, typed presentation, tax allocation.
- Persistence: stable IDs, idempotency, whole-graph rollback, backup/corrupt import, conditional migration.
- Integration: AccountsCore ↔ Cashflow projection, refresh convergence, totals/history/group equality.
- UI: creation/detail/edit/maturity/close state matrix, localization/accessibility/render.
- Final: targeted suites, broader finance regressions, clean builds and diff check.

## Acceptance mapping

| AC group | Phases | Sufficient evidence |
|---|---|---|
| C1–C5 | 1–2, 3 | characterization + pure invariant suites + writer boundary |
| P1–P6 | 1, 3, 6 | atomic failure matrix + lifecycle tests |
| F1–F4 | 1, 4 | exactly-once/no-balance-effect integration |
| H1–H4 | 3–5 | shared endpoint and refresh fixtures |
| T1–T4 | 7 | multi-currency owner-wide completeness suite |
| U1–U6 | 5–6 | typed state tests + simulator scenarios |
| L1–L3 | 9 | localization/accessibility/render matrix |
| B1–B4 | 1, 8–9 | backup/migration decision + safe-log release gate |

## Challenge Log

1. **Does this solve the problem?** Yes. Every numbered AC maps to at least one phase and a concrete gate. Financial truth and atomicity precede UI.
2. **Is it the simplest safe solution?** Yes. It reuses Account/AccountEvent, product catalog, save boundary, historical resolver, NotificationManager and Cashflow bridge. A second ledger and recurring template are rejected.
3. **Any code for code's sake?** Conditional features are deferred: no schema, variable-rate model, provider rules or auto-rollover engine until Phase 1 proves and specifies the persisted need.

## Journal

- 2026-08-11: Device-feedback polish for the deposit hero. Added locale-aware grouped money formatting, clearer type hierarchy, adaptive interest metric cards, readable date/amount rows, larger actions, and an explicitly labelled term-progress bar instead of the ambiguous bare percentage. Deposit presentation/render tests pass.

- 2026-08-10: Phase 0 complete on dirty user baseline. Research/spec/plan created; production/schema/tests unchanged. Awaiting the literal Phase 1 guard phrase.
- 2026-08-10: Phase 1 complete. Added deposit characterization and serial multi-context projection fixtures; focused gate succeeded in 28.506s. Schema remains unchanged. Production/UI/schema untouched; next guard is Phase 2.
- 2026-08-10: Phase 2 complete. Added pure `DepositCalendarPolicy` and `DepositFinancialContract` with typed provenance/incomplete/lifecycle output. Final focused contract + characterization + scheduler + replay gate passed 48/48 tests in 24.626s. Cashflow still uses the compatibility path and keeps AC-C3 open until Phase 4.
- 2026-08-10: Phase 3 complete. Added the disposable-context `DepositOperationCoordinator`, creation-term validation and atomic commands for top-up, confirmation, term edit, maturity, rollover and early close. Partial withdrawal stays explicitly unsupported until a persisted policy exists. The final expanded regression gate passed 71/71 tests; Cashflow routing remains Phase 4.
- 2026-08-10: Phase 4 complete. Added confirmed-only `DepositCashflowProjector`, atomic confirmation + Cashflow persistence, typed corruption diagnostics and one post-commit `depositOperationCommitted` refresh consumed by Finance, Cashflow and Dynamics. Generated due estimates no longer become income. Expanded regression gate passed 97/97 tests.
- 2026-08-10: Phase 5 complete. Added live creation estimates and validation, a typed deposit presentation mapper, dedicated hero/actions/edit/top-up/close UX and coordinator-only writes. Generic income/expense/adjust/transfer routes are inaccessible for deposits; generated forecasts are excluded from history; archived/incomplete deposits are read-only and maturity exposes only the typed withdrawal action. Debug simulator build passed; expanded focused gate passed 37/37 tests and the final presentation regression gate passed 5/5.
- 2026-08-11: Phases 6–9 complete. Wired maturity reminder lifecycle without exposing auto-rollover, added owner-wide event-date FX tax completeness, confirmed schema unchanged through backup/restore gates, localized RU/EN/zh-Hans copy, rendered all states at 375×812/390×844 with accessibility Dynamic Type, passed safe-log/diff audits and clean Debug/Release simulator builds.
