# Handoff: statement review plan Phase 0

- Implementation completed: Cashflow information architecture and route ownership before statement-import redesign. The phase gate remains open only for manual VoiceOver/Dynamic Type screenshot acceptance.
- Root `CashflowView` is the only dashboard. `CashflowMonthWorkspaceView` is a thin month operations screen with month selector, type totals/list, lifecycle status, closure action and sibling Add/Import actions.
- Removed the cyclic Month → Analytics → `CashflowView` route and the child overflow. Root overflow owns only display currency.
- Route ownership is encoded in `CashflowNavigationPolicy`; tests prove unique owners and an acyclic graph.
- Add and Import share `CashflowMonthScopePolicy`. `.specificMonth` yields one canonical month; every other period requires explicit picker confirmation and never consumes stale `selectedMonth`.
- Unified Entry now accepts `initialMonth`; this fixed a proven gap where category entry initialized from `Date()` despite caller month context. Global FAB callers retain current-month behavior through the optional default.
- Closed months keep both actions visible, disabled, and accompanied by one visible/readable explanation. A close-race is also checked immediately before presenting Add/Import from an explicitly selected month.
- Focused tests passed: `CashflowMenuRoutingTests`, `CashflowMonthWorkspacePresentationTests`, `CashflowCategorySheetBootstrapTests`.
- Cashflow regression suites executed explicitly by suite name. Two unique failures reproduce in isolation with parallel testing disabled and are outside this phase/inside the pre-existing dirty baseline: `FinanceLifecycleIntegrationTests.duplicateCardsStayConsistentAcrossModules()` and `CashflowHistoricalPortfolioCutoverTests.unresolvedLegacyFailsClosed()`.
- Build gates passed: compact simulator tests; iPhone 17 Pro simulator build; signed physical-device build for connected iPhone 17 Pro Max (`70B4BF5E-1A5B-5010-9C59-4E13F9B48FF4`). App was not installed/launched and no financial data was touched.
- Accessibility audit: controls use labels/hints, 44–48 pt targets, wrapping/scaling and a visible closed-month explanation. Manual VoiceOver and largest Dynamic Type traversal remains a human/device acceptance item; no unsupported claim was made.
- No backend files, financial records, commits, pushes or remote resources were changed.
- Next action requires explicit authorization: `Реализуй фазу 1 по плану`.

## Dirty-worktree ownership

Baseline was captured at branch `agent/accounts-history-source-of-truth`, HEAD `157bde6cb4f8abefc3061cfb9bb6ef320d30e840`. Pre-existing AccountsCore, Finances, schema, localization and Cashflow/import changes were preserved. Phase 0 intentionally overlaps only the already modified Cashflow navigation files and adds narrow policy/tests/documentation.
