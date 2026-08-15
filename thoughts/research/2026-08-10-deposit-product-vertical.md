# Research: продуктовая вертикаль «Вклады»

- Date: 2026-08-10
- Scope: iOS AccountsCore deposit creation, terms, schedule, operations, replay, totals/history, Cashflow, tax/FX, backup, refresh and product UX.
- Mode: read-only production audit; only research/spec/plan/status documentation is created.
- Baseline: dirty user worktree. Existing real-estate, localization and finance UI changes were not modified.

## Executive verdict

База уже сильная: вклад — отдельный AccountsCore-продукт, баланс реплеится из `AccountEvent`, создание атомарно, проценты идемпотентно проецируются в Cashflow, meta проходит backup round-trip.

Но вертикаль ещё не пуленепробиваема. Главная проблема не в красоте UI, а в нечестной семантике: заранее сгенерированные проценты со временем автоматически становятся «фактом» и доходом Cashflow без подтверждения; generic-операции не защищают условия вклада; досрочное закрытие имеет две save-boundary. Рисовать deposit hero до исправления этих контрактов — слабая идея.

## End-to-end map

| Stage | Current owner | Evidence | Verdict |
|---|---|---|---|
| Create form | `InlineDepositCreateForm` | `millio/UI/Services/Finances/AccountsCore/InlineDepositCreateForm.swift:6-211` | Dedicated form exists; no live income/maturity preview and no persisted payout day input. |
| Mapping | `AccountsCoreAdditionBridge.depositMeta` | `.../AccountsCoreAdditionBridge.swift:234-258` | Maps rate/term/options; always writes `payoutDay: nil`. |
| Product identity | `ProductDefinitionCatalog` | `millio/Core/AccountsCore/ProductCatalog/ProductDefinitionCatalog.swift:180,290-295` | `.deposit` requires `DepositMeta`; validation does not reject term before opening, invalid payout day or contradictory options. |
| Atomic creation | `AccountProductFactory` | `.../AccountProductFactory.swift:131-207,212-252` | Account + opening + initial schedule commit in disposable context with one save. Strong. |
| Schedule | `DepositInterestScheduler` | `millio/Core/AccountsCore/DepositInterestScheduler.swift:31-56,112-170,225-270` | Idempotent generated events; future regeneration preserves past. Fixed formulas and forecast/actual ambiguity remain. |
| Persisted ledger | `AccountEvent` | `millio/Core/AccountsCore/AccountEvent.swift:4-43,99-118` | One event model. Generated future interest is stored as ordinary `.interest`; only source prefix distinguishes it. |
| Replay | `AccountBalanceEngine` | `millio/Core/AccountsCore/AccountBalanceEngine.swift:100-120` | Opening/income/transferIn/interest add; expense/transferOut/fee subtract. One current/historical balance function. |
| Operations | `AccountsCoreService` | `millio/Core/AccountsCore/AccountsCoreService.swift:153-184,526-633` | Generic income/expense/adjust/transfer; no deposit-specific available-funds/terms boundary. Early close is not one transaction. |
| Terms edit | Generic edit sheet | `.../AccountDetailSheets.swift:360-470`; `.../AccountDetailView.swift:1072-1086` | Only name/group/note/includeInTotal. `DepositMeta` cannot be edited in current UI and schedule is not regenerated from edit flow. |
| Totals/history | `AccountsTotalsService` + shared replay | `millio/Core/AccountsCore/AccountsTotalsService.swift:54-230`; `Account.swift:93-107` | Typed completeness-aware history and time-aware archive participation exist. |
| Cashflow projection | `AccountsCoreDepositCashflowBridge` | `millio/UI/Services/Cashflow/AccountsCoreDepositCashflowBridge.swift:69-174` | Due `.interest` becomes income exactly once in normal serial flow; `affectsCardBalance=false`. |
| Tax | `DepositTaxCalculator`; detail adapter | `millio/Core/AccountsCore/DepositTaxCalculator.swift:3-103`; `.../AccountDetailView.swift:428-468` | Owner-wide calculation exists; detail passes foreign amounts as RUB and labels an estimate. |
| Detail UI | `AccountDetailView` | `.../AccountDetailView.swift:176-240,385-469,835-879` | Shows balance/rate/days/forecast, but uses generic hero/actions and does not show next payout, maturity action or provenance. |
| Refresh | detail-local token + selected EventBus calls | `.../AccountDetailView.swift:1164-1200`; `FinanceViewModel.swift:793-824` | Edit/archive refresh global finance; top-up/withdraw/adjust/transfer refresh detail only. |
| Notifications | legacy `Investment` only | `millio/Core/Notifications/NotificationManager.swift:410-451`; callers only in `InvestmentViewModel.swift` | `DepositMeta.remindEnd` is not wired for AccountsCore deposits. |
| Backup | `DepositMeta.exportDict/import`; Account/Event export | `AccountMeta.swift:133-171`; `Account.swift:110-138`; `AccountEvent.swift:121-146` | Round-trip exists; importer rejects malformed required DepositMeta. |

