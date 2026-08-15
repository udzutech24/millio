# Spec: продуктовая вертикаль «Дебетовые и банковские карты»

## Problem

AccountsCore already provides the right ledger, but debit cards are exposed through generic account operations that do not enforce funds, magnitude, refund, fee, adjustment or whole-graph Cashflow semantics. Legacy `Card` remains an active compatibility store with unsafe destructive reads and sensitive fields. A visual redesign alone would preserve financial defects.

## Goal

Deliver a debit-card vertical whose actual balance, operations, history, totals, Cashflow and refresh all derive from one AccountsCore financial contract, with no second ledger and no unproven schema migration.

## Financial contract

- Canonical balance is the user's own available funds in the account currency.
- `balance(at:) = opening + income - expense + transferIn - transferOut - fee + valid adjustment`.
- Opening, income, expense, transfer and fee commands accept positive magnitudes; sign is owned by the typed command/event.
- Default overdraft policy is **forbidden**: opening and post-operation balance must be `>= 0`. A future overdraft requires a separate persisted/product contract and is not inferred from negative data.
- Expense reduces balance; income increases it.
- Transfer between the user's accounts creates two linked legs, changes no Cashflow income/expense total, and is atomic.
- Fee is a typed debit event and one Cashflow expense projection.
- Refund links an original expense, cannot exceed its remaining refundable amount, and corrects that expense; it is not ordinary income.
- Adjustment is a typed audit operation with required reason and explicit before/after/delta; it is not presented as income/expense.
- One operation affects Account balance exactly once. Cashflow is classification/projection and never a second balance effect.
- `includeInTotal=false` excludes current and historical portfolio totals while retaining list access and event history.
- Archive is read-only from its effective timestamp and retains replay, links and historical group membership.
- Current and historical values use the same event contract and stable ordering.
- Every amount is normalized once at the command boundary using an explicit ISO-4217/minor-unit policy; intermediate FX math uses `Decimal`, and the persisted debit/credit legs specify where rounding remainder is assigned.
- Sufficient funds are evaluated at the operation effective timestamp inside the same transaction that commits the operation. Two concurrent withdrawals cannot both spend the same funds.

## Ownership and persistence

- `Account` owns identity, currency, display fields, membership, archive state and optional `CardMeta`.
- `AccountEvent` is the only balance ledger.
- `CashflowTransaction` owns income/expense/transfer classification, linked exactly once by a stable operation/source ID.
- `DebitCardFinancialContract` and `DebitCardPresentationSnapshot` are pure derived models and persist nothing.
- A single `DebitCardOperationCoordinator` owns validation, staging of all linked rows, one isolated-context commit, rollback and one post-commit refresh publication.
- Legacy `Card` is compatibility input only. It must not be written by new creation/operation UI and must not mutate during fetch.
- No new schema field is allowed until Phase 1 proves existing IDs/meta/events cannot encode a required invariant.

## Commands

| Command | Event/projection | Validation | Result |
|---|---|---|---|
| Create | Account + opening event | name, ISO currency, opening `>= 0`, debit meta has no limit, last4 empty or four digits | one durable graph |
| Expense | `.expense` + expense Cashflow | active, amount `> 0`, sufficient funds | balance decreases once |
| Income | `.income` + income Cashflow | active, amount `> 0` | balance increases once |
| Transfer | linked out/in; transfer Cashflow | both active, distinct, amount `> 0`, sufficient funds, explicit FX if needed | zero income/expense |
| Fee | `.fee` + fee expense | active, amount `> 0`, sufficient funds, typed category/reason | balance decreases once |
| Refund | typed correction/link to original expense | original exists, same card/currency, positive remaining cap | original expense net decreases |
| Adjust | `.adjustment` delta | active, target `>= 0`, required reason | auditable correction only |
| Archive | archived timestamp | explicit warning when balance `> 0`; optional transfer-first | history retained, writes disabled |

