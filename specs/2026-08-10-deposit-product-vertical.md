# Spec: продуктовая вертикаль «Вклады»

## Problem

Millio has a first-class deposit ledger, schedule and Cashflow projection, but the product contract is incomplete. Generated estimates become factual interest by date alone, generic operations can violate deposit terms or available funds, early close is not one atomic transaction, and persisted maturity/reminder/rollover options are not executed. The current generic detail cannot honestly distinguish balance, confirmed income, estimated income and incomplete tax/FX.

## Goal

Make deposits a trustworthy product vertical over the existing AccountsCore ledger: one financial source of truth, typed actual/forecast/incomplete states, atomic deposit commands, exactly-once Cashflow projection and a dedicated progress-to-date-and-income UX.

## Financial contract

### Terms

- `principal`: opening balance plus confirmed top-ups minus confirmed withdrawals/transfers, excluding interest.
- `confirmedInterest`: persisted interest explicitly confirmed/imported by the user/provider.
- `estimatedInterest`: scheduler-derived amount not confirmed by a bank statement or user.
- `currentBalance`: principal plus confirmed balance-affecting events through `asOf`; estimated interest is included only under an explicit auto-post policy and remains visibly estimated.
- `projectedBalance(date)`: current balance plus future schedule estimates; never historical fact.
- `availableToWithdraw`: non-negative amount allowed by product terms. V1 cannot infer bank penalties or withdrawal policy not represented in metadata.
- `maturityAmount`: projected balance at `termEnd`, labelled estimate unless all components are confirmed.
- Amount signs are owned by typed commands; UI always submits positive magnitudes.

### V1 schedule policy

- Rate is a positive numeric percent (`12` = 12%).
- `.none`: simple estimate at term using the explicitly documented current ACT/365 policy.
- `.monthly`: nominal annual rate divided by 12, rounded half-up to two decimals per period.
- `.quarterly`: nominal annual rate divided by 4, rounded half-up to two decimals per period.
- Gregorian calendar and injected IANA timezone; month anniversaries clamp to the last valid day.
- These are Millio estimates, not provider-specific bank calculations. Unsupported day-count/variable-rate rules produce an explicit unsupported/incomplete state.

## Ownership

- `Account` + `DepositMeta`: product identity and terms.
- `AccountEvent`: only balance source. No parallel DepositTransaction or stored balance.
- Deposit schedule policy: produces projections with stable IDs and provenance.
- Deposit operation coordinator: sole interactive writer for top-up, withdrawal, term edit, maturity, rollover and early close.
- Cashflow bridge: one-way projection from confirmed/eligible interest into `CashflowTransaction`; it never changes account balance.
- Tax presentation: derived owner-wide read model; never a balance or Cashflow event.

## Lifecycle rules

- Creation validates name, positive opening amount, non-negative rate, `termEnd > openingDate`, payout day if supported, penalty in `0...1`, and option consistency before one atomic commit.
- Top-up is allowed only when active and `allowsTopUp`; it appends one typed positive event and regenerates only affected future estimates.
- Withdrawal is disabled unless a supported withdrawal policy is explicit. Any enabled withdrawal requires active account, positive amount and `amount <= availableToWithdraw`.
- Terms edit preserves past confirmed events, recalculates future projections only, previews the delta and commits metadata + future schedule atomically.
- Interest confirmation/upsert is idempotent by stable period/source ID. Estimated and confirmed states cannot both contribute for one period.
- Maturity produces `active`, `dueSoon`, `maturedNeedsAction`, `rolledOver`, or `closed`; no silent rollover and no silent archive.
- Rollover requires explicit supported terms and one atomic command. Existing `autoRollover` must not promise execution until this command exists.
- Early close previews lost interest, fee, net proceeds and destination; deletion of future estimates, fee, two transfer legs and archive commit together or not at all.
- Archive is read-only and preserves historical replay/group identity. Generic archive-with-balance is not a substitute for maturity/early close.

## Actual, forecast and completeness

`DepositPresentationSnapshot` is a pure typed adapter with:

- `asOf`, `currency`, `principal`, `currentBalance`;
- `confirmedInterest`, `estimatedDueInterest`, `futureInterest`;
- `nextAccrual`, `maturityDate`, `maturityAmount`, `daysRemaining`, `progress`;
- `availableToWithdraw` and capability flags;
- `lifecycleState`;
- per-value `provenance: confirmed | estimated | unavailable`;
- `unresolved: [reasonCode]` with safe, non-PII codes.

No public number may silently coerce `unavailable` to zero or raw foreign value.

## UX hierarchy

Chosen concept: **progress to date and income**.

1. Hero: current balance and currency; separate confirmed/estimated badge.
2. Progress: rate, maturity date/days or open-ended state, progress bar.
3. Income: already confirmed, estimated due, next accrual, projected maturity income.
4. Context action: top up, confirm interest, manage maturity, or early close depending on state/terms.
5. Terms: capitalization, top-up/withdrawal availability, early-close policy, Cashflow projection status.
6. Timeline: actual events and projected events rendered as distinct series/rows.
7. Tax: owner-wide estimate with year, assumptions and complete/incomplete provenance.

Required states: creation preview, normal, savings/no-term, due-soon, matured-needs-action, early-close preview, archived, zero/error/incomplete.

## Acceptance criteria

### Core and financial semantics