## Evidence table

| Status | Finding | Proof |
|---|---|---|
| Already works | Deposit is a first-class AccountsCore product, not an Investment subtype. | `AccountKind.deposit`, `AccountProductType.deposit`, catalog definition at `ProductDefinitionCatalog.swift:180`. |
| Already works | Creation cannot persist Account without its initial schedule. | Disposable context and single commit at `AccountProductFactory.swift:237-247`; failure-stage tests at `AccountProductFactoryTests.swift:89-176`. |
| Already works | Serial scheduler regeneration and Cashflow sync are idempotent. | Stable source IDs at `DepositInterestScheduler.swift:21-29`; focused tests cover repeated generation/materialization. |
| Proven broken | Generated forecast becomes factual ledger/Cashflow income merely because its date passed. | Future schedule is persisted as ordinary `.interest` (`AccountProductFactory.swift:179-200`); bridge selects solely `type == .interest && date <= today` (`AccountsCoreDepositCashflowBridge.swift:131-160`). No confirmation/provenance check exists. |
| Proven broken | Early close is not atomic. | It stages deletion/fee, calls `transfer()` which saves at `AccountsCoreService.swift:632`, then `archiveAccount()` saves again at `:574,788-790`. A second-save failure can leave money transferred and the deposit active. Existing tests cover only success. |
| Proven broken | Deposit conditions cannot be edited from the current detail UI. | Generic editor exposes only common fields (`AccountDetailSheets.swift:360-470`); save calls `updateAccount` without `depositMeta` (`AccountDetailView.swift:1072-1086`). |
| Proven broken | `remindEnd`, `autoRollover` and `payoutDay` are decorative persisted fields for new-core deposits. | Repository references outside meta/form/seeder are absent; notification callers exist only in legacy `InvestmentViewModel`. Form mapping forces `payoutDay: nil`. |
| Proven broken | Generic withdrawal/transfer can violate available funds and product options. | `recordEvent` accepts `.expense` without positive/balance/deposit checks (`AccountsCoreService.swift:153-184`); `transfer` has no amount-positive or sufficient-funds guard (`:585-633`); UI only warns for forbidden top-up, not withdrawal. |
| Proven broken | Top-up/withdraw/adjust/transfer may leave list/dashboard stale. | `perform` changes only local `refreshToken` (`AccountDetailView.swift:1164-1171`); only edit/archive publish `investmentsUpdated` (`:1174-1197`). |
| Proven broken | Foreign-currency tax is numerically mislabeled as RUB. | Detail passes raw event amount into `amountRUB` (`AccountDetailView.swift:444-450`) despite calculator contract requiring historical conversion (`DepositTaxCalculator.swift:36-49`). |
| Proven broken | Maturity is display-only. | Scheduler stops at term; no command archives, transfers or rolls over. UI only appends `term_ended` (`AccountDetailView.swift:392-400`). |
| Hypothesis | Same-day timezone boundaries can change generated source keys. | Scheduler injects a calendar for dates, but `AccountEvent.dayKey(for:)` uses a formatter with current timezone (`AccountEvent.swift:99-111`). Requires an Istanbul/UTC characterization test before calling it a bug. |
| Hypothesis | Concurrent/re-entrant Cashflow materialization can duplicate rows. | SwiftData has no unique constraint and `existingKeys` is not updated inside the insertion loop. `@MainActor` serializes one process, but multi-context/restore duplication needs a fixture. |
| Missing | Bank-specific day-count convention, variable-rate periods, payout destination and partial-withdrawal policy. | `DepositMeta` has none of these typed contracts. Do not infer them. |
| Missing | Specialized deposit presentation states and render fixtures. | Deposit uses `standardHeader` and generic action strip; no dedicated deposit section type or screenshot matrix exists. |

