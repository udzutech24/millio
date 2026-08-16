# Spec: unified dashboard header

## Problem

`DashboardView` places the history, privacy and profile controls in one row and places the two mini-app actions in a separate row. The separated rows spend vertical space before the primary balance without adding hierarchy.

## Goal

Place history, Courses, Cashback, the balance-privacy control and profile in one compact, accessible dashboard header while preserving every existing navigation action.

## Acceptance criteria

- [ ] On regular-width iPhones, history, Courses, Cashback, privacy and profile appear in one visual header row.
- [ ] On narrow widths or with large Dynamic Type, the header has no clipping, overlap or horizontal scroll; mini-app labels may collapse to icons while retaining VoiceOver labels.
- [ ] History opens the existing history route; Courses and Cashback preserve their routes; privacy still masks the balance; profile opens the existing profile route.
- [ ] Every header target has a minimum 44×44 pt hit area and a stable accessibility identifier/label.
- [ ] Normal and widget-edit modes retain coherent header spacing; no change is made to widget ordering or stored dashboard preferences.

## Scope

- `millio/UI/Dashboard/DashboardView.swift` and the focused UI tests or layout-policy tests needed to cover the layout decision.

## Non-goals

- No new mini-app, navigation route, profile flow, localization copy, data model or storage migration.

## Constraints and risks

- Keeping the current text widths for both mini-app chips plus three icon controls does not fit every supported iPhone width. A responsive compact representation is required; a horizontally scrolling header is rejected because primary controls become hidden and discoverability degrades.
- Existing unrelated working-tree changes must remain untouched.
