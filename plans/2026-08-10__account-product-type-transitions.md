# Plan: безопасная смена типов продуктов

## Inputs

- Research: `thoughts/research/2026-08-10-account-product-type-transitions.md`
- Spec: `specs/2026-08-10-account-product-type-transitions.md`

## Phase 0 — decision documents

- [x] Трассированы product identity, replay engines, metadata и valuation boundaries.
- [x] Сформирована матрица correction / conversion / blocked.
- [x] Запрещён generic field flip.

## Phase 1 — exhaustive pure transition policy

- [x] Exhaustive family-based pair classifier returns correction, replacement or typed block.
- [x] Pristine deposit, credit/loan/debt, market quote identity and invalid tuple gates are explicit.

**Scope:** `AccountProductTransitionPolicy`, event summary и exhaustive pair matrix; без writes/UI.

**Tests:** все пары типов; cash-like/manual/market equivalence; pristine deposit; credit/loan/debt/cross-engine blocks; invalid metadata.

**Gate:** PT-C1–C5.

**Guard phrase:** `Реализуй фазу 1 по плану plans/2026-08-10__account-product-type-transitions.md`.

## Phase 2 — atomic in-place correction

- [x] Full identity/metadata tuple and revisions mutate in one disposable-context save.
- [x] Backup-compatible operation marker provides retry/relaunch conflict detection and rollback.

**Scope:** correction coordinator только для разрешённых policy переходов.

**Tests:** tuple validation, stable ID/retry/conflict, every-stage rollback, history/totals invariants, backup.

**Gate:** PT-P1, PT-P3–P4, PT-H1, PT-B1.

**Guard phrase:** `Реализуй фазу 2 по плану plans/2026-08-10__account-product-type-transitions.md`.

## Phase 3 — replacement conversion

- [x] Supported deposit/cash-like replacement archives source and creates target atomically.
- [x] Confirmed balance and group identity transfer without overlap; generated interest is excluded.
- [x] Save failure and retry leave no partial or duplicate graph.

**Scope:** archive source + create target atomically только для явно поддержанных family pairs. Остальные остаются blocked.

**Tests:** balance handoff without double count; failure matrix; credit/debt/loan/market refusal; retry/relaunch/restore.

**Gate:** PT-P2–P4, PT-H1–H2, PT-B1.

**Guard phrase:** `Реализуй фазу 3 по плану plans/2026-08-10__account-product-type-transitions.md`.

## Phase 4 — preview and UX

- [x] Account detail separates «Исправить тип» from destructive «Перенести в новый продукт».
- [x] Replacement requires a destructive confirmation and preserves source-history copy.
- [x] Blocked transitions expose stable typed reason codes; RU/EN/zh-Hans chrome is localized.

**Scope:** отдельные flows «Исправить тип» и «Перенести в новый продукт», reason codes, localization/accessibility.

**Tests:** allowed/blocked matrix presentation, destructive copy, Dynamic Type, RU/EN/zh-Hans, render matrix.

**Gate:** PT-U1–U2.

**Guard phrase:** `Реализуй фазу 4 по плану plans/2026-08-10__account-product-type-transitions.md`.

## Rollback

Каждая фаза независима. Correction/Conversion не подключаются к UI до полного persistence gate. Schema не меняется без отдельного доказательства и backup/migration fixtures.

## Journal

- 2026-08-11: Phases 1–4 complete. Added exhaustive pure matrix, atomic correction and replacement coordinators with persisted stable operation markers, rollback/idempotency tests, confirmed-balance handoff without total overlap, and separate localized correction/conversion/blocked UX. Schema unchanged.
- 2026-08-11: UX follow-up after device feedback. Moved product transition from the account-detail body into «Изменить», excluded the current/legacy type from targets, replaced raw diagnostic labels with localized copy, kept operation IDs stable for retries, and dismissed the stale detail instance after an isolated-context commit so the refreshed account list reflects the new type.
- 2026-08-11: Fixed a second device-feedback defect: selecting Deposit had been a dead-end because required `DepositMeta` was never collected. The edit flow now requests rate, capitalization, term, top-up and early-close conditions, validates them, then exposes the real correction/replacement action. Focused transition tests pass.
