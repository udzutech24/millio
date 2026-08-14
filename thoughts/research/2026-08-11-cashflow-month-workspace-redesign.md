# Research: Cashflow month workspace redesign

- Date: 2026-08-11
- Scope: iOS information architecture for monthly cashflow review, single entry, manual bulk entry, bank-statement import/review, and reversible month closing. Research/spec/plan only; no production code.

## Reproduction and evidence

### The screenshot is an add flow pretending to be a month workspace

The exact route is:

```text
RootTabView global FAB
  -> showExpenseSheet/showIncomeSheet/showTransferSheet
  -> CashflowUnifiedEntryContainer
  -> CashflowCategoryTransactionSheet (expense/income)
     or CashflowTransactionEditorView (transfer)
```

- `RootTabView.swift:119-137` presents `CashflowUnifiedEntryContainer` for all three FAB actions.
- `CashflowUnifiedEntryContainer.swift:45-75` puts two category/month screens and one full transfer editor into a page-style `TabView`. These are not peer information views: expense/income are month/category dashboards while transfer is an editor.
- `CashflowUnifiedEntryView.swift:20-63` owns more than 30 local state values: month, category search/cap, budget, history, settings, bulk import, category CRUD, reorder, loading and feedback. This is evidence of mixed responsibilities, not merely a visual problem.
- `CashflowUnifiedEntryView.swift:137-160` renders month header, monthly total, management shortcuts and category grid in one scroll hierarchy.
- `CashflowUnifiedEntryView.swift:321-465` adds close/history/settings controls, a budget action and a large summary hero before the user reaches data.
- `CashflowUnifiedEntryView.swift:502-599` exposes management actions as icon-only tiles. Their meaning is carried mostly by accessibility labels, so sighted users must guess from symbols.
- `CashflowUnifiedEntryView.swift:762-775` renders an empty-state after the summary and zero-valued category grid have already consumed most of the screen.
- `CashflowUnifiedEntryView.swift:777+` makes every category a large bordered card. On an empty month the screenshot therefore shows a zero hero, multiple zero category cards, and another “no transactions” state simultaneously.

The screenshot confirms the code path: decorative outer/inner strokes compete with content; the summary, three icon-only actions, sort action, zero category grid, floating plus and empty state all request attention. There is no single primary task.

### Current data architecture

- `CashflowViewModel` is shared by `RootTabView` and the Cashflow tab. `CashflowTransaction` is the SwiftData source of truth for income/expense/transfer operations.
- `CashflowTransaction` already stores `importSourceRaw` and `importReferenceKey`, but amounts use `Double` and the current import namespace is not statement-level.
- Budget data is separate and correctly period-scoped through `BudgetPlan`, `BudgetCategoryLimit`, `monthlyBudgetSummary(...)` and `BudgetProgressCalculator`.
- Categories are provided through `CashflowCategoryService`, with pins/order in UserDefaults. Category cards are an entry affordance and summary, not a transaction history.
- Single entry ultimately uses `CashflowTransactionEditorView`; tapping a category in the current expense/income screen navigates there.
- History already exists as `CashflowTransactionsHistoryView`, but it is behind a clock icon instead of being the primary month content.

### Existing bulk import is reusable only in parts

- `CashflowBulkExpenseImportSheet` supports manual and screenshot modes, local Vision OCR, category suggestions, confidence and manual review.
- `CashflowBulkExpenseRowDraft.requiresAttention` and `CashflowBulkExpenseScreenshotReviewPolicy` are reusable concepts.
- `persistBulkExpenseImport` (`CashflowViewModel+History.swift:407-525`) is **not** a valid statement-import persistence path:
  - it aggregates one transaction per category/month/card;
  - fingerprints are category rollup keys, not bank-operation fingerprints;
  - re-import replaces/deletes rollup transactions;
  - original operation dates and merchants are lost;
  - duplicate/reconciliation evidence cannot be preserved.
- Conclusion: reuse category resolver, selection/presentation patterns and possibly extracted row components; do not route bank statement operations through `monthly_category_rollup` persistence.

### Backend readiness

- `millio-back/plans/2026-08-09-bank-statement-import.md` has Phase 1 complete: versioned contract, decimal/date/currency validation, keyed account scope, fingerprints, redaction and adapter ports.
- Backend CSV/XLSX adapters, authenticated upload endpoint and Alfa PDF adapter are not implemented yet.
- iOS must therefore expose a typed client boundary and honest `serviceUnavailable/unsupported` states. It must not simulate successful server analysis.

### Month closing does not exist

Repository-wide search found no Cashflow month-close/lock/reopen model or mutation policy. Existing “reopen” hits refer to stores/tests, not accounting periods. `BudgetPlan` represents limits, not a closed ledger period.

A visual “Closed” badge without a domain model would be dishonest. A real implementation needs:

