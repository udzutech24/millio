# Millio codebase audit: top 10 engineering priorities

**Date:** 2026-08-09
**Scope:** iOS (`millio/`), backend (`millio-back/`), web (`millio-web/`)
**Mode:** read-only audit; production code was not changed.

## Executive verdict

The product is not a poorly engineered prototype: the iOS app has substantial tests and an explicit migration architecture, and the backend has useful unit coverage around auth and market data. However, the system is not yet "bulletproof". The highest risks are not visual polish or naming. They are fail-open internal endpoints, plaintext third-party credentials, an unvalidated financial export boundary, two competing iOS financial models, and a red backend test suite.

The ranking below is based on expected damage and change leverage, not file size alone.

## Evidence collected

- iOS: about 182,005 lines of Swift including tests; 306 test-related files.
- Backend: about 14,474 lines of TypeScript; 21 Jest suites / 126 tests discovered.
- Web: about 3,250 lines of TypeScript/TSX/Astro; 5 test-related files.
- Backend test run: **3 suites failed, 18 passed; 3 tests failed, 123 passed**.
- Web test run could not start because local dependencies are not installed (`vitest: command not found`).
- Xcode project and schemes resolve successfully. A full simulator test run was not performed in this audit.
- Existing unrelated working-tree changes were preserved: `millio/thoughts/research/2026-08-09-fx-ui-stress-test.md` and `millio-web/AGENTS.md`.

## Top 10

### 1. P0 Security: internal backend endpoints fail open when secrets are absent

**Evidence:**

- `millio-back/src/support/support.controller.ts:33`
- `millio-back/src/trading-briefing/trading-briefing.controller.ts:19`
- `millio-back/src/market-watchlist/market-watchlist.controller.ts:18`

All three authorize with the equivalent of `if (expected && supplied !== expected)`. An empty/missing environment secret therefore disables authentication instead of disabling the endpoint. The endpoints can trigger Telegram handling, AI/provider work, market polling, and outbound messages.

**Risk:** unauthenticated cost generation, spam, provider-budget exhaustion, and operational abuse after one bad deployment configuration.

**Recommendation:** create one reusable constant-time `ConfiguredSecretGuard` that fails application startup or returns 503 when the secret is missing and 401 when it mismatches. Apply explicit throttling. Do not duplicate ad-hoc header checks.

**Done when:** boot/config tests cover missing secret; controller tests prove missing, empty, and invalid secrets are rejected; no internal trigger uses fail-open logic.

### 2. P0 Security: Google OAuth refresh tokens are stored as plaintext

**Evidence:**

- `millio-back/prisma/schema.prisma:107` stores `refreshToken String`.
- `millio-back/src/sheets/sheets.service.ts:226-229` writes the provider token directly.
- `millio-back/src/sheets/sheets.service.ts:198-200` reads and uses it directly.

The main Millio refresh tokens are correctly hashed, but Google refresh tokens cannot be hashed because they must be reused. They therefore require encryption at rest and strict key management.

**Risk:** a database leak grants long-lived access to users' Google Sheets.

**Recommendation:** envelope-encrypt tokens (versioned ciphertext + nonce + key ID), keep the KEK outside the database, redact all token-bearing errors, support key rotation, and revoke the Google token on disconnect before deleting the row.

**Done when:** no plaintext provider token is persisted; migration is reversible and tested; disconnect revokes access; logs/Sentry never receive token material.

### 3. P0 Boundary integrity: `/sheets/sync` accepts an unvalidated, unbounded financial dump

**Evidence:**

- `millio-back/src/sheets/sheets.controller.ts:91-99` binds `@Body() data: MillioExportData`.
- `MillioExportData` and nested rows in `sheets-export.types.ts` are TypeScript interfaces, not runtime DTOs; Nest `ValidationPipe` cannot validate them.
- There are no per-array limits, string limits, finite-number checks, ISO-date validation, currency validation, or payload-size policy in this boundary.

**Risk:** malformed financial output, NaN/Infinity propagation, memory/Google API amplification, request-time DoS, and partial spreadsheet corruption.

**Recommendation:** introduce runtime DTOs with nested validation and hard limits; configure body size; make sync an idempotent job with a revision/idempotency key. Reject rather than "repair" invalid money data at the server boundary.

**Done when:** adversarial DTO tests cover huge arrays, invalid dates, non-finite numbers, oversized strings, duplicate IDs, and unsupported currencies.

### 4. P0 Correctness/architecture: iOS has two live financial source-of-truth models

**Evidence:**

- Legacy link model: `millio/UI/Services/Finances/FinanceAccount.swift:39`.
- New event-sourced model: `millio/Core/AccountsCore/Account.swift:8`.
- `FinanceDynamicsViewModel.swift` simultaneously fetches/reconciles `FinanceAccount`, `Card`, `Credit`, `Investment`, and new `Account`; it contains explicit `legacy`, `shadow`, `compatibility`, predecessor, and fallback paths throughout (for example lines 1198-1249, 1558-1693, 1737-1950).

