# Handoff: Cashflow unified upcoming planner

- Goal: remove completed-today transactions from Upcoming and build one list-first forecast for income, expenses and deposit-interest projections.
- Current status: research/spec/plan complete; no implementation for this new feature in this task.
- Completed: reproduced exact start-of-day classification bug; audited kind-specific navigation and compact/full source mismatch; selected unified read-first architecture.
- Remaining: implement Phases 1–5 in `plans/2026-08-14__cashflow-unified-upcoming-planner.md`.
- Decisions and reasons: today is actual and tomorrow starts one-time planned because the product editor is date-only; use a new focused unified destination rather than adding optional-kind branches to the large legacy management view.
- Changed files: research/spec/plan/handoff only for this feature. Preserve existing dirty Phase 9 and AccountsCore work.
- Tests run and results: no tests required for plan-only work. Existing physical screenshot and exact code trace prove the bug.
- Risks/blockers: no blocker. Do not introduce a schema migration or fake cross-currency totals.
- Exact next action: in a new chat read `millio/AGENTS.md`, project skill, this handoff and plan; then execute the guard phrase `Реализуй фазы 1–5 по плану Cashflow unified upcoming planner` starting with failing day-boundary tests.
