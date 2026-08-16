# Plan: Cashflow and Cashback icon colors

**Status:** IMPLEMENTED — Phase 1 completed on 2026-08-15.

## Decision

- Cashflow's bottom-tab icon uses its existing purple service accent in both states, subdued when inactive; its label keeps the established selected/unselected navigation colors.
- Cashback's dashboard mini-app icon and border use a local mint accent. The global `cashbackGradient` remains blue because it styles the Cashback service itself and is outside this request.
- Rejected: changing `AppColors.cashbackGradient`, which would recolor unrelated Cashback screens.

## Phase 1

- [x] Apply local Cashback dashboard accent and Cashflow active-tab icon accent.
- [x] Inspect focused diff; run `git diff --check` and Swift parser validation for the three changed files.
- [x] Attempt iOS build; blocked before the changed views by existing compile errors in `Core/Backend/BackendAvailability.swift` (unrelated to this change).