## Financial contract audit

### Current formulas

- `.none`: one event at term, `opening × rate / 100 × days / 365`, rounded half-up to two decimals (`DepositInterestScheduler.swift:225-236`). It ignores top-ups and hard-codes 365 even across a 366-day interval.
- `.monthly`: every anniversary month, `balanceBefore × rate / 100 / 12`, rounded per event (`:238-258`).
- `.quarterly`: every three anniversary months, `balanceBefore × rate / 100 / 4`, rounded per event (`:238-258`).
- Gregorian `Calendar.date(byAdding:.month, from: Jan 31)` clamps to Feb 28, Mar 31, Apr 30 in the executed characterization snippet; month-end drift was not reproduced.
- No day-count convention is persisted. Therefore these are Millio estimates, not a claim that they reproduce a bank statement.

### Actual versus forecast

The current comment calls future schedule events a forecast, but the persistence type calls them normal interest. Once `date <= today`, the same row changes meaning without a user or provider event. That contaminates accrued interest, balance history, tax estimate and Cashflow together. The safe target is one ledger with explicit provenance:

- confirmed/manual interest is financial fact;
- scheduled interest is a projection and must never be presented as confirmed;
- without a bank API, due scheduled interest may remain `estimatedDue` until user confirmation, or be auto-posted only under an explicit user policy and still labelled estimated;
- no parallel deposit balance store and no recurring Cashflow template.

The existing `sourceTransactionID` prefix may be sufficient for a first compatibility adapter; schema change is not yet proven. A persisted status/event-type addition is conditional on Phase 1 fixtures proving the prefix cannot safely express lifecycle and backup requirements.

## Atomicity and ownership

- `AccountEvent` owns balance. Cashflow rows from the deposit bridge are projections only and must keep `affectsCardBalance=false`.
- Creation atomicity is proven. Regeneration uses one outer save but not the disposable-context boundary; save-failure rollback behavior is not covered.
- Early close atomicity is disproven by direct call tracing.
- Generic transfer is two-legged and atomically saved for the transfer itself, but it is not a deposit command and does not enforce deposit availability/terms.
- Historical membership is preserved through `archivedAt`/`deletedAt`; physical deletion is not the normal UI path.

## Tax and FX

- The calculator correctly accepts owner-wide RUB-normalized inputs and allocates one aggregate result across accounts.
- Defaults in `SettingsManager`/`DepositTaxSettings` are application assumptions, not verified legal advice. This research makes no claim that a current statutory rate is correct.
- Foreign-interest conversion is a confirmed correctness defect. Until historical FX exists for every event, the public result must be `incomplete`/unavailable, never a number with a RUB suffix.
- Forecast net income must be labelled estimate and must not reuse a current-year effective tax rate as if exact across term/year boundaries.

## UX state audit

| State | Current experience | Required direction |
|---|---|---|
| Creation | Dedicated fields, formatted amounts and options. No result preview; payout day unavailable. | Preview maturity amount/next accrual as estimate; validate term/options before save. |
| Normal term deposit | Generic balance hero + text lines + forecast card. | Dedicated hero: current principal/balance, confirmed/estimated interest, next payout and progress. |
| Savings/no-term | Label exists; rolling schedule depends on Cashflow tab loading. | Show next payout and open-ended status; horizon maintenance must not depend on visiting Cashflow. |
| Due soon | Days-left text only. | Action card with maturity date and explicit choices, without claiming automatic rollover unless implemented. |
| Matured | `term_ended`; account stays active with balance. | Typed `maturedNeedsAction` state and destination/rollover/close command. |
| Early close | Generic warning then destination picker; no monetary preview. | Show confirmed/estimated lost interest, fee, amount received and destination before commit. |
| Archived | Generic read-only behavior via hidden actions. | Dedicated archived summary with preserved event history/provenance. |
| Error/incomplete | Save logs or generic error; tax can show a false RUB number. | Typed safe reason, retry/action, no fabricated totals. |

## Risk matrix

