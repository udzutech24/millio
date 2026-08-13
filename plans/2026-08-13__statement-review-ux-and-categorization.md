# Plan: statement review UX and automatic categorization

## Status

`IN PROGRESS` — Phases 1–4 complete. Phases 0 and 5 are implemented pending manual compact/large-device, VoiceOver and screenshot acceptance.

## Inputs

- Research: `../thoughts/research/2026-08-13-statement-review-ux-and-categorization.md`
- Stress test: `../thoughts/research/2026-08-13-statement-plan-stress-test.md`
- Spec: `../specs/2026-08-13-statement-review-ux-and-categorization.md`

## Decision

- Chosen approach: a layered deterministic category resolver and a dedicated group-first statement review flow.
- Rejected alternatives:
  - Keep expanding the current single `List`: it cannot make a 52-row review discoverable.
  - Backend-only categories: no custom categories or personal learning.
  - LLM categorization: excessive privacy, latency, cost and auditability risk.
  - Toggle that imports transfers unchanged: current apply contract cannot safely represent them and would corrupt totals.
- Rollback strategy: route changes, category rules and review UI land behind narrow resolver/presentation types. Learned mappings are versioned. Disable the new route and fall back to safe `other`; never delete imported transactions or mappings automatically.

## Target flow

```text
Cashflow (selected period/month)
  -> visible Add operation / Import
  -> period control owns month selection
  -> chart owns expansion
  -> budget card owns budget editor
  -> content owns operations/history
  -> overflow owns infrequent settings only

Import hub
  -> choose statement
  -> processing / error
  -> Statement review (dedicated screen)
       -> Needs attention
       -> Categories -> category drill-down
       -> All operations
       -> Transfers excluded -> explicit reclassification only
  -> Confirmation
       -> account attribution
       -> balance remains unchanged
       -> totals/counts
  -> Apply -> result
```

## Phases

### [ ] Phase 0 — Cashflow information architecture and route ownership (implemented; manual accessibility/screenshots pending)

- Inventory every Cashflow destination and assign exactly one primary owner/entry point.
- Remove Month and chart expansion from root overflow; period control and chart own those actions.
- Route budget cards directly to their editors and expose operations/history visibly in content.
- For an open selected month, show persistent sibling actions `Add operation` and `Import`; both receive the same canonical month.
- Root Cashflow is the only dashboard; month workspace becomes a thin transaction detail without another chart/analytics root.
- For custom/multi-period ranges, require explicit month selection before a month-scoped write flow; never reuse stale `selectedMonth`.
- Reduce overflow to infrequent settings such as display currency; do not use it as a second tab bar.
- Remove Month -> nested `CashflowView` recursion and duplicate mini-app quick-navigation inside Cashflow child flows.
- Evidence: acyclic route graph tests, unique route ownership, selected-month preservation, closed-month write blocking and compact/large-device screenshots.

### [x] Phase 1 — category taxonomy and deterministic backend rules

- Define a canonical versioned system-category taxonomy fixture with parity tests in both repos; backend never emits custom category IDs.
- Extract normalization/rule matcher from the Alfa adapter; cover common fixture-backed patterns such as groceries, restaurants, transport, subscriptions, fees, cash and income.
- Return confidence/source honestly; unmatched and ambiguous descriptions remain `other`/low confidence.
- Add backend golden/negative tests, including PII-redacted descriptions and false-positive boundaries.
- Evidence: backend unit/contract suite and build green. Production deployment was performed later under the user's explicit permission; the runtime matcher smoke test and protected preview-route gate passed.

### [x] Phase 2 — iOS category resolution and learning

- Add a pure `StatementCategoryResolver`; validate taxonomy version, category existence and income/expense kind.
- Reuse/version `CashflowBulkExpenseMerchantCategoryPrefs` through a narrow protocol; learn only from a sanitized stable merchant key, never a full bank description.
- Precedence: review override > learned mapping > valid backend suggestion above threshold > `other`.
- Track resolution source/confidence and derive `needsAttention` without coupling it to SwiftUI.
- Return inserted/skipped fingerprint sets from apply and annotate local duplicates during review.
- Learn explicit confirmed corrections only after successful apply; cancelled/failed/closed-month paths do not learn.
- Tests: precedence, invalid taxonomy/category, ambiguous merchant, custom category, cancellation and successful learning.

