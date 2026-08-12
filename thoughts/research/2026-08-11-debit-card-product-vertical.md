# Research: продуктовая вертикаль «Дебетовые и банковские карты»

- Date: 2026-08-11
- Scope: iOS legacy `Card`, AccountsCore debit/bank-account products, Cashflow, totals/history/groups/Dynamics, backup, refresh, security and product UX.
- Mode: read-only production audit; only Research/Spec/Plan/status/reflection documentation was changed.
- Boundary: credit cards are excluded. Their available-limit/debt/grace contract remains in the separate credit-card vertical.

## Executive verdict

The strongest part is already the correct foundation: new creation writes one `Account` plus one opening `AccountEvent` through an isolated, single-save factory; current and historical values replay the same event ledger; debit cards contribute their own signed balance to net worth; archive is time-aware and retains events.

The vertical is nevertheless not bulletproof. The UI is still a generic account screen, but that is not the critical defect. The critical defects are financial and persistence boundaries: generic debit writers accept invalid magnitudes/overdraft, Cashflow and AccountEvent do not share one durable commit, ordinary reads can delete legacy cards, and legacy `Card` still persists PAN/CVV-shaped payloads and logs card names. A cosmetic plastic-card redesign before these are fixed would be irresponsible.

**Hard recommendation:** keep `Account`/`AccountEvent` as the sole forward ledger; add a small debit-card financial/presentation policy and one atomic operation coordinator that owns AccountEvent plus Cashflow projection. Keep legacy `Card` as a quarantined compatibility source until linkage/backup fixtures prove safe retirement. Do not add schema or a second ledger.

## End-to-end map

| Stage | Source of truth / writer | Read model / refresh | Save boundary / tests | Drift risk |
|---|---|---|---|---|
| Create | `FinanceProductCreationCommandResolver` maps card input to `.debitCard` + optional `CardMeta`; `AccountProductFactory` writes Account + opening event | Finance reload via `investmentsUpdated` | Disposable context, one save (`FinanceProductCreationCommandResolver.swift:111-144`; `AccountProductFactory.swift:225-265`) | Opening amount is not debit-specific validated; negative opening survives. |
| Persisted identity | `Account.productTypeRaw`, `kindRaw`, optional `CardMeta`; no stored balance | `ProductDefinitionCatalog` | Catalog validates debit has no credit limit (`ProductDefinitionCatalog.swift:165-180,281-289`) | Card and bankAccount have slightly different metadata allowance; UI semantics are still shared/generic. |
| Opening/current/history | `AccountEvent(.openingBalance)`; all changes are events | `AccountBalanceEngine.balanceAt` | Same cash-like sign map for current and historical (`Account.swift:4-5`; `AccountBalanceEngine.swift:102-119`) | No debit non-negative invariant. |
| Income/expense/adjust | Cashflow-first route calls `AccountsCoreCashflowBridge.upsertEvent`; detail calls generic `AccountsCoreService` | Detail local `refreshToken`; Finance/Dynamics event subscribers | `upsertEvent` saves before outer Cashflow save (`AccountsCoreService.swift:406-465`; `CashflowPersistenceService.swift:328-357`) | Proven split commit / orphan or missing projection. Direct detail events have no Cashflow row. |
| Transfer | `AccountsCoreService.transfer` writes two linked events; Cashflow bridge uses same path | Account replay; Cashflow transaction classifies transfer separately | Two legs share one context save (`AccountsCoreService.swift:580-633`) | Amount can be non-positive; mixed legacy/core transfer becomes income/expense event and is not a canonical two-leg core transfer. |
| Fee/refund | No debit-specific command. `fee` is not allowed for debit; refund is generic income | Generic event list | Catalog cash events omit fee (`ProductDefinitionCatalog.swift:129-167`) | Required semantics absent; refund cannot link/cap original expense. |
| Totals/groups | `Account.participates(on:)` + replay + `AccountTotalsContribution` | Finance totals, historical producer, group and Dynamics consumers | Shared contribution path (`Account.swift:93-108`; `AccountTotalsContribution.swift:22-31`) | Strong for core; legacy/core predecessor selection still depends on conversion registry. |
| Detail/list | `AccountDetailView` directly computes `balanceToday` and renders generic actions/history | Local token plus selected event-bus publications | Generic sheets/service (`AccountDetailView.swift:4-79`) | No typed debit snapshot, no incomplete state, generic adjustment exposed. |
| Edit | `AccountsCoreService.updateAccount` updates display/meta/membership | Finance reload published by detail | Clean-context precondition + typed save boundary (`AccountsCoreService.swift:724-781`) | Strong atomicity; no debit-specific metadata editor; archived guard is not centralized for generic writers. |
| Archive/delete | `archiveAccount` timestamps account; soft delete keeps graph | Historical participation cuts off on date; archived detail is read-only by routing | One save (`AccountsCoreService.swift:784-823`) | Generic non-zero warning exists; direct service methods do not uniformly reject archived operation writes. |
| Backup/restore | Account, events and CardMeta export/import; legacy Card has separate registration/importer | Registry and importers rebuild links | Account fields and events export stable IDs (`Account.swift:110-138`; `AccountEvent.swift:121-146`) | Legacy Card import dedup uses mutable display fields, not stable ID; legacy-core registry is device-local. |
| Legacy read | `CardCatalog`, `FinanceAccountService`, legacy valuator/Dynamics | `CardSnapshotFactory`, legacy FinanceAccount wrapper | `CardCatalog.fetchAll` may delete and save while fetching (`CardCatalog.swift:53-80`) | Critical hidden mutation and potential orphan references. |