Retry with the same operation ID and identical payload is a no-op returning the original graph. Reuse with different payload is a typed conflict. Any staging/save failure leaves zero partial rows and publishes no refresh.

## Create/edit policy

- First-value fields: name, currency, opening balance.
- Useful optional fields: bank/issuer, last4 only when user opts in, icon/color, comment, includeInTotal, group.
- Favorite may be offered only as display ordering; it is not financial metadata and need not block v1.
- Deferred/forbidden: expiry, cardholder name, PAN, CVV, credentials, credit limit/statement/due/grace, investment/deposit controls.
- Edit may change name, issuer, optional last4, icon/color, note, favorite/order, group and includeInTotal.
- Currency is immutable after any event; v1 keeps it immutable even for pristine accounts unless the approved product transition contract handles replacement.
- Balance changes only through typed operations/adjustment.
- Product-type changes use the approved transition policy; no field flip.
- Archived cards are read-only.

## Actual and converted values

- `actualBalance` is exact account-currency replay at the requested instant.
- `convertedTotalContribution` is separate and carries target currency, rate date/source and exact/provisional/unavailable state.
- Missing FX never displays raw native amount as if converted and never silently contributes a complete total.
- Detail hero prioritizes actual balance; converted contribution is secondary and explicitly labelled.

## Typed presentation API

```text
DebitCardPresentationSnapshot
  identity: accountID, name, issuer?, last4?, icon, color
  lifecycle: active | archived(effectiveAt)
  actualBalance: amount, currency, asOf
  convertedContribution: exact | provisional | unavailable(reasonCode)
  membership: included | excluded
  capabilities: expense, income, transfer, fee, refund, adjust, edit, archive
  recentActivity: [DebitCardActivityItem]
  completeness: complete | incomplete([safeReasonCode]) | error(safeReasonCode)
```

No localized strings, raw persistence errors, account names or amounts appear in diagnostic reason codes/logs.

## UX hierarchy

- Creation: name → currency/opening balance → optional issuer/last4 → include/group → note/icon; live validation; keyboard-safe primary action.
- List: name/issuer, actual balance and currency, favorite/excluded/archived badges; deterministic grouping/sort.
- Detail: actual-balance hero; quick Expense/Income/Transfer; recent activity; view-all history; secondary metadata and converted provenance.
- Edit: display metadata and membership only; no balance/currency mutation.
- Operations: typed sheets with resulting balance preview and categorized errors.
- History: event-derived activity; refunds and fees clearly typed; transfers paired; adjustments visually distinct.
- Archive: warn on non-zero balance, offer transfer-first, preserve read-only history.
- Error/incomplete: never fabricate values; keep safe read-only metadata and recovery action.

## Acceptance criteria

### Core

- [x] **DC-C1** One pure contract implements the stated replay equation for every supported date with deterministic same-time ordering.
- [x] **DC-C2** Positive-magnitude commands own signs; zero/negative magnitudes are rejected before mutation.
- [x] **DC-C3** Opening and every resulting debit balance are non-negative; overdraft is unavailable without a separate approved contract.
- [x] **DC-C4** Fee, refund and adjustment have typed semantics; refund cannot exceed remaining original expense.
- [x] **DC-C5** Retry/relaunch with a stable operation ID is idempotent; conflicting reuse is rejected.
- [x] **DC-C6** Currency-aware Decimal rounding is deterministic for zero-, two- and three-minor-unit currencies, FX transfers and refunds; replay never accumulates binary-Double drift.
- [x] **DC-C7** Funds validation uses balance at the operation effective timestamp and defines future/backdated behavior explicitly.

### Persistence

- [x] **DC-P1** Create writes Account + opening + metadata with one isolated-context commit.
- [x] **DC-P2** Expense/income/transfer/fee/refund/adjust/archive each have one whole-graph commit and complete rollback on every staged failure.
- [x] **DC-P3** Currency cannot be edited after creation; product type changes only through transition policy.
- [x] **DC-P4** Archived/deleted accounts reject every financial writer while retaining events.
- [x] **DC-P5** Duplicate source/operation IDs converge to one graph across retry, relaunch and serial multi-context execution.
- [x] **DC-P6** True concurrent same-account withdrawals/fees/transfers serialize or conflict so the committed balance never violates the non-negative invariant.

