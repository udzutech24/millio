# Stress test: statement review UX and navigation plan

**Date:** 2026-08-13
**Verdict before corrections:** FAIL

## Blocking findings

1. Phase 0 did not choose the final owner of monthly UX, allowing two dashboards to survive. Root Cashflow must be the only dashboard; month child must be a thin transaction detail.
2. Root supports custom/multi-period ranges, but import requires one canonical month. Outside `.specificMonth`, an explicit month choice is mandatory; stale `selectedMonth` must never be reused.
3. Existing merchant preferences normalize their input, but statement adapter does not populate a stable merchant. Full descriptions contain changing identifiers. Learn only from a sanitized stable merchant key; otherwise do not learn.
4. Internal and external transfers were conflated. Internal transfers must remain locked/excluded; only external transfers may be explicitly converted to income/expense.
5. Backend/iOS taxonomy ownership was vague. Use a canonical versioned system-category fixture with parity tests in both repos; backend never emits custom IDs.

## High-risk findings

6. Statement reconciliation totals and proposed import totals must be shown separately after exclusions/reclassification.
7. Backend cannot see locally imported fingerprints. Annotate local duplicates before confirmation, not only as silent apply skips.
8. Integer apply result cannot identify inserted/skipped rows or safe learning targets. Return typed fingerprint sets.
9. Category group key must include transaction kind, category raw and currency.
10. Revalidate optional account attribution and open-month status at apply time; failure causes no partial write or learning.
11. Confidence threshold and attention reasons must be named domain policy, not UI constants.
12. Add search and lazy/performance evidence for 200 rows; segmented filters alone are insufficient.
13. File cancellation, background/resume, retry and second-file replacement need state-machine tests.
14. Backend deployment/rollback remains a separate explicitly authorized release step.

## Corrected verdict

**PASS WITH PHASE GATES** after these corrections are incorporated. Phase 0 must precede UI work; Phases 1–3 must precede claims of automatic or transfer-safe review.