## Ownership map

| Concern | Canonical owner going forward | Compatibility owner | Must not own |
|---|---|---|---|
| Debit balance | `AccountEvent` replay | Legacy `Card.balance` only before verified conversion boundary | UI, Cashflow projection, `CardSnapshot` |
| Product identity | `Account.productType == .debitCard/.bankAccount` | `Card.cardTypeRaw` for legacy rows | Bank metadata heuristic |
| Bank metadata | `Account.cardMeta` (`bank`, optional `last4`) | Legacy `Card` fields | Cashflow transaction |
| Cashflow classification | `CashflowTransaction` projection linked by stable source ID | Legacy Cashflow rows | A second balance engine |
| Historical valuation | structured AccountsCore historical producer plus explicit legacy predecessor | legacy valuator before conversion cutoff | detail view recomputation |
| Group membership | `Account.group` for core; `FinanceAccount` junction for legacy | conversion/migration boundary | destructive dedup fetch |

### `Card` ↔ AccountsCore ↔ Cashflow

1. A new card is only an AccountsCore `Account`; the production create path explicitly says it never creates legacy `Card` (`FinanceAddAccountView.swift:1110-1161`).
2. Existing legacy cards remain schema/backup/import entities and active Finance/Dynamics inputs (`Card.swift:108-173`; `CardFeatureRegistration.swift:11-19`; `FinanceAccountService.swift:106-145`).
3. Conversion creates a core twin with a new UUID, records legacy→core mapping in `LegacyConversionRegistry`, archives the legacy row, then remaps Cashflow/card IDs (`LegacyAccountConversion.swift:25-50`; `LegacyAccountConverter.swift:52-77`; `LegacyAccountsMigrator.swift:125-165`). IDs therefore do not intrinsically match.
4. New-core Cashflow resolves real `Account.id`, creates/upserts `AccountEvent` by `CashflowTransaction.uniqueID`, and never mutates legacy `Card.balance` (`AccountsCoreCashflowBridge.swift:33-49,68-109`). Legacy targets still mutate `Card.balance` (`CashflowPersistenceService.swift:448-485`).
5. This is controlled dual architecture, not safe dual-write. A single transaction chooses a world by resolved target. The broken edge is durability: event and transaction are saved separately.

## Financial contract evidence

For debit/bank cards, cash-like replay already implements:

`opening + income - expense + transferIn - transferOut - fee + adjustment`

