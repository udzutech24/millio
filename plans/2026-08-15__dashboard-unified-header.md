# Plan: unified dashboard header (superseded)

**Status:** SUPERSEDED — user narrowed scope on 2026-08-15 to Cashflow and Cashback icon colors only. No header-layout implementation was performed.

## Inputs

- Research: visual inspection of the supplied dashboard screenshot and `millio/UI/Dashboard/DashboardView.swift`.
- Spec: `specs/2026-08-15-dashboard-unified-header.md`.

## Decision

- Chosen approach: replace the separate `topActionButtons` and `miniAppsSection` placement in normal mode with one responsive header component. It presents two labelled mini-app chips where space allows and collapses them to icon controls below the determined width / accessibility size. History stays leading; privacy and profile stay trailing.
- Rejected alternatives: keep two rows (wastes prominent above-the-fold space); force every full label into one row (clips on narrow iPhones and Dynamic Type); horizontal scrolling (hides important controls).
- Rollback strategy: restore the existing composition of `topActionButtons` followed by `miniAppsSection`; no persistent data or route contract changes.

## Phases

- [ ] **Phase 1 — responsive unified header**
  - Extract the existing five actions into one local dashboard-header composition; preserve callbacks and identifiers.
  - Use `ViewThatFits` or an equivalent native SwiftUI layout to select labelled chips only when they fit, otherwise icon variants with explicit accessibility labels.
  - Preserve 44×44 pt hit targets and a stable profile accessibility identifier.
  - Keep the mini-app row in edit mode only if needed for widget-edit context; otherwise reuse the same header intentionally.
  - Add focused tests for the layout-policy decision and existing route/action identifiers; update screenshots only after verified simulator capture.

## Verification

- Unit tests: focused layout-policy tests for regular/narrow accessibility widths and existing callback exposure where testable.
- Integration/build checks: focused `millioTests` dashboard suite and iOS simulator build; inspect the dashboard at normal and accessibility Dynamic Type.
- Acceptance criteria audit: record evidence against every item in `specs/2026-08-15-dashboard-unified-header.md` before marking the phase complete.

## Change log

- 2026-08-15 — created; awaiting explicit authorization: `Реализуй фазу 1 по плану`.