| Risk | Severity | Probability | Blast radius | Mitigation |
|---|---|---:|---|---|
| Forecast silently becomes actual income | Critical | High | Balance, history, Cashflow, tax | Typed provenance/lifecycle adapter; characterization before migration. |
| Half-closed deposit after second save failure | Critical | Medium | Two accounts and historical ledger | One disposable-context coordinator and injected save-failure test. |
| Withdrawal/transfer creates negative deposit | High | High | Account balance, totals/history | Deposit-specific commands with positive/availability/terms validation. |
| Maturity/rollover/reminder toggles do nothing | High | High | Trust and missed user action | Remove false promises or implement lifecycle/reminder policy before shipping the toggles. |
| Foreign tax shown as RUB | High | Medium | Tax guidance/trust | Historical event-date FX or typed incomplete state. |
| Global UI stale after operation | Medium | High | Lists, dashboard, groups, dynamics | One finance mutation event after successful outer commit. |
| Calendar/day-key boundary | High | Unknown | Duplicates/missing interest | Injected timezone/day-key policy and DST/month-end tests. |
| Large account/event fetch in bridge | Low now | Medium later | Cashflow load performance | Measure first; batch/index only after evidence. |

## Architecture alternatives

1. **UI-only redesign over current writers.** Complexity S/M, immediate visual gain. Rejected: preserves false actual/forecast semantics, negative balances and non-atomic close.
2. **New Deposit/DepositTransaction store.** Complexity L/XL. Rejected: duplicates Account/AccountEvent, totals, history, backup and Cashflow; violates KISS and creates reconciliation debt.
3. **Chosen: deposit-specific contract and commands over existing Account/AccountEvent.** Complexity L but phased. Add pure presentation/financial policy, one atomic coordinator, exactly-once Cashflow projection and specialized UI. Use existing source IDs/meta where sufficient; schema only for a proven lifecycle gap.

## UX alternatives

1. **Rate-first calculator.** Strong marketing visual, low complexity, weak daily utility and encourages unverifiable yield promises. Rejected.
2. **Chosen: progress to date and income.** Hero answers balance, earned/estimated, next payout, maturity amount and days; actions are contextual. High trust and daily clarity, medium complexity.
3. **Timeline/ledger-first.** Excellent auditability, weak 5-second comprehension. Keep as history drill-down, not primary hero.

## Recommendation

Keep AccountsCore as the only ledger. First harden financial semantics and lifecycle, then build the progress hero. The first value slice after characterization is a `DepositOperationCoordinator` that atomically handles validated top-up, withdrawal, early close and maturity, emits one refresh event, and never creates a second Cashflow balance effect. In parallel, introduce a pure typed snapshot that distinguishes confirmed, estimated and incomplete values. Do not implement auto-rollover, payout destination or a schema change until their exact persisted contract is approved.

## Characterization commands and results

1. Calendar probe:
   - Command: Foundation Gregorian UTC `date(byAdding:.month)` from 2025-01-31 and day count 2023-07-01 → 2024-07-01.
   - Result: Feb 28, Mar 31, Apr 30, May 31; interval is 366 days. Month-end clamping works; fixed `/365` behavior remains explicit.
2. Focused XCTest/Swift Testing gate:
   - Command: `xcodebuild test ... -only-testing:millioTests/DepositInterestSchedulerTests -only-testing:millioTests/DepositTaxCalculatorTests -only-testing:millioTests/AccountsCoreDepositCashflowBridgeTests -only-testing:millioTests/AccountProductFactoryTests -only-testing:millioTests/AccountsCoreBackupTests -only-testing:millioTests/AccountsCoreServiceTests CODE_SIGNING_ALLOWED=NO` on `Millio-375-QA`.
   - Result: `** TEST SUCCEEDED **` in 30.554 seconds; xcresult: `/Users/alekseya/Library/Developer/Xcode/DerivedData/millio-dmfikblrgtwcwqclmgpmluqjyynl/Logs/Test/Test-millio-2026.08.10_17-32-16-+0300.xcresult`. Existing suites characterize happy-path schedule, serial idempotency, creation rollback, backup and successful early close; they do not cover the proven failure modes above.

## Non-goals and deferred persisted gaps

