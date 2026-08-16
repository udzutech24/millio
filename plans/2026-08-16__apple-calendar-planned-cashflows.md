# Plan: экспорт плановой операции в Apple Calendar

## Status

`PARTIALLY IMPLEMENTED` — phase 1 complete; planner UI and system editor are not implemented.

## Inputs

- Research: `../thoughts/research/2026-08-16-apple-calendar-planned-cashflows.md`
- Spec: `../specs/2026-08-16-apple-calendar-planned-cashflows.md`

## Decision

- Chosen approach: явная одноразовая передача одного planner entry в системный `EKEventEditViewController` после write-only authorization.
- Rejected alternatives: фоновый sync всех записей и молчаливая запись в default calendar.
- Rollback strategy: убрать action/service; созданные пользователем Calendar-события намеренно остаются их данными и не удаляются приложением.

## Stress-test audit (2026-08-16)

| Риск | Вердикт | Коррекция |
|---|---|---|
| all-day событие + alert 09:00 | Хрупко: точка отсчёта all-day alert и time zone не должны быть неявными. | v1 маппит план в timed event 09:00–09:15 с alert в момент старта. |
| recurring Cashflow → recurring Calendar event | Опасно: две модели recurrence и неразрешённый sync. | Экспортируется только nearest occurrence, без `EKRecurrenceRule`. |
| write-only permission + system editor | Верный least-privilege выбор, но нужен real-device proof. | До release проверить fresh grant/denial/restricted/no writable calendar; в Info.plist добавить write-only calendar usage string. |
| Продолжающееся редактирование/удаление Millio записи | Риск stale event неизбежен без event ID/sync. | До editor и после save показать односторонность; v1 не сохраняет external ID. |
| Дубль UI при double tap / async authorization | Реальная race на MainActor. | Одно state machine: `idle/requesting/presenting`; disable action до completion/dismissal. |
| Date boundary/DST/travel | Высокий риск для день-только plan. | Маппер принимает Calendar/time zone; тесты на DST, полночь и non-Gregorian system calendar. |
| Источник UI | Текущий `transactionRow` в mode `.recurring` не имеет effective next date. | Действие доступно только для `CashflowScheduledEntry` в planner, не для generic recurring list. |

## Phases

### [x] Phase 1 — domain and EventKit boundary

- Добавить изолированные `CalendarEventExportPayload`/builder и `AppleCalendarEventExporting` с адаптером EventKit.
- Маппировать `CashflowScheduledEntry` в timed event 09:00–09:15 with alert at start; без хранения event ID и без `EKRecurrenceRule`.
- Добавить calendar privacy usage description и локализованные разрешения/ошибки.
- Unit-тесты: future eligibility, title/note mapping, date/time zone/DST, denied/error state mapping и один active export state.

**Evidence:** CAL-2, CAL-3, CAL-5, CAL-7.

**Completed 2026-08-16**

- Added `Core/Calendar/AppleCalendarEventExport.swift`: pure payload/eligibility boundary, write-only EventKit authorization and unsaved `EKEvent` construction with an alert at event start.
- Added `NSCalendarsWriteOnlyAccessUsageDescription`.
- Added `AppleCalendarEventExportTests`; targeted simulator result: 7 passed, 0 failed.
- The boundary does not save an event or retain its identifier. `EKEventEditViewController` remains Phase 2 work.

### [x] Phase 2 — planner UI and system editor

- Добавить одно доступное действие в row/detail planner entry; скрыть для due/past entries.
- Представить только один `EKEventEditViewController`; дать пользователю выбрать календарь/сохранить/отменить.
- Показать односторонность экспорта до подтверждения; обработать denial/error без изменения Cashflow.
- UI/presentation tests: action availability, one-editor guard, localized/accessibility copy.

**Evidence:** CAL-1, CAL-4, CAL-5, CAL-6, CAL-7.

**Completed 2026-08-16**

- Planner rows now expose the action through a leading swipe and context menu only for a future `CashflowScheduledEntry`.
- A confirmation dialog explains that export is one-way before EventKit access is requested.
- `AppleCalendarEventEditorSheet` presents `EKEventEditViewController`; the user selects the calendar and saves or cancels. No Millio transaction is mutated by either outcome.
- Denied/restricted access is surfaced through the global toast. An actor-confined in-flight guard blocks duplicate permission/editor flows.
- Targeted simulator result after the final date-boundary fix: 5 passed, 0 failed (`iPhone Air`, iOS 26.5).

### [ ] Phase 3 — verification and audit

- Запустить новые unit-тесты и релевантный Cashflow test suite.
- Собрать iOS target и проверить на физическом iPhone: fresh permission, denied, editor cancel, saved event in a selected calendar, recurring-entry export and dark/Dynamic Type view.
- Self-audit acceptance criteria; обновить plan status/history.

**Evidence:** все CAL критерии.

## Verification

- Unit tests: new `AppleCalendarEventExport*Tests` плюс targeted Cashflow planner tests.
- Build checks: `xcodebuild` for `millio` and targeted test plan.
- Manual checks: real Calendar permission/editor scenarios listed in Phase 3.