### [x] Phase 3 — transfer and exclusion domain policy

- Replace `canInclude` boolean with an explicit review disposition: included, excluded-transfer, excluded-duplicate, excluded-technical, reclassified.
- Keep `Exclude all transfers` as the safe default and add group-level visibility/action.
- Internal transfers stay locked/excluded. Permit only an external transfer after explicit conversion to expense/income plus category; preserve original type in review metadata.
- Keep duplicate/technical rows locked out.
- Tests: internal/external distinction, default/bulk exclusion, reclassification validation, local duplicates, closed-month race, counts/totals and apply preflight.

### [x] Phase 4 — dedicated review navigation and presentation

- Keep `CashflowImportHubView` only as method selection/status entry.
- Push a dedicated `CashflowStatementReviewView`; no nested modal stack for ordinary progression.
- Add segmented filters `Needs attention / Categories / All`.
- Category tab is group-first; tapping a category opens its rows. Provide confirmed group reassignment.
- Group by transaction kind + category + currency; add search and forbid cross-kind reassignment.
- Put reconciliation in a compact status header; move account attribution to confirmation.
- Add a sticky safe-area action `Import N operations`; show a precise blocking reason when disabled.
- Pure presentation/performance tests cover 0/1/52/200 rows, mixed currency/kind, search, all-categorized and all-excluded states.

### [ ] Phase 5 — confirmation, accessibility and visual acceptance (implemented; manual device acceptance pending)

- Build final confirmation with separate statement reconciliation and proposed import totals, inserted/skipped candidates, exclusions, reclassified external transfers, revalidated account link and unchanged-balance guarantee.
- Complete RU/EN/zh fallback copy, VoiceOver order/actions, Dynamic Type and Reduce Motion behavior.
- Run focused import/apply/category suites, relevant Cashflow regression gate and signed device build.
- Capture compact/large iPhone screenshots for processing, needs-attention, categories, transfer review, confirmation, error and completion.
- Perform final AC/security/privacy audit and update handoff/reflection/status.

## Verification

- Unit tests: acyclic route ownership/month preservation; backend rule matcher; iOS resolver, disposition policy, presentation builder and learned mapping lifecycle.
- Contract tests: schema taxonomy/confidence/source and backend/iOS golden fixture parity.
- Integration/build checks: apply idempotency and atomicity, mixed currencies, closed month, simulator tests, signed physical-device build.
- Acceptance criteria audit: every spec checkbox mapped to a test, screenshot or explicit manual device check before status becomes complete.

## Stress-check

| Failure mode | Impact | Mitigation |
|---|---|---|
| Wrong high-confidence category | Financial analytics silently wrong | Conservative rules, fixture negatives, visible source/attention threshold, final review |
| Unknown/custom category from backend | Invalid persisted raw value | iOS taxonomy/kind validation and safe fallback |
| Merchant used for multiple purposes | Incorrect learned category | Editable suggestion, learn only confirmed choices, future mapping reset surface |
| Transfer imported as expense | Double-counted cashflow | Default exclusion; explicit typed reclassification only |
| 200-row statement freezes UI | Abandoned import | Pure precomputed presentation, lazy rows, performance/layout test |
| Mixed currencies summed together | Misleading totals | Group and confirm totals by currency |
| Backend unavailable/offline | Dead end/data loss | Explicit retry/back flow; original remains user-controlled; no partial apply |
| Double tap/concurrent apply | Duplicate writes | Disable action while applying plus fingerprint idempotency |
| Two competing Cashflow dashboards | Users cannot predict where actions live | One route owner per destination; remove duplicate menu entries |
| Child Cashflow opens root Cashflow | Cyclic stack and repeated controls | Route graph test; delete nested root presentation |
| Custom range reuses stale month | Operations land in wrong month | Explicit month selection outside `.specificMonth` |
| Learning uses changing description | Mapping misses or poisons merchants | Stable sanitized merchant key or no learning |
| Internal transfer becomes expense | Double-counted movement | Internal transfers locked/excluded |
| Local duplicate appears only after confirm | Misleading counts | Pre-annotate fingerprints; typed apply result |
| Reconciliation differs from import proposal | User trusts wrong total | Display both totals separately |
| Month closes/account disappears mid-review | Invalid write or attribution | Revalidate at apply; atomic failure, no learning |

