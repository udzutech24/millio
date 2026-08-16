# Cashflow: primary hero, phase 1

> Superseded on 2026-08-16: direct user clarification established that the hero shows transaction difference, while `periodTotalChange` remains in the lower balance summary. See `2026-08-16-cashflow-primary-screen-phase3.md`.

Date: 2026-08-16

## Outcome

- Unified the period selector, authoritative period result, compact income/expense summary and chart inside one elevated hero surface.
- Replaced the detached text expansion action with a 44×44 pt icon button and preserved its localized VoiceOver label.
- Reduced compact chart height from 200 to 164 pt while reserving 60 pt for labels and retaining the existing chart scale and minimum visible bar policy.
- Added a pure presentation policy and tests. The hero uses `periodTotalChange` instead of reconstructing result as income minus expense, because the latter would omit asset revaluation.

## Scope discipline

Phase 2 was intentionally not implemented: action hierarchy, the lower asset table, its trailing alignment and the smaller duplicated Result row remain unchanged.

## Verification

- Swift parse: passed.
- Focused unit/layout tests: passed on `Millio-390-QA`.
- No persistence, routing, entitlement or chart geometry changes.
