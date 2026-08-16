# Spec: Cashflow primary screen hierarchy

## Problem

The compact Cashflow chart has proven data semantics but poor first-viewport hierarchy: it takes substantial height, expansion is visually detached, and the selected period's net result competes with a separate balance table below.

## Goal

Make the selected period's financial outcome readable at a glance, reduce avoidable chart chrome, and make transaction creation clearly primary without changing Cashflow calculation, routes, or data storage.

## Acceptance criteria

- [x] The selected period shows transaction income, expenses and their difference. Asset revaluation remains exclusively in the balance summary below.
- [x] The compact chart remains readable and consumes less vertical space than the current 200 pt presentation, while full-screen expansion remains available with a 44×44 pt target.
- [x] The date range, menu, add-transaction flow, month workspace and all existing accessibility identifiers keep working.
- [x] The primary add action is visually stronger than the month-workspace navigation action without disabling either flow.
- [x] Income/expense/asset-change/end-assets use the existing source of truth and retain current calculation semantics.
- [x] Every monetary value in the compact summary and asset card uses tabular digits, so a changing value does not horizontally jump.
- [x] Asset-card amounts share one trailing-aligned value column. Rows without an expand button reserve the same trailing control width as Income and Expenses.
- [x] Normal and accessibility-large Dynamic Type screenshot runs pass on the narrow 375 pt QA device; the regular screenshot run also passes at 390 pt.

## Scope

- `millio/UI/Services/Cashflow/CashflowView.swift`
- The existing Cashflow chart/layout test seam and screenshot UI test, only where needed for the new presentation contract.

## Non-goals

- No model, persistence, transaction, localization, entitlement, chart-geometry or navigation-route rewrite.

## Constraints and risks

- The current calculation and common chart scale are already test-backed; implementation must reuse them.
- Existing user changes under Cashflow Import/Statement views are out of scope and must not be changed.