through one sign map (`AccountBalanceEngine.swift:108-119`). `includeInTotal=false` is a membership rule and does not hide or delete the account/history (`Account.swift:93-108`). `AccountTotalsContribution` leaves debit balances unchanged when no credit limit exists (`AccountTotalsContribution.swift:22-31`). This proves canonical debit value is the user's own balance, not an available credit amount.

Missing contract enforcement:

- creation accepts any debit opening balance; factory has deposit-specific positivity rules but none for debit (`AccountProductFactory.swift:95-117`);
- `recordEvent`, `upsertEvent`, and `transfer` accept zero/negative magnitudes and do not check resulting funds (`AccountsCoreService.swift:153-184,406-465,585-633`);
- the existing characterization test explicitly expects an expense of 500 on balance 100 to yield -400 (`AccountsCoreCashflowBridgeTests.swift:302-318`);
- `fee` is not in debit allowed events, refund has no typed link, and adjustment is a generic delta.

Therefore overdraft is currently **implicitly allowed**, not deliberately modeled. That is a proven contract defect for this vertical.

## Operation audit

| Operation | Current command/sign | Cashflow classification | Links/idempotency | Atomicity/validation | Verdict |
|---|---|---|---|---|---|
| Opening | `.openingBalance`, signed stored amount | none | account relation | atomic factory; no debit non-negative validation | Works structurally; validation broken. |
| Purchase/expense | `.expense`, subtract | expense | `sourceTransactionID` on Cashflow path | amount/funds not enforced; split save | Proven broken. |
| Income | `.income`, add | income | source ID on Cashflow path | split save; generic positive amount not enforced | Partly works. |
| Transfer | `.transferOut`/`.transferIn` | transfer, not income/expense | shared transfer ID + source ID | legs atomic; magnitude/funds missing | Partly works. |
| Fee | no debit UI/writer; engine knows `.fee` subtracts | should be expense/fee | absent | catalog rejects | Absent. |
| Refund | generic `.income` | income today | no original-expense link/cap | no typed semantics | Absent as a correct refund. |
| Adjustment | `.adjustment` delta | adjustment transaction | source ID on Cashflow path | arbitrary; no required reason | Works mechanically, unsafe semantically. |
| Archive non-zero | timestamp cutoff | none | history retained | one save; generic warning | Core behavior works. |

## Proven defects

### D1 — Debit overdraft and invalid magnitude are accepted (high)

- Input: debit/cash account opening 100; expense 500.
- Expected: reject because overdraft is not an explicit product capability.
- Actual: balance becomes -400.
- Evidence: `AccountsCoreCashflowBridgeTests.swift:302-318`; no magnitude/funds guard in `AccountsCoreService.swift:153-184,585-633`.

Negative expense/transfer is a related proven code-path defect: the writer multiplies stored amount by a sign without requiring `> 0`, so a negative expense increases balance and a negative transfer reverses both legs. A dedicated red test is still required before implementation.

### D2 — Cashflow↔Account graph is not atomic (critical)

- Input: create/edit a Cashflow transaction targeting a core debit card; bridge succeeds; final Cashflow save fails.
- Expected: neither transaction nor AccountEvent persists.
- Actual by code: bridge `upsertEvent` calls `saveOrRollback` first; the later Cashflow save is a second boundary. Conversely, bridge errors are caught and transaction save continues.
- Evidence: `AccountsCoreService.swift:462-465`; `CashflowPersistenceService.swift:328-357`.

This is a code-proven failure path; an injected-save characterization test is required in Phase 1.

### D3 — Read path destructively deduplicates legacy cards (critical)

- Input: two legacy Card rows with the same derived/stable ID but distinct linked history/group/backup state.
- Expected: read returns a deterministic view or typed corruption; no data mutation.
- Actual: `fetchAll` deletes all but newest and saves during read.
- Evidence: `CardCatalog.swift:53-80`; selection is only `updatedAt` (`CardCatalog.swift:83-109`).

No code transfers related `CashflowTransaction`/`FinanceAccount` links before deletion. Existing tests characterize only in-memory winner selection, not persisted relationship safety (`CardCatalogTests.swift:30-61`).

### D4 — Sensitive legacy fields are persisted and backed up (critical security)