This is a migration system embedded in a screen view model. Every new finance feature must reason about two identities, two balance engines, archive semantics, fallback rules, and reader modes.

**Risk:** double counting, missing balances, inconsistent historical charts, regressions that only affect migrated users, and permanent migration tax.

**Recommendation:** make `Account` the only write model, move legacy reading into a bounded anti-corruption/migration layer, publish explicit parity telemetry, then delete compatibility paths after a measurable exit criterion. Do not add more conditional bridges to the view model.

**Done when:** new writes cannot create legacy finance entities; parity is proven on fixtures/backups; reader switch is complete; legacy fetches disappear from UI/view models.

### 5. P1 Correctness: persistence failures are silently swallowed in user flows

**Evidence:** at least 9 production call sites use `try? ...save()`; examples include:

- `millio/UI/Services/Investments/InvestmentViewModel.swift:231`
- `millio/Core/AccountsCore/AccountMarketPriceService.swift:59,113`
- `millio/UI/Services/Finances/FinanceViewModel.swift:697`
- `millio/UI/Services/UserSubscriptions/UserSubscriptionsView.swift:299,378`
- `millio/UI/Services/Cashflow/CashflowViewModel+History.swift:378,400`

**Risk:** the UI can report success while SwiftData rejected the write, producing silent data loss and cache/model divergence.

**Recommendation:** route mutations through typed repositories/use cases with one save/error policy. Return typed failure to the caller, rollback/reset the context where appropriate, show actionable UI, and report sanitized diagnostics.

**Done when:** user-visible mutations cannot ignore save errors; failure-path unit tests assert no success event/haptic/navigation occurs after a failed save.

### 6. P1 Maintainability/correctness: core iOS screens are god objects

**Evidence:**

- `FinanceDynamicsViewModel.swift`: 3,483 lines, mixing selection state, SwiftData fetches, cache ownership, migration compatibility, FX, historical valuation, chart sampling, and UI actions.
- `FinanceDynamicsView.swift`: 3,231 lines.
- `CashflowTransactionEditorView.swift`: 2,532 lines, mixing rendering, category CRUD, transfer FX, balance validation, recurrence, navigation, and persistence orchestration.
- Other production views exceed 2,000 lines (`CashbackView`, `CashflowBulkExpenseImportSheet`, `FinanceViewModel`, `CashflowView`).

Large files are not automatically wrong; these are wrong because responsibilities and change reasons are demonstrably mixed. The 3,551-line `CashflowViewModelTests.swift` and 3,155-line `FinanceViewModelTests.swift` mirror the same missing seams.

**Recommendation:** split by stable capabilities, not arbitrary extensions: pure calculation engines, data loaders/repositories, mutation use cases, state reducer, and small view sections. Keep one orchestration view model per screen; inject protocols only at real side-effect boundaries.

**Done when:** financial calculation tests run without SwiftUI/SwiftData; view models orchestrate rather than calculate; no split is merely line-count shuffling.

### 7. P1 Delivery: backend main is currently red and one unit test depends on wall-clock behavior

**Evidence from `npm test`:**

- `market-data.service.spec.ts:819` timed out at 5 seconds despite a `setTimeout` spy; this is a flaky/incorrect async seam.
- `market-prewarm.service.spec.ts:149` expects 12 symbols but production budget selection returned 5; contract and test disagree.
- `schema-readiness.spec.ts:16` was not updated for required `PromoCode`.

**Risk:** CI cannot distinguish regressions from stale/flaky tests; developers normalize red builds.

**Recommendation:** make delay/clock injectable and use deterministic fake timers; define the prewarm budget contract once and test the policy as a pure function; generate or centralize required-table expectations.

**Done when:** 20+ repeated local runs are green; tests use no real wait; CI blocks merge on test/build/lint.

### 8. P1 Data integrity: Google Sheets sync is a 1,043-line untested, non-atomic workflow

**Evidence:** `millio-back/src/sheets/sheets.service.ts` owns OAuth, persistence, spreadsheet creation, formatting metadata, transformations, append deduplication, dashboard computation, and many sequential remote writes. No `sheets.service.spec.ts` exists. `fullSync` updates local sync metadata only after many Google calls, but Google Sheets writes themselves are not one atomic commit.

**Risk:** a failure halfway leaves a mixed-generation workbook; retry behavior is unclear; changes to financial formulas have no executable specification.

**Recommendation:** split into OAuth credential store, pure export mapper, workbook plan builder, and Google gateway. Build a complete deterministic write plan first, stage/version writes, then publish a completion marker. Unit-test all pure calculations and contract-test the gateway.

**Done when:** failure injection at every remote step has a defined retry outcome; golden fixtures cover formulas/rows; sync status distinguishes running/partial/succeeded/failed.

### 9. P1 Reliability: background trigger endpoints acknowledge work that is neither owned nor observed