- persisted lifecycle/audit history;
- a readiness calculator;
- mutation gates for create/edit/delete/import/scheduled auto-apply;
- explicit reopen before corrections;
- CloudKit/backup/schema handling;
- a definition of scope. Recommendation: close the whole calendar month across income, expense and transfer, not one tab/category, because otherwise ledger consistency is fictional.

## Apple guidance applied

- Apple describes sheets as scoped tasks related to the current context. The existing sheet has become a dashboard, settings area, category manager, import tool and editor at once; this violates the spirit of scoped modality. Source: https://developer.apple.com/design/human-interface-guidelines/sheets
- Apple recommends a prominent style for the most likely action, clear labels when text communicates better than icons, and at least 44×44 pt hit regions. The current row of icon-only management buttons has no visible action hierarchy. Source: https://developer.apple.com/design/human-interface-guidelines/buttons
- Apple positions menus as a space-efficient home for commands and requires concise action labels. A labeled secondary menu is a better home for import, budgets and settings than three equal icon tiles. Source: https://developer.apple.com/design/human-interface-guidelines/menus
- Apple lists/tables are intended for organized data and drill-down. Transactions should be the main list; categories should be filters/breakdown, not the primary empty grid. Source: https://developer.apple.com/design/human-interface-guidelines/lists-and-tables
- SwiftUI provides the system `fileImporter` boundary; supported UTTypes must be explicit and the selected security-scoped URL must be handled safely. Source: https://developer.apple.com/documentation/swiftui/view/fileimporter(isPresented:allowedContentTypes:allowsMultipleSelection:onCompletion:)

## Options considered

### Option A — cosmetically simplify the existing unified sheet

Keep `CashflowCategoryTransactionSheet`, reduce borders and add “Upload statement” plus “Close month”.

- Benefit: smallest short-term diff.
- Failure: preserves the wrong responsibility boundary and adds two more states to an already state-heavy view. Statement review and month locking would become more nested sheets and booleans.
- Verdict: rejected. This is cheap now and expensive forever.

### Option B — turn the existing container into one large monthly super-screen

Make expense/income/transfer tabs each show summary, transactions, import and close controls.

- Benefit: visually coherent and preserves the top segment.
- Failure: transfer has different fields; month lifecycle is shared across tabs; closure/import status would be duplicated or inconsistent. A single giant view remains likely.
- Verdict: rejected as the final architecture, but the segmented selector can remain a filter within the workspace if backed by one shared presentation model.

### Option C — separate month workspace, scoped entry, import hub/review, and closure flow

- `CashflowMonthWorkspaceView`: month navigation, compact summary, month status, transaction list, category filter/breakdown and primary add action.
- `CashflowEntryFlow`: current single-transaction editor, opened from the workspace or global FAB.
- `CashflowImportHub`: manual bulk vs statement upload; no parsing logic.
- `CashflowStatementReview`: staged review and transaction-level apply.
- `CashflowMonthCloseFlow`: readiness checklist, confirm close, closed summary and explicit reopen.

Benefit: each screen owns one job; unavailable backend and closure lifecycle are honest states; existing services can be adapted behind protocols. Cost: larger phased refactor.

Verdict: **recommended**. It is the smallest architecture that satisfies the requested product, not merely the smallest diff.

## Recommended information architecture

```text
Cashflow month workspace
├── Month header + Expense/Income/Transfer filter
├── Compact summary + month lifecycle status
├── Primary content: transaction list
├── Category breakdown/filter (collapsed/secondary)
├── Primary action: Add transaction
└── Secondary menu
    ├── Manual bulk entry
    ├── Upload statement
    ├── Budgets/limits
    ├── Planned/recurring
    └── Category settings

Import hub (sheet)
├── Manual bulk entry -> existing flow, simplified later
└── Bank statement
    └── fileImporter -> processing -> review -> apply

Close month (sheet)
└── readiness checklist -> confirmation -> closed summary -> explicit reopen
```

Global FAB should remain fast: it opens scoped single entry for the requested kind. The month workspace belongs to the Cashflow tab and can also be reached from the add flow via a labeled “Manage month” action. Replacing the global FAB with a dashboard first would add friction to the app’s most frequent action.

## State model

### Workspace presentation

```text
loading
  -> empty
  -> populated
  -> failed(recoverable)

monthLifecycle (orthogonal)
  open.inProgress
  open.needsReview(reasons)
  open.readyToClose
  closed(snapshot, closedAt)
```

The current calendar month is normally `inProgress`; a past month can become `readyToClose`. “No imported statement” is `notApplicable`, not automatically an error.

### Import session

```text
idle
 -> selectingFile
 -> uploading
 -> processing
 -> needsReview(rows, reconciliation)
 -> applying
 -> completed

selecting/uploading/processing
 -> unsupportedFileOrBank
 -> backendUnavailable
 -> reconciliationFailed
 -> failed(retryable/nonretryable)
```

Import review must survive normal app backgrounding. Persist only sanitized preview/session evidence required for recovery; never retain the original document by default.

### Month lifecycle

```text
open -> closeRequested -> closed
closed -> reopenConfirmed -> open
```

