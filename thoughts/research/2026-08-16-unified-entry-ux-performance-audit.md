# Unified Entry: UX/performance audit

Date: 2026-08-16
Scope: `CashflowUnifiedEntryContainer` and `CashflowCategoryTransactionSheet`

## Outcome

The screen is overloaded because it combines four jobs in one scrolling surface:

1. choose operation type;
2. inspect the month summary and budget;
3. manage/import/search/reorder categories;
4. create an operation by tapping a category.

The visual weight follows that architectural overload: almost every group has its own stroke, nested card, or large control. The user has to decode controls before reaching the primary task.

The reported tab-switch lag has a credible code-level cause. It still needs an Instruments signpost/profile before implementation claims a measured improvement.

## Evidence

### P0 — History and "paid" state are not discoverable

- Completed operations are accessible through an unlabeled clock icon in the header. The icon's meaning is ambiguous and there is no visible `History` affordance.
- The previous browse-history tab was intentionally removed from `CashflowUnifiedEntryContainer`; the comment says history moved to the main Cashflow screen. The current sheet nevertheless retains a hidden icon route, creating split ownership rather than a clear product rule.
- Planned/recurring management exposes templates and future schedule entries. There is no status filter (`Upcoming / Paid / All`) in `CashflowScheduledTransactionsView`, so a user looking for completed scheduled payments cannot recover that history there.
- Putting paid rows permanently at the bottom is weak: long future lists still bury them. The robust interaction is a visible status filter with `Upcoming` as default and `Paid`/`All` as explicit choices; within `All`, completed items form a collapsed section below active items.

### P0 — Switching tabs repeats expensive work

- `CashflowUnifiedEntryContainer` embeds expense, income, and transfer screens simultaneously inside a paging `TabView`.
- Both category sheets call `reloadMonthlyTotal()` from `onAppear`.
- Each reload awaits total, category totals, and budget summary sequentially.
- `monthlyBudgetSummary` calls `monthlyCategoryTotals` again when a plan exists. Thus a sheet with a budget traverses and converts the same month's transactions at least three times: total, category totals, category totals for budget.
- Conversion happens transaction by transaction in async loops. Income and expense pages can perform this work while the user only needs one page.
- The tab change is animated by the button's `withAnimation`, the page `TabView`, the container `.animation`, and per-button animations. This multiplies transition work and makes dropped frames more visible.

Required proof before a performance fix: add signposts around bootstrap and monthly snapshot loading; measure cold open and expense↔income switch on the target iPhone with a realistic large transaction fixture.

### P1 — Visual hierarchy is flattened

- Borders exist on the month control, toolbar circles, outer monthly panel, nested hero, management buttons, every category card, icon circles, and floating add button.
- The gradient border is repeated at card level, so decorative treatment competes with values and labels.
- Four large icon-only management buttons occupy a complete row without visible labels. Their accessibility labels do not solve visual discoverability.
- The large floating `+` suggests "create category", while the actual primary action is tapping a category to create an operation. This is a misleading primary affordance.
- The 2-column grid gives zero-value categories the same area and weight as active categories. In the screenshot, five of six cards show zero, yet consume most of the viewport.

### P1 — Information architecture does not match the user's question

The primary question is: "What do I need to add/pay, and what has already happened?" The screen instead leads with a summary ring and category administration. Category reorder, settings, bulk import, plan setup, recurring management, search, and category creation are all promoted into the first viewport.

### P2 — Avoidable body-time work

- `monthTitle` creates a `DateFormatter` whenever recomputed.
- `formattedAmount` creates a `NumberFormatter` per value render.
- `heroChartEntries` reconstructs an option dictionary and sorts totals during view recomputation.
- `categoryBudgetSummary` linearly searches budget snapshots for each card.

These are secondary to duplicate data loading, but they amplify re-render cost on large category sets.

## Recommended target UX

### First viewport

- Compact navigation bar: close, month, overflow.
- One quiet segmented control: `Expenses | Income | Transfer`; no redundant nested animation.
- Compact monthly summary in the visual language of current Accounts/Cashflow: amount, plan progress, one subdued separator, no nested gradient frame.
- Visible two-state workflow control: `Upcoming | History`; History opens with status chips `All | Paid | Planned` and preserves month/type filters.

### Category entry

- Preserve the card-based quick selection explicitly preferred by the product owner, but use a compact two-column grid with approximately eight immediately visible categories rather than oversized cards.
- Active/non-zero categories receive a restrained tinted surface; zero-value categories remain immediately available but visually quieter. Avoid gradient borders and glow.
- Default ordering: pinned/recent/non-zero first, followed by the remaining visible categories; `All categories` and search expose the full catalog.
- Expose an explicit sort control beside the section title. Modes: activity, amount, manual order, and name. Activity means categories with operations in the selected month first; the grid must not reshuffle immediately after every saved operation. Pinned categories remain above every selected sort mode. Persist the selected mode independently for income and expense.
- Keep tap-on-category as the primary create path and state it in the section title/copy.
- Move reorder, category settings, and create category into one `Manage categories` route. Remove the floating `+` from the main surface.
- Move bulk import and recurring/planned management to labelled secondary actions or overflow; icon-only mystery controls should not remain.

### History contract

- Default: active/upcoming items.
- Filter: `Upcoming`, `Paid`, `All` (and type/month/category as secondary filters).
- `All`: active first; `Paid` below in a collapsed section, newest first.
- Empty states explain the active filter and offer `Show all`, so history never appears lost.

## Performance direction

1. Replace the three independent monthly calls with one `MonthlyEntrySnapshot` calculation that produces total, category totals, and budget progress from one conversion pass.
2. Load only the selected tab; cache snapshots by `(kind, month, currency, transaction revision, budget revision)`.
3. Cancel stale work on tab/month changes and publish only the latest request.
4. Keep exactly one transition animation and respect Reduce Motion.
5. Pre-index category/budget lookup data and reuse formatters through the existing formatting layer.

## Acceptance evidence for implementation

- Instruments/signpost comparison on target iPhone: cold open and ten expense↔income switches with realistic data.
- No duplicate monthly category traversal for one snapshot request (unit test with counting converter/provider).
- Paid items reachable in at most two taps and recoverable through `All`.
- Screenshot tests at 375/390 pt plus accessibility text size.
- VoiceOver labels for every visible action; no icon-only management control without a visible or contextually standard meaning.
