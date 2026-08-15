# Handoff: statement review plan Phase 2

- Phase 2 complete: pure iOS category resolution, safe merchant learning and typed apply outcome.
- `StatementCategoryResolver` implements the audited precedence: explicit review correction, valid learned mapping, valid backend suggestion at confidence `>= 0.8`, safe `other` fallback.
- Every candidate is checked against taxonomy version 1, the current category catalog and the operation income/expense kind. Current custom categories are accepted only from local review/learning, never trusted from backend suggestions.
- Resolution exposes source, confidence and `needsAttention` without SwiftUI coupling.
- Statement DTO now decodes backend `merchant`/`mcc`. Learning identity accepts only the separate sanitized `merchant`; bank `description` is never passed to the store. Email-like, long-number and unbounded keys fail closed.
- Existing `CashflowBulkExpenseMerchantCategoryPrefs` is reused behind the versioned narrow `CashflowStatementMerchantCategoryStore` adapter.
- Controller records only actual explicit category changes. Mappings are written only after a successful apply and only for inserted fingerprints; cancellation, failure, closed month and skipped duplicates cannot learn.
- Apply returns exact `insertedFingerprints` and `skippedFingerprints`. Persisted statement fingerprints are annotated and excluded before review apply.
- Focused resolver/apply/controller tests passed. Extended statement/taxonomy/bulk-import/category regression suite passed. Signed Release build for physical iPhone passed with Apple Development identity.
- The existing Xcode Crashlytics build phase reported that symbol upload would continue in the background during the required signed build; no deploy, app install, commit, push or financial-data mutation was initiated.
- Phase 0 manual accessibility/screenshots remain pending and are not reclassified by this phase.
- Next phase requires: `Реализуй фазу 3 по плану plans/2026-08-13__statement-review-ux-and-categorization.md`.