Close/reopen should be append-only audit events. Mutation of transactions in a closed month is rejected by one shared policy used by single save, edit/delete, bulk apply and scheduled auto-apply. Reopening does not delete the old close record; it appends a reopen event.

## Failure modes and mitigations

| Failure mode | Evidence/probability | Impact | Mitigation |
|---|---|---:|---|
| UI says “closed” but transactions still mutate | No lifecycle/policy exists; high if only UI is added | Critical | Domain model + shared mutation gate before UI |
| Statement import destroys detail by category rollup | Current persistence does exactly that | Critical | Separate transaction-level statement apply service |
| Same operation imported twice | Backend fingerprints exist but iOS model path does not consume them | High | Persist import fingerprint and unique preflight/apply policy |
| App closes during review | Current screenshot review is view state | Medium | Sanitized resumable import session or explicit discard warning |
| Backend unavailable/offline | Backend phases 2–4 absent today | High | Honest unavailable state; manual flow remains usable |
| Scheduled transaction writes into closed month | Auto-materialization is a separate mutation path | Medium | Closure policy injected into scheduled service; queue for review/next action |
| Dynamic Type breaks dense header/cards | Current UI uses many fixed sizes and one-line text | High | system text styles, flexible rows, accessibility-size alternate layout |
| Swipe tab changes unexpectedly during horizontal gestures | Current page `TabView` plus controls | Medium | use explicit segmented Picker without page swipe for workspace filters |
| CloudKit merge creates duplicate close events | New SwiftData model will sync | Medium | stable event ID/fingerprint and dedup tests/schema registration |
| Closing current/future month creates false finality | No rule exists | Medium | v1 allows closing completed calendar months only |

## Relevant files and tests

- Entry/routing:
  - `millio/UI/Main/RootTabView.swift`
  - `millio/UI/Services/Cashflow/UnifiedEntry/CashflowUnifiedEntryContainer.swift`
  - `millio/UI/Services/Cashflow/UnifiedEntry/CashflowUnifiedEntryView.swift`
  - `millio/UI/Services/Cashflow/CashflowTransactionEditorView.swift`
- Existing import:
  - `CashflowBulkExpenseImportSheet.swift`
  - `CashflowBulkExpenseImportModels.swift`
  - `CashflowBulkExpenseImportCategoryResolver.swift`
  - `CashflowViewModel+History.swift`
- Data/budget/history:
  - `CashflowTransaction.swift`
  - `CashflowTransactionsHistoryView.swift`
  - `Budget/BudgetPlan.swift`
  - `CashflowAnalyticsService.swift`
  - `CashflowFeatureRegistration.swift`
  - `Core/Schema/AppSchemaVersions.swift`
- Existing regression tests:
  - `CashflowUnifiedEntryTests.swift`
  - `CashflowBulkExpenseImportTests.swift`
  - `CashflowBulkExpenseImportLayoutPolicyTests.swift`
  - `CashflowCategoryGridLayoutTests.swift`
  - `CashflowTransactionEditorViewLayoutTests.swift`
  - localization tests under `millioTests/Core/Localization/` and `millioTests/UI/Services/Cashflow/`.

## 2026-08-14 follow-up: device UI audit and import month recovery

The current device build proves that the architectural pieces exist, but their composition is still weak:

- `CashflowView` renders three competing entry points in sequence: Add, Import, then a separate Month card. Import is month-scoped too, so exposing it before the month workspace duplicates navigation and hides the stronger mental model: choose/manage a month, then act inside it.
- `CashflowMonthWorkspaceView` uses a stock `List(.insetGrouped)`, segmented control and light material while the parent Cashflow screen uses black glass cards and custom finance tokens. The visual mismatch reported by the user is real, not subjective polish.
- The workspace repeats month status, close/reopen controls, empty-state import, and a persistent bottom Add/Import bar. This gives rare period-closing administration the same weight as everyday transaction review.
- `CashflowImportHubView.month` and `CashflowStatementImportController.selectedMonth` are immutable. `CashflowStatementMonthPolicy` correctly detects a mismatch, but `.monthMismatch` exposes no recovery action. The user must dismiss the flow, change month elsewhere and restart the import.
- The manual bulk sheet already owns a local selectable month. The statement path is the inconsistent one.

Recommended correction:

1. Main Cashflow actions become `Add operation` and `Month`; remove the separate Month card.
2. Month workspace becomes the only visible home for monthly transaction review and import.
3. Restyle the workspace with the parent screen's black background, `financeCardBackground`-equivalent shared tokens, readable rows and one compact sticky Add/Import action area.
4. Keep close/reopen in an overflow menu/status detail because it is infrequent administration, not primary navigation.
5. Make import month explicit and mutable. Preserve the parsed preview on mismatch, derive the statement month when the period belongs to one calendar month, and offer `Switch to <month>` plus manual month selection. Multi-month/invalid statements remain blocked with a precise explanation.
6. Revalidation must happen locally from the retained preview; selecting another month must not upload the bank file again.