- No bank API, statement ingestion or automatic market-rate comparison.
- No legal/tax advice and no hard-coded claim of current law.
- No provider-specific compounding/day-count emulation without explicit product selection.
- No gamification/confetti.
- No second ledger or recurring Cashflow template.
- Deferred pending Phase 1 evidence: day-count convention, variable-rate periods, payout destination, partial-withdrawal policy, interest confirmation state and rollover terms.

## Phase 1 decision record — 2026-08-10

**Decision: schema unchanged.** The existing ledger can express the next phases without a migration:

- scheduler estimates are already identifiable by the stable `deposit-interest:<accountID>:<dayKey>` provenance prefix;
- confirmed/manual/provider interest can remain an `AccountEvent(.interest)` with a non-scheduler source ID;
- lifecycle is derivable from `termEnd`, `archivedAt` and explicit idempotent command events/IDs;
- `DepositMeta` already persists the current term flags and survives round-trip backup;
- the proven failures are reader/writer policy and transaction-boundary failures, not missing storage columns.

| Current behavior | Classification | Phase consequence |
|---|---|---|
| None/monthly/quarterly math, half-up period rounding, ACT/365, Gregorian anniversary clamping | Desired V1 compatibility | Preserve in Phase 2 and label as Millio estimate. |
| Stable generated source IDs; serial and serial multi-context Cashflow deduplication | Desired, incomplete under true concurrency | Preserve; add an atomic claim/upsert strategy in Phase 4 without assuming a SwiftData unique attribute. |
| `dayKey` captures process timezone at creation | Compatibility debt | Phase 2 owns an injected deposit calendar policy; persisted historical keys are not rewritten. |
| Future generated interest becomes accrued and Cashflow fact by date alone | Bug | Phase 2 separates estimated/confirmed; Phase 4 projects only eligible facts. |
| Negative expense and oversized transfer are accepted | Bug | Phase 3 typed commands reject non-positive/insufficient amounts and generic UI stops routing deposit writes. |
| Early close bypasses the injected save boundary and commits transfer/archive in separate saves | Bug | Phase 3 introduces one disposable-context outer commit and a real per-stage failure matrix. |
| `payoutDay`, `remindEnd`, `autoRollover` do not change scheduling/lifecycle | Compatibility debt presented as capability | Hide/label inert behavior until Phase 6 implements explicit commands. |
| Corrupt required DepositMeta restores the Account with `depositMeta == nil` | Compatibility debt | Phase 2 must return typed incomplete state; Phase 8 decides whether restore diagnostics need strengthening. |

Phase 1 evidence lives in `DepositProductVerticalCharacterizationTests`, the existing deterministic replay test in `AccountBalanceEngineTests`, and the serial multi-context fixture in `AccountsCoreDepositCashflowBridgeTests`. True simultaneous two-context insertion is not claimed safe: there is no database uniqueness constraint, so it remains an explicit Phase 4 concurrency risk rather than a fabricated green guarantee.

Focused gate: `** TEST SUCCEEDED **` in 28.506 seconds; xcresult: `/Users/alekseya/Library/Developer/Xcode/DerivedData/millio-dmfikblrgtwcwqclmgpmluqjyynl/Logs/Test/Test-millio-2026.08.10_18-24-27-+0300.xcresult`.

## Phase 2 implementation record — 2026-08-10

- `DepositCalendarPolicy` makes Gregorian timezone, day keys, day count and month anniversaries explicit without rewriting persisted historical keys.
- `DepositFinancialContract` is a fetch-free read policy over supplied `DepositMeta` and `AccountEvent` values. It reuses `AccountBalanceEngine` for confirmed current balance and uses a separate projection event set for maturity.
- Generated `deposit-interest:` rows remain `estimated` even after their date. A confirmed non-generated interest row on the same injected-calendar day suppresses that estimate, preventing double contribution in the typed snapshot.
- Missing metadata, non-positive rate, invalid term/currency/interest, unsupported day count or variable-rate rules produce `unavailable` values and safe reason codes rather than zero.
- Partial withdrawal remains unavailable because current metadata does not define it. Reminder and auto-rollover capabilities remain explicitly non-operational.
- No persistence, writer, UI or Cashflow route changed. Consequently the Cashflow half of AC-C3 is deliberately still open for Phase 4.

