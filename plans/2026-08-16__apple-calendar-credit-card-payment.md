# Plan: экспорт ближайшего платежа кредитки в Apple Calendar

## Status

`PARTIALLY IMPLEMENTED` — phase 1 complete; the detail-card action and editor are pending.

## Inputs

- Research: `../thoughts/research/2026-08-16-apple-calendar-credit-card-payment.md`
- Spec: `../specs/2026-08-16-apple-calendar-credit-card-payment.md`
- Reused boundary: `../plans/2026-08-16__apple-calendar-planned-cashflows.md`

## Decision

- Reuse the approved write-only EventKit/system-editor boundary; do not create a second calendar permission flow.
- Add a narrow credit-card payment payload builder backed by `CreditCardPaymentPolicy`.
- Keep an explicit user action in the payment card. No external IDs or sync.
- Rollback: remove the action and builder. Existing user-owned Calendar events remain untouched.

## Phases

### [x] Phase 1 — payment export contract and tests

- Add pure `CreditCardCalendarPaymentExport` builder that consumes canonical `CreditCardPaymentStatus`, card metadata and stored payment settings.
- Reuse EventKit payload but extend its builder to accept a validated explicit hour/minute; retain Cashflow's 09:00 policy through its caller.
- Unit tests for grace/exact date alignment, future/overdue eligibility, legacy time normalization, title/amount privacy and no inferred monthly payment.

**Evidence:** CC-CAL-2, CC-CAL-3, CC-CAL-4, CC-CAL-7.

**Completed 2026-08-16**

- Added `CreditCardCalendarPaymentExport`, which accepts only the canonical `CreditCardPaymentStatus` and stored `CreditCardPaymentSettings`.
- `AppleCalendarEventExportPayloadBuilder` now accepts a caller-owned hour/minute and clamps invalid persisted values; the existing Cashflow caller retains its default 09:00.
- A Calendar note is emitted only when `CardMeta.minPayment` is explicitly present. Outstanding debt and limit cannot become a fabricated payment amount.
- Targeted test result: 7 passed, 0 failed on iPhone Air simulator.

### [x] Phase 2 — detail-card action and system editor

- Add a compact labelled calendar button in `CreditCardDetailSection` within the «Ближайший платёж» card.
- Reuse one-way confirmation, authorization state and `AppleCalendarEventEditorSheet`; action is hidden for no status/today/overdue status.
- Ensure saved/cancelled/denied outcomes cannot write any `Account`, `CardMeta` or payment settings.
- Add accessibility label and localized copy.

**Evidence:** CC-CAL-1, CC-CAL-5, CC-CAL-6, CC-CAL-7.

**Completed 2026-08-16**

- `CreditCardDetailSection` now shows an accessible “Add to Calendar” button inside the future-payment card.
- The button opens a one-way confirmation, requests write-only access only after confirmation and presents the shared system editor.
- Today/overdue/unconfigured payments expose no action; deny/restrict/cancel paths leave `Account`, `CardMeta` and payment settings unchanged.
- Targeted build/test result: 7 passed, 0 failed on iPhone Air simulator. Physical-device permission/editor QA remains Phase 3.

### [ ] Phase 3 — verification

- Run targeted CreditCard payment policy and Calendar export tests plus iOS build.
- On a physical iPhone check permission fresh/denied, calendar selection, cancel, save, exact date, grace period and payment date changed after export.
- Audit every acceptance criterion; update plan/status/history.

**Evidence:** all CC-CAL criteria.
