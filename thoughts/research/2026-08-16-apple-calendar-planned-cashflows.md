# Research: Apple Calendar for planned cashflows

- Date: 2026-08-16
- Scope: export a user-selected planned Cashflow income/expense to Apple Calendar with a calendar alert.

## Evidence

- The app already creates local notifications through `UNUserNotificationCenter` in `Core/Notifications/NotificationManager.swift`; it does not import EventKit or create `EKEvent`.
- iOS deployment target is 18.6, so the available EventKit API supports `requestWriteOnlyAccessToEvents` (iOS 17+).
- `CashflowScheduledEntry` supplies a transaction, an effective scheduled date and stable display identity. `CashflowScheduledService` produces one-time planned and recurring entries.
- Persistence performs save/delete in `CashflowPersistenceService`; automatic calendar synchronisation from those paths would add cross-store consistency and deletion problems that the product has not asked to solve.

## Options considered

1. **Automatic two-way synchronisation of every planned entry.** Rejected: creates calendar spam, needs durable external event IDs, reconciliation after edits/deletes, conflict policy and access to user calendars. This is unjustified scope for v1.
2. **Direct write to a default calendar.** Rejected: surprising external mutation and poor user control over calendar selection.
3. **Explicit “Add to Calendar” for one planner entry, shown in the system event editor.** Recommended: user approves the exact event and calendar; no external IDs, background sync or destructive reconciliation are needed.

## Recommended contract

- Add the action only to future planned/recurring Cashflow entries in the scheduled planner.
- The action opens the system event editor prefilled with an all-day event, localized title/notes and one alert at 09:00 on the scheduled date. The user selects a calendar and must save it themselves.
- Request EventKit **write-only** access only after the action. Handle denied/restricted/error with an actionable in-app message; do not treat an event-editor dismissal as success.
- Use `EKEventEditViewController` rather than silently saving. v1 does not retain an event ID and never attempts update/delete/sync after the user saves.
- Do not include account/card identifiers or other unnecessary personal data in title/notes. Amount, type and optional note are enough for the user-facing event.

## Risks and mitigations

| Failure mode | Impact | Mitigation |
|---|---|---|
| Permission denied/restricted | No export | Explicit state and Settings recovery path; no failed local mutation. |
| Transaction changes after export | Stale calendar event | State it clearly in UI; v1 is a one-way copy. Synchronisation is a separate product feature. |
| Past/due entry export | Misleading event | Hide/disable action unless scheduled date is in the future. |
| Repeated taps | Duplicate drafts/events | One editor presentation at a time; user confirmation remains required. |
| Localization/VoiceOver gap | Inaccessible export | Localize strings and label the action; cover pure presentation policy with tests. |

## Relevant files/tests

- `millio/Core/Notifications/NotificationManager.swift`
- `millio/UI/Services/Cashflow/CashflowScheduledService.swift`
- `millio/UI/Services/Cashflow/CashflowScheduledTransactionsView.swift`
- `millio/UI/Services/Cashflow/CashflowViewModelTypes.swift`
- `millio/UI/Services/Cashflow/CashflowPersistenceService.swift`
- `millioTests/UI/Services/Cashflow/CashflowPlannedDatePolicyTests.swift`