- Input: a legacy Card with encrypted full PAN/CVV.
- Expected: vertical stores neither PAN nor CVV; last4 only if necessary.
- Actual: model contains `encryptedFullNumber` and `encryptedCVV`, exports them, and importer restores them.
- Evidence: `Card.swift:114-149,303-309`; `CardFeatureRegistration.swift:85-92,136-143`.

Encryption does not satisfy the stated data-minimization requirement. Removal needs a separately authorized, carefully staged data-retention migration; it is not silently added to this vertical's v1 schema plan.

### D5 — Legacy import/logging exposes identifying metadata and uses unsafe identity (high)

- Input: restore two cards sharing name/last4/bank/type/currency or a card name containing PII.
- Expected: stable-ID-first idempotent restore and safe reason-code logging.
- Actual: importer matches mutable display fields and logs the card name; `CardCatalog` logs raw localized persistence errors.
- Evidence: `CardFeatureRegistration.swift:43-67,95`; `CardCatalog.swift:74-78`.

## Status table

| Status | Finding |
|---|---|
| Already works | AccountsCore single ledger; atomic create graph; shared current/historical replay; time-aware include/archive; two-leg transfers; Account/CardMeta/Event backup fields; legacy conversion preserves an explicit predecessor. |
| Proven broken | D1 overdraft/magnitude; D2 split Cashflow save; D3 mutation during fetch; D4 PAN/CVV persistence; D5 mutable-field import and PII logging. |
| Hypothesis | concurrent duplicate `sourceTransactionID` rows because no uniqueness constraint; stale detail object after isolated commits; VoiceOver/Dynamic Type clipping at 375/390; corrupt CardMeta incomplete presentation. Must be characterized. |
| Absent | debit-specific typed snapshot/commands; fee/refund policy; safe adjustment reason; explicit overdraft policy; debit render/localization matrix. |
| Legacy/not forward-used | legacy Card editor/manager writers are compiled and testable but new product creation routes to AccountsCore; legacy Card remains read/backup/migration input and cannot yet be removed. |

## Persistence and migration conclusion

There are two persisted representations across the installed population, but not two representations for every new card. Conversion deliberately creates a new core UUID and keeps predecessor evidence via a device-local registry. Legacy identifiers can be derived from mutable fields when `uniqueID` is missing (`Card.swift:267-274`), so duplicate and missing-ID handling is not strong enough for destructive cleanup.

**No mandatory Account schema migration is yet justified.** Existing `Account`, `AccountEvent`, `CardMeta`, source IDs, transfer IDs, archive timestamps and backup payloads encode balance and transfer semantics. The adversarial plan review reopened one narrow persisted-gap question: whether refund→original-expense identity can be durably owned by existing `CashflowTransaction.operationGroupID` while remaining reconstructible after backup/restore, or needs a minimal additive AccountEvent link. Phase 1 must prove this; notes/category IDs are not acceptable relational storage.

**Legacy Card retirement is not yet proven safe.** Compatibility is currently safer than an eager purge because legacy history, FinanceAccount membership, Cashflow links, cashback links and restore behavior still refer to legacy IDs. Phase 7 is a conditional evidence gate: quarantine destructive reads immediately; migrate/remove only if fixtures prove complete link remap and rollback. Sensitive PAN/CVV retirement is a separate security migration decision requiring explicit authorization.

## UX state audit

- Creation: name/currency/opening balance and optional bank/last4/include/group/note exist. Bank/last4/color are secondary; priority/expiry/cardholder/PAN/CVV are legacy noise. Negative opening is not blocked.
- Normal/zero/excluded: generic detail can show balance/history and membership, but lacks a debit-specific hero, exclusion explanation and capability-driven quick actions.
- Recent/no operations: event list exists; no compact recent-activity hierarchy or typed empty copy.
- Archived: routing supports read-only history; generic service itself does not consistently enforce read-only.
- Corrupt/incomplete: no debit-specific typed incomplete state; generic UI can silently omit metadata.
- Error/refresh: detail stores a string error and local token; global convergence depends on scattered EventBus publications.
- Accessibility/localization/render: generic keys exist, but no debit RU/EN/zh-Hans typed namespace or required 375/390, dark, VoiceOver, Dynamic Type, Reduce Motion matrix is proven.
- FX: core historical infrastructure has provenance, but generic card UI does not clearly distinguish native actual balance from converted portfolio total.