**Evidence:**

- `trading-briefing.controller.ts:22` calls `void this.briefing.run()` and returns accepted.
- `market-watchlist.controller.ts:27-44` launches untracked async IIFEs and immediately returns accepted.

There is no durable queue, job ID, deduplication, retry contract, or controller-level error ownership.

**Risk:** process restart loses work; async rejection may be unhandled; repeated requests create duplicate provider calls/messages; callers cannot know outcome.

**Recommendation:** use a durable job queue/outbox with idempotency keys and observable job state. If volume does not justify a queue, keep it KISS: await the operation and return its actual result instead of pretending it is asynchronous infrastructure.

**Done when:** every accepted request has a durable job ID or the endpoint awaits completion; duplicates and failures are tested.

### 10. P2 Type safety/KISS: Yahoo market access is duplicated behind `any`

**Evidence:** separate direct Yahoo clients exist in:

- `millio-back/src/market-data/yahoo-finance.provider.ts`
- `millio-back/src/market-watchlist/market-watchlist.service.ts`
- `millio-back/src/trading-briefing/prices.service.ts`

The latter paths use `any`, `any[]`, and repeated unchecked quote/history parsing. Only the main market provider is exercised indirectly by `market-data.service.spec.ts`; no focused tests were found for the other direct clients.

**Risk:** provider response drift yields runtime corruption; retry/rate-limit/symbol normalization policy diverges across features; provider spend becomes hard to control.

**Recommendation:** one typed `MarketQuoteGateway` with runtime parsing, centralized budgets/timeouts/retries, and feature-specific application services above it. This removes duplication without inventing a generic framework.

**Done when:** no feature instantiates Yahoo directly; malformed provider fixtures fail safely; all provider calls share budget and telemetry policy.

## Recommended execution order

1. Security hotfix: items 1-3, with focused tests and deployment config validation.
2. Restore the backend quality gate: item 7.
3. Stabilize Sheets as a bounded subsystem: items 2, 3, and 8 together.
4. Complete the iOS account-model cutover: item 4 before broad UI refactoring.
5. Introduce typed mutation/save boundaries: item 5.
6. Decompose iOS god objects incrementally behind characterization tests: item 6.
7. Consolidate async jobs and market providers: items 9-10.

Do not start by mechanically splitting large Swift files. That produces more files while preserving the same coupling. The first architectural move must be removal of competing sources of truth and extraction of pure financial policies.

## Verification limits

- No production code was changed, so no new tests were added.
- Backend results are directly reproduced by the test command above.
- Web cannot be judged green or red until dependencies are installed from the lockfile; the missing local install is not itself a product defect.
- A full iOS simulator matrix would require a separate verification phase. This audit therefore treats iOS runtime defects as risks only where source evidence is explicit; it does not claim an unexecuted test failure.

## Stress-test addendum (2026-08-09)

The original ranking identifies the right risk areas, but its execution order is too coarse for autonomous implementation. The corrected dependency order is:

1. Record the current backend test baseline so new regressions remain distinguishable.
2. Fix item 1 as a bounded security phase: endpoint-local 503 for missing configuration, 401 for invalid credentials, one reusable constant-time guard, focused wiring tests, and an explicit active throttler guard. Do not mix background-job redesign into this patch.
3. Restore the complete backend quality gate (item 7).
4. Fix background trigger ownership (item 9) immediately after authentication; otherwise valid-secret calls still create untracked, lossy work.
5. Split the Sheets work into `3A runtime DTO/body validation → 2 credential encryption migration → 8 deterministic/retryable workbook workflow`. Idempotent jobs are not part of the boundary-validation hotfix.
6. Introduce the narrow save/error boundary needed by account migration (part of item 5) before the account-model cutover (item 4). Expand the save policy to remaining flows after cutover.
7. Decompose iOS god objects (item 6), then consolidate the market gateway (item 10), unless provider failures become an earlier operational incident.

Additional evidence found during stress-testing:

- `millio-back/src/idea-inbox/idea-inbox.controller.ts` repeats the fail-open API-key pattern and must be included in item 1 for GET/PATCH routes.
- `millio-back/src/promo/bot-token.guard.ts` is already fail-closed but duplicates secret checking and should migrate to the shared primitive.
- `ThrottlerModule` configuration alone does not activate throttling. The protected routes need an actual `ThrottlerGuard` (global or route-level) plus route policy metadata.

Policy decisions required by the first phase are now explicit:

- Keep existing header and environment-variable names to avoid breaking callers.
- Missing or blank server-side secret returns 503; it must not disable the whole API because these integrations are optional deployment capabilities.
- Missing, blank, multi-valued, or mismatched caller credentials return 401 without echoing secret material.
- Public routes remain public in this phase; their exposure is a separate product/security decision.
- Rollback means reverting code while retaining configured secrets. Returning to fail-open operation is not an acceptable planned fallback.