## Journal

- 2026-08-13: reproduced root causes in code and screenshots. Backend emits `other` for every operation; transfers are already excluded but not presented as a coherent policy; review and import-method navigation are mixed in one long list. Research/spec/plan created. No production code changed.
- 2026-08-13: navigation audit proved duplicate root/month overflow destinations and a cyclic Month -> Analytics -> new Cashflow root route. Added Phase 0 for one route owner per destination before statement UI work.
- 2026-08-13: stress test initially failed on route ownership, non-month periods, merchant identity, transfer semantics, taxonomy drift, local duplicates and apply races. Plan/spec hardened; corrected verdict: pass with phase gates.
- 2026-08-13: Phase 0 implemented test-first. Added a pure ownership/route/month-scope policy, removed root and child duplicate destinations, deleted Month → nested `CashflowView`, made month detail transaction-only, added persistent sibling Add/Import actions, and required explicit month selection outside `.specificMonth`. Canonical month now reaches income/expense/transfer editors explicitly instead of relying on stale view-model state. Focused policy/editor tests passed; Cashflow regression found two unrelated reproducible dirty-baseline failures (`duplicateCardsStayConsistentAcrossModules`, `unresolvedLegacyFailsClosed`). Compact and large simulator builds and signed physical iPhone 17 Pro Max build passed. Manual VoiceOver/Dynamic Type interaction was not claimed; structural labels/hints and flexible layouts were audited.
- 2026-08-13: Phase 1 complete. Added a canonical taxonomy-v1 fixture mirrored byte-for-byte in backend/iOS and an iOS enum parity test. Backend runtime validation rejects unknown, custom and wrong-kind IDs. Extracted deterministic normalization/rule matcher and wired it into Alfa XLSX after redaction. Positive and false-positive fixtures cover groceries, dining, taxi/transport, subscriptions, fees, cash movement, salary, interest and refunds; ambiguous input remains `other/0.35`. Backend bank-statement suite passed 50/50, Nest build passed, and iOS taxonomy parity test passed. No deployment or remote mutation occurred.
- 2026-08-13: Phase 1 deployed to production after explicit user authorization. The existing production checkout was intentionally not rebuilt because it lacked the uncommitted statement module and contained unrelated dirty files. Instead, an isolated overlay image added only the matcher, taxonomy, contract and Alfa-adapter runtime artifacts on top of the active image. Pre-deploy focused tests passed 29/29 and Nest build passed; candidate and active-container matcher smoke tests resolved `Пятерочка` to `groceries/0.92`; the protected preview endpoint returned the expected unauthenticated `401`; no runtime errors appeared. Rollback image tag: `millio-back:rollback-pre-statement-phase1-20260813`. Physical-device relaunch was blocked only because the iPhone was locked; re-import acceptance remains pending.
- 2026-08-13: Physical-device evidence showed only 2/51 operations categorized. Root cause: Alfa column 5 (`Категория`) was parsed as a required header but ignored for resolution, leaving description-only rules with predictably poor coverage. Added test-first conservative Alfa category aliases for 29 common category labels while preserving specific merchant precedence and refusing ambiguous `Прочие/Финансовые операции`. Focused suite passed 47/47, build passed, candidate and active runtime smoke gates passed. Production overlay updated with rollback `millio-back:rollback-pre-bank-category-20260813`; app relaunched on physical iPhone for a fresh preview.
- 2026-08-13: The user supplied the failing Alfa XLSX for local-only analysis. It proved 50/52 source rows are labeled `Прочие операции`, while card descriptions contain structured merchant and MCC fields. Added MCC taxonomy fallback, Yandex aggregator merchant disambiguation, utilities/parking evidence, and principal-repayment recognition as internal cash movement. No source amounts, account identifiers or full descriptions were persisted as fixtures or logged remotely. Focused suite passed 59/59 and build passed. The real file was parsed locally without import: 49/50 included operations categorized, one evidence-free row remained honestly `other`, and two internal movements were excluded. Production runtime gate passed; rollback tag `millio-back:rollback-pre-mcc-20260813`. Phone relaunch was blocked by device lock; fresh preview remains the final manual check.