- [x] **AC-C1** Characterization fixtures lock current none/monthly/quarterly formulas, rounding, leap interval, 28/29/30/31, DST/timezone and same-day event ordering.
- [x] **AC-C2** One typed snapshot separates principal, confirmed interest, estimated due interest, future interest, current balance and projected maturity balance.
- [x] **AC-C3** Generated estimates cannot become confirmed historical/Cashflow income by date alone; one period cannot contribute twice.
- [x] **AC-C4** Current balance and historical balance use shared AccountEvent replay; projected balance is explicitly separate.
- [x] **AC-C5** Unsupported provider rules return typed incomplete/unsupported state, not guessed numbers.

### Persistence and atomic commands

- [x] **AC-P1** Creation validates all supported term invariants and commits Account + opening + schedule in one disposable-context save.
- [x] **AC-P2** Top-up/withdrawal commands enforce active state, positive magnitude, capabilities and sufficient available funds. Partial withdrawal is rejected as unsupported until its policy is persisted.
- [x] **AC-P3** Terms edit preserves past confirmed events and atomically updates metadata plus future projections.
- [x] **AC-P4** Early close is whole-graph atomic across future projection cleanup, penalty, transfer legs and archive, including injected failures at every stage.
- [x] **AC-P5** Maturity/rollover/close have explicit typed commands; decorative metadata is not presented as active behavior.
- [x] **AC-P6** Retry/relaunch/restore are idempotent by stable operation/period IDs.

### Cashflow

- [x] **AC-F1** One eligible interest period produces exactly one Cashflow income row with `affectsCardBalance=false`.
- [x] **AC-F2** Cashflow retry, catch-up and relaunch never duplicate rows; corrupt/duplicate source events produce typed diagnostics.
- [x] **AC-F3** Editing future terms updates projections without rewriting past Cashflow facts.
- [x] **AC-F4** No recurring Cashflow template is created for deposit interest.

### Totals, history and refresh

- [x] **AC-H1** Account detail, list, groups, dashboard, Dynamics and Cashflow agree on the same committed endpoint after every operation.
- [x] **AC-H2** Actual and projected series are visually and semantically distinct; forecast never appears as closed historical fact.
- [x] **AC-H3** Archive/delete preserve historical replay and group membership through the cutoff.
- [x] **AC-H4** Every successful outer commit publishes one appropriate finance refresh; failed operations publish none.

### Tax and FX

- [x] **AC-T1** Tax aggregates all owner deposits for one year and does not allocate a separate allowance per account.
- [x] **AC-T2** Each foreign interest event uses historical event-date FX to RUB with provenance.
- [x] **AC-T3** Missing FX/settings produce incomplete tax, never raw foreign amount labelled RUB or an exact net forecast.
- [x] **AC-T4** Copy states that tax is an estimate and exposes assumptions/year; no legal-advice claim.

### Product UI

- [x] **AC-U1** Creation shows a live estimated result and blocks invalid term/option combinations without keyboard obstruction.
- [x] **AC-U2** Dedicated deposit hero answers balance, earned/estimated interest, next accrual, maturity amount/date and required action within one screen.
- [x] **AC-U3** Actions are deposit-specific and capability-driven; generic income/expense/adjust are not exposed where they distort semantics.
- [x] **AC-U4** Terms edit previews financial impact; immutable/unsupported terms are read-only with a reason.
- [x] **AC-U5** Early-close confirmation shows lost interest, penalty, net proceeds and destination before commit.
- [x] **AC-U6** Matured and archived states are explicit; archived is read-only.

### Localization, accessibility and render

- [x] **AC-L1** Typed RU/EN/zh-Hans presentation exists; no raw keys or hard-coded product copy are visible.
- [x] **AC-L2** VoiceOver labels/values/actions, Dynamic Type, Reduce Motion and focus order pass.
- [x] **AC-L3** 375×812 and 390×844 render matrix passes all required states without clipping or hidden primary action.

### Backup, migration and observability

- [x] **AC-B1** Existing DepositMeta/Event backup round-trip and corrupt/missing-meta rejection remain green.
- [x] **AC-B2** Schema stays unchanged unless Phase 1 proves existing source IDs/meta cannot encode required lifecycle; any change is additive with old-store, export/import and rollback fixtures.
- [x] **AC-B3** Restore leaves no orphan projections/Cashflow links and can safely rebuild derived forecasts.
- [x] **AC-B4** Logs contain safe reason codes/counts only, never account names, amounts, tax values or other PII.

## Scope

AccountsCore deposit semantics, schedule provenance, deposit-specific commands, Cashflow projection, maturity/reminders, refresh, typed presentation, tax/FX completeness, backup proof, localization/accessibility/render QA.

## Non-goals

- Bank APIs, statement scraping or provider-specific calculators.
- Automatic comparison of market deposit rates.
- Tax/legal advice or silently updated statutory defaults.
- Universal rule engine for every financial product.
- Gamification, confetti or decorative charts without decision value.
- Parallel deposit ledger or recurring Cashflow template.

## Constraints and risks

- Production code starts only after the literal phase guard phrase.
- Dirty user changes in finance/real-estate/localization must be preserved.
- Current future `.interest` rows require compatibility fixtures before changing interpretation.
- Schema migration is conditional, never assumed.
- Missing bank/provider evidence must reduce certainty, not fabricate precision.
