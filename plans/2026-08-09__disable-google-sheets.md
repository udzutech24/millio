# Plan: temporarily disable Google Sheets in iOS

**Status:** REALIZED (2026-08-09)

## Goal

Temporarily remove Google Sheets from the app and stop all automatic/manual export work without deleting integration code or user connection metadata.

## Decision

- A single fail-closed `SheetsExportAvailability.isEnabled = false` is the product kill switch.
- Profile no longer exposes the Google Sheets entry.
- `CashflowViewModel` receives no export trigger while disabled, avoiding snapshot construction after transaction saves.
- `SheetsExportTrigger` independently checks availability before status/network work, protecting direct and stale call paths.
- Re-enable only after refresh-token encryption and Sheets workflow hardening are complete; then set the flag to `true` and restore `.googleSheets` in `ProfileMenuStructure`.

## Acceptance criteria

- [x] Google Sheets is absent from Profile settings.
- [x] Transaction saves cannot schedule Sheets export work.
- [x] Direct trigger calls perform no status or sync request while disabled.
- [x] Existing integration code and stored connection data are preserved.
- [x] Focused tests pass: 9/9, 0 failures.

## Non-goals

- Backend endpoint shutdown or token deletion/revocation.
- Encryption or Sheets workflow changes.
- Removal of source files, localization or persisted connection state.