Final focused gate: **48/48 passed** in 24.626 seconds; xcresult: `/Users/alekseya/Library/Developer/Xcode/DerivedData/millio-dmfikblrgtwcwqclmgpmluqjyynl/Logs/Test/Test-millio-2026.08.10_18-53-22-+0300.xcresult`.

## Phase 3 implementation record — 2026-08-10

- `DepositOperationCoordinator` is the typed write boundary. Every command uses a disposable `ModelContext`, disables autosave and crosses `AccountsCoreSaveBoundary` once.
- Top-up validates magnitude, active state, currency, source capability and available funds. Partial withdrawal remains a typed refusal because `DepositMeta` has no withdrawal policy; silently inventing one would corrupt financial semantics.
- Interest confirmation replaces the generated estimate for the same calendar period. Term edits retain confirmed history and regenerate only future estimates.
- Early close calculates its penalty from confirmed interest only, writes both transfer legs, removes future projections and archives the deposit in one commit. Maturity and rollover are explicit commands rather than decorative flags.
- Stable operation IDs make retries observationally idempotent and detect conflicting reuse. Injected failures at every exposed stage leave the persisted graph unchanged; a later unrelated save cannot resurrect discarded mutations.
- Product creation now rejects invalid deposit terms before inserting any graph nodes. No schema migration was required.
- The old UI and Cashflow bridge are intentionally not routed through the coordinator in this phase. Phase 4 owns exactly-once Cashflow projection and the post-commit refresh boundary, so AC-C3 remains open.

Final expanded gate: **71/71 passed** across the Phase 3 coordinator, product factory, financial contract, characterization, scheduler, service and backup suites; xcresult: `/Users/alekseya/Library/Developer/Xcode/DerivedData/millio-dmfikblrgtwcwqclmgpmluqjyynl/Logs/Test/Test-millio-2026.08.10_20-18-30-+0300.xcresult`.

## Phase 4 implementation record — 2026-08-10

- The old bridge behavior was proven wrong: it promoted every due scheduler estimate to historical Cashflow income solely by date. `DepositCashflowProjector` now excludes the `deposit-interest:<account>:<period>` namespace unconditionally.
- A confirmed interest command inserts its `AccountEvent` and non-balance-affecting `CashflowTransaction` in the same disposable context and the same outer save. Retry observes the stable source ID and creates neither a duplicate row nor a second refresh.
- Catch-up remains available for confirmed legacy/provider events. Missing source IDs, duplicate source events and duplicate projected rows are reported as typed diagnostics instead of being guessed or multiplied.
- Deposit interest rows always use `recurrenceRule = none`; no recurring-template fallback exists.
- One `FinanceEvent.depositOperationCommitted` is emitted only after a successful outer save. Finance accounts/groups/dashboard, Cashflow and Dynamics consume that same endpoint. Failed saves and already-persisted retries publish nothing.
- SwiftData still has no cross-device unique constraint for `importReferenceKey`. The implementation guarantees atomic coordinator writes and serial in-process/multi-context idempotency; it does not fabricate a global CloudKit exactly-once claim. Duplicate rows arriving from external merge are diagnosed rather than silently counted.

Final expanded gate: **97/97 passed** across projection, coordinator, bridge, financial contract, characterization, scheduler, Finance/Cashflow integration, service and backup suites; xcresult: `/Users/alekseya/Library/Developer/Xcode/DerivedData/millio-dmfikblrgtwcwqclmgpmluqjyynl/Logs/Test/Test-millio-2026.08.10_20-42-26-+0300.xcresult`.

## Relevant files/tests

- Core: `Account.swift`, `AccountEvent.swift`, `AccountMeta.swift`, `AccountBalanceEngine.swift`, `AccountsCoreService.swift`, `DepositInterestScheduler.swift`, `DepositTaxCalculator.swift`.
- Product: `ProductDefinitionCatalog.swift`, `AccountProductFactory.swift`.
- UI: `InlineDepositCreateForm.swift`, `AccountDetailView.swift`, `AccountDetailSheets.swift`.
- Cashflow: `AccountsCoreDepositCashflowBridge.swift`, `CashflowUpcomingSectionBuilder.swift`.
- Tests: `DepositInterestSchedulerTests`, `DepositTaxCalculatorTests`, `AccountsCoreDepositCashflowBridgeTests`, `AccountProductFactoryTests`, `AccountsCoreServiceTests`, `AccountsCoreBackupTests`.