## Architecture alternatives

1. **UI-only facelift over generic service. Rejected.** Cheap but leaves D1/D2 and undefined fee/refund semantics intact.
2. **New DebitCard/Transaction ledger. Rejected.** Duplicates AccountEvent, totals, history, backup and Cashflow; violates KISS and creates reconciliation debt.
3. **Chosen: AccountsCore ledger + thin debit contract/coordinator.** Pure snapshot defines actual balance/capabilities/incomplete reasons; one atomic coordinator stages AccountEvent and Cashflow in an isolated context; UI consumes the typed snapshot. Minimal, reversible and aligned with deposits/credit-card patterns.

## UX alternatives

1. **Balance + quick operations + recent activity — chosen.** Highest five-second value, maps directly to existing ledger/history and needs no new schema. Complexity medium; risk is hiding provenance, mitigated by typed actual/converted labels.
2. **Plastic-card visual first — rejected.** High decoration, low financial value, invites PAN/last4 emphasis and does nothing for D1/D2.
3. **Cashflow analytics first — deferred.** Useful after operation ownership is correct, but duplicates the existing Cashflow/Dynamics surface and increases complexity before the core contract is safe.

## Risk register

| Risk | Severity | Probability | Blast radius | Gate/mitigation |
|---|---|---|---|---|
| Half-written Cashflow/Event graph | Critical | Medium | balance, budgets, history, retry | injected stage/save matrix; one isolated outer commit |
| Implicit overdraft/negative magnitude | High | High | any debit operation | pure command validation + property tests |
| Read deletes linked legacy record | Critical | Medium | history, groups, restore | make reads pure; duplicate fixtures before cleanup |
| PAN/CVV retained | Critical | Existing | privacy/security | stop new use; separate authorized retention migration |
| Legacy/core double or gap after restore | High | Medium | totals/history | old backup + registry-missing + remap fixtures |
| Missing FX shown as native equivalent | High | Medium | foreign-card balance | typed incomplete/provisional provenance |
| Stale consumers after mutation | Medium | Medium | list/detail/dashboard/Dynamics | one post-commit finance event and convergence tests |
| Accessibility/localization regression | Medium | Medium | non-default users | automated key/render matrix plus manual VoiceOver gate |

## Characterization commands and results

1. `rg` trace across `Card`, `Account`, `AccountEvent`, product factory/catalog, Cashflow bridge/persistence, Finance/Dynamics, backup and tests: confirmed active legacy reads/writes/import, core-only new creation and split save boundaries.
2. `xcodebuild -project millio.xcodeproj -scheme millio -showdestinations`: succeeded; QA simulators `Millio-375-QA` and `Millio-390-QA` are available on iOS 26.5.
3. Targeted test command for `CardCatalogTests`, `AccountsCoreCashflowBridgeTests`, `AccountBalanceEngineTests`, `AccountProductFactoryTests`, `AccountsCoreBackupTests`: see final journal/result in the plan. The existing bridge suite contains and executes the explicit negative-balance characterization.

## Non-goals

- Credit-card debt/limit/grace semantics.
- Deposits, loans, investments, universal AccountsCore redesign.
- Bank API/open banking, automatic synchronization or merchant enrichment.
- PAN/CVV storage, virtual issuance, Apple Pay, rewards/cashback engine.
- FX speculation or provider-specific bank rules.
- Decorative bank-app imitation.

## Adversarial plan-review addendum — 2026-08-11

The first plan draft was directionally correct but under-specified in five material areas: currency minor-unit rounding, effective-date funds validation, true-concurrent double spend, persisted refund linkage and complete production-writer inventory. It also scheduled destructive legacy-read quarantine too late. The spec/plan now add DC-C6/C7, DC-P6, DC-F5/F6 and mandatory Phase 1Q before semantic/UI phases. This addendum changes no production finding and authorizes no schema change.