### Cashflow

- [x] **DC-F1** One eligible debit operation produces exactly one Cashflow projection and one Account balance effect.
- [x] **DC-F2** Transfer never contributes to Cashflow income/expense.
- [x] **DC-F3** Refund corrects the original expense instead of creating ordinary income.
- [x] **DC-F4** Failed bridge/projection/save leaves neither orphan event nor transaction; no error is swallowed into divergence.
- [x] **DC-F5** Refund-to-original linkage survives relaunch and backup/restore without parsing notes or overloading category IDs; Phase 1 explicitly proves whether existing Cashflow linkage is sufficient or an additive persisted field is required.
- [x] **DC-F6** Every production debit writer (detail, Cashflow create/edit/delete, recurring, import, quick edit and migration tools) is inventoried and either routes through the coordinator or is explicitly read-only/quarantined.

### Totals, history and groups

- [x] **DC-H1** List, detail, group, dashboard, Dynamics and current total agree on the same actual endpoint.
- [x] **DC-H2** Historical replay equals the same contract at every event boundary; later display metadata edits do not change past balances.
- [x] **DC-H3** `includeInTotal=false` excludes current/history totals but preserves visibility and history.
- [x] **DC-H4** Archive preserves pre-cutoff replay, event links and historical group membership.

### UI

- [x] **DC-U1** Creation exposes only debit-relevant fields and blocks invalid opening/last4 without keyboard obstruction.
- [x] **DC-U2** Detail's hero is actual balance; converted value/provenance is distinct and secondary.
- [x] **DC-U3** Expense, income and transfer are immediate capability-driven actions; fee/refund/adjust are explicit typed flows.
- [x] **DC-U4** Recent/no-activity, zero, excluded, favorite, archived, corrupt/incomplete and save/refresh error states are explicit.
- [x] **DC-U5** Non-zero archive confirmation explains the historical/totals effect and offers transfer-first.

### Localization/accessibility

- [x] **DC-L1** Typed RU/EN/zh-Hans copy has no raw keys or dynamic namespace leakage.
- [x] **DC-L2** VoiceOver labels/values/actions, focus order, Dynamic Type and Reduce Motion pass.
- [x] **DC-L3** 375×812 and 390×844 light/dark render matrix passes all required states with accessible contrast.

### Backup/migration

- [x] **DC-B1** Account/CardMeta/Event/source IDs and links round-trip; corrupt/missing meta and duplicate IDs fail safely or produce typed incomplete state.
- [x] **DC-B2** Legacy duplicate fetch is read-only; no row or relationship is deleted during read.
- [x] **DC-B3** Old backup restore leaves no orphan events/Cashflow/group links and preserves predecessor history.
- [x] **DC-B4** Schema remains unchanged unless characterization proves a persisted gap; any migration is additive with old-store/import/rollback fixtures.
- [x] **DC-B5** Legacy PAN/CVV retention is handled only by a separately authorized security migration; new debit paths never write it.

### Refresh/security

- [x] **DC-R1** One post-commit event refreshes detail/list/groups/totals/dashboard/Dynamics/Cashflow without relaunch; failed writes publish nothing.
- [x] **DC-S1** No PAN, CVV, credentials or bank token is accepted, stored or logged by new debit paths; last4 is optional and validated.
- [x] **DC-S2** Logs contain safe category/reason/operation codes only, never names, last4, amounts, notes, IDs or raw persistence payloads.

## Non-goals

Credit cards; deposits; open banking; automatic statement sync; PAN/CVV; card issuance; Apple Pay; rewards/cashback engine; merchant enrichment; universal AccountsCore rewrite; decorative plastic-card simulation.
