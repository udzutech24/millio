# Research: Apple Calendar for credit-card payment

- Date: 2026-08-16
- Scope: explicit export of the next credit-card payment from its detail card to Apple Calendar.

## Evidence

- `CreditCardDetailSection` already derives one `CreditCardPaymentStatus` from `CreditCardPaymentSettingsStore` and `CreditCardPaymentPolicy`; it is the screen shown by the user.
- `CreditCardPaymentPolicy` is the canonical calculator for `dueDate`, including grace-period and exact-date modes. Calendar UI must never recalculate a parallel date.
- Settings already carry `reminderHour` and `reminderMinute`; unlike the Cashflow planner export, the Calendar event must use those configured values rather than a fixed 09:00.
- Existing EventKit boundary is one-way: it requests write-only permission, builds an unsaved event and hands saving/calendar selection to `EKEventEditViewController`.

## Recommended contract

- Add a compact `calendar.badge.plus` action inside the existing “Ближайший платёж” card, after the due-date/remaining-days information.
- Only show it for a future, non-overdue payment status.
- On tap, show the one-way-export confirmation and then the same system editor already used for Cashflow planner export.
- Event starts at the credit card's configured reminder time on canonical `dueDate`, lasts 15 minutes and alerts at its start. It contains the card name and payment amount only if `monthlyPayment` exists; it must not infer a payment amount from debt.
- No EventKit ID, automatic update/delete, recurrence rule or background task in v1. Changing the card's payment settings later does not alter an event already saved by the user.

## Rejected alternatives

1. Automatically create/update an event whenever the credit card is saved: rejected because every edit can create duplicates and owning/deleting external user events requires a sync contract.
2. Export a monthly `EKRecurrenceRule`: rejected because the grace-period due date can move and the one-off exact-date mode is not recurring.
3. Derive the payment date directly in the view: rejected because it can diverge from the reminder and visible payment status.

## Risks

| Failure mode | Mitigation |
|---|---|
| Grace period/date is not configured | Keep existing unavailable card; render no export action. |
| Due date is today or overdue | Do not offer export; Calendar event would be misleading. |
| Reminder time contains invalid legacy value | Normalize/clamp in a pure builder and test it. |
| User changes due date after export | Make one-way behavior explicit before opening Apple's editor. |
| Double tap during EventKit prompt | Share the existing actor-confined in-flight guard/presentation policy. |

## Relevant files

- `millio/UI/Services/Finances/AccountsCore/CreditCardDetailSection.swift`
- `millio/Core/AccountsCore/CreditCard/CreditCardPaymentPolicy.swift`
- `millio/Core/Calendar/AppleCalendarEventExport.swift`
- `millio/UI/Shared/AppleCalendarEventEditorSheet.swift`
