# Research: statement review UX and automatic categorization

- Date: 2026-08-13
- Scope: iOS statement review, category suggestion pipeline, transfer handling, backend Alfa XLSX adapter. No production changes.
- Reproduction/evidence:
  - `AlfaBankXlsxAdapter` assigns `categoryId: "other"` to every operation with confidence `0.35`; iOS correctly copies that value into `categoryByFingerprint`. Automatic category selection therefore cannot work.
  - Transfers are already rejected by `CashflowStatementImportController.canInclude`, but the UI exposes only counters and disabled rows. There is no clear group action or safe reclassification path.
  - `CashflowImportHubView` mixes method selection, account settings, summary, reconciliation, category totals, 52 row editors and final action in one `List`. The primary action is below all rows and effectively undiscoverable.
  - Existing `CashflowBulkExpenseMerchantCategoryPrefs` already provides a local learned merchant-to-category mapping that can be reused instead of inventing another preference store.
  - Root overflow mixes seven unrelated destinations. Month workspace duplicates import/history/analytics in another overflow.
  - Month -> Analytics presents another `CashflowView` inside Cashflow, creating cyclic navigation and repeated top/quick-navigation controls.
  - Month workspace persistently exposes `Add operation`, while statement import is hidden in overflow unless the month is empty.
- Current architecture and constraints:
  - Backend owns extraction and portable rule suggestions; iOS owns actual available system/custom categories and personal learned mappings.
  - Statement apply rejects transfer operations and never mutates account balance.
  - Original bank bytes and PII must not be persisted or logged.
  - Category taxonomy values must be validated against the current iOS catalog; backend suggestions cannot blindly become persisted raw values.
- Options considered:
  1. Backend-only keyword dictionary. Simple, but cannot use custom categories or personal corrections and will remain weak for ambiguous merchants.
  2. iOS-only classification. Supports personalization, but duplicates bank normalization and makes previews inconsistent across clients.
  3. Layered deterministic pipeline: backend base rules + iOS taxonomy validation + existing local learned mappings + explicit user override. Recommended: simple, explainable, private and incrementally improvable.
  4. LLM categorization. Rejected for this phase: privacy, latency, nondeterminism, cost and poor auditability are unjustified.
- Recommended option and why:
  - Establish one information architecture first: destinations live in their content; overflow contains only infrequent settings.
  - Remove the cyclic Month -> Cashflow analytics route and duplicate quick-navigation control inside Cashflow-owned flows.
  - For any selected open month, show sibling actions `Add operation` and `Import`; both inherit that month.
  - Split import hub from a dedicated review flow.
  - Group-first review with filters `Needs attention / Categories / All`, category drill-down and a sticky bottom action.
  - Default-exclude transfers. Allow only explicit per-row conversion to income/expense with category selection; never silently import a transfer as ordinary cashflow.
  - Resolve category by precedence: session override > learned local merchant mapping > valid backend suggestion above threshold > `other`.
  - Learn only after final confirmed import, never from tentative picker changes.
- Risks and unknowns:
  - Bank descriptions can contain noisy identifiers; normalization needs fixture-backed tests and must not over-collapse distinct merchants.
  - One merchant can legitimately map to different categories. Learned mapping must be editable and confidence/source visible for low-confidence rows.
  - Mixed currencies cannot be aggregated into one amount; breakdown must group by category and currency.
  - Reclassified transfers affect reconciliation semantics and must be shown separately in confirmation.
- Relevant files/tests:
  - iOS: `CashflowImportHubView.swift`, `CashflowStatementImportController.swift`, `CashflowStatementReviewPresentation.swift`, `CashflowStatementApplyService.swift`, `CashflowBulkExpenseMerchantCategoryPrefs.swift`.
  - Backend: `alfa-bank-xlsx.adapter.ts`, schema-v1 contract and adapter specs.
