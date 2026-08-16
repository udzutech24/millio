# Plan: создание счёта из банковской выписки

## Status

`IN PROGRESS` — Phase 3 create-flow composition implemented and verified; Phase 1 bank-specific balance extraction still awaits a sanitized real fixture that actually declares a balance.

## Inputs

- Research: `../thoughts/research/2026-08-16-account-creation-from-statement.md`
- Spec: `../specs/2026-08-16-account-creation-from-statement.md`
- Existing statement plan: `2026-08-13__statement-review-ux-and-categorization.md`
- Debit contract: `../specs/2026-08-11-debit-card-product-vertical.md`

## Decision

- Chosen approach: preview/review до persistence; затем одна атомарная Account + closing-balance anchor + Cashflow projection через `AccountProductFactory.graphEnricher`. Импортированные операции не меняют баланс.
- Rejected alternatives:
  - Новый parser/review flow в Finances: дублирует рабочий statement pipeline.
  - Проигрывать все строки как AccountEvent: нет достаточных anchor/transfer guarantees.
  - Два save — create, затем apply: оставляют полусозданный счёт при сбое.
  - Open Banking: другой продукт/угроза и не нужен для текущего UX.
- Rollback strategy:
  - iOS CTA/route отделены от обычного create; их можно снять без миграции user data.
  - Backend balance fields additive/optional; старый client и manual-balance fallback продолжают работать.
  - При atomic failure в хранилище нет частичного graph; rollback не удаляет уже существующие user rows.

## Target flow

```text
Create debit card / bank account
  -> enter minimal metadata
  -> optional "Upload statement"
  -> existing file picker + backend preview
  -> existing statement review/category/transfer policy
  -> balance evidence
       -> trusted bank closing balance
       -> or explicit manual balance confirmation
  -> final confirmation
  -> one atomic commit
       Account + openingBalance(closing snapshot, asOf)
       CashflowTransaction[] (affectsCardBalance=false)
  -> one refresh -> account detail + imported Cashflow
```

## Phases

### [ ] Phase 1 — balance evidence contract and characterization (contract complete; adapter evidence pending)

- Add backend/iOS typed optional balance evidence; choose additive decoding compatible with existing preview payloads.
- Before adapter edits, add sanitized characterization fixtures proving where Alfa XLSX and T-Bank PDF do or do not declare opening/closing balance and date.
- Parse only header-labelled deterministic fields; never infer a bank-declared value from totals alone.
- Add invariant `opening + income - expense = closing` when both anchors exist; mismatch downgrades confidence/forces review, never silently rewrites a value.
- Add backend contract/golden/negative tests: absent balance, corrupt decimal/date, wrong currency, mismatch, huge/negative allowed balance values and template drift.
- Add iOS decode/policy tests for new and old payloads.
- Evidence gate: supported fixture produces exact expected balance evidence; fixtures without evidence remain valid and require manual input.

### [x] Phase 2 — reusable statement staging and atomic coordinator

- Extract persistence-neutral validation/staging from `CashflowStatementApplyService`; ordinary Cashflow import retains byte-for-byte financial behavior.
- Introduce a narrow `AccountStatementOnboardingCommand` containing validated create command, approved rows, balance evidence/manual confirmation and stable onboarding ID.
- Implement `AccountStatementOnboardingCoordinator` on top of `AccountProductFactory.graphEnricher`; stage Cashflow rows in the factory's isolated context and commit once.
- Revalidate currency, one-month scope, month-open policy, included dispositions, fingerprints, category kinds, account product type and balance confirmation immediately before staging.
- Make final apply idempotent for double tap/retry: persist the stable onboarding key in `openingEvent.sourceTransactionID`, compare the existing account anchor and imported fingerprint set, and reject the same key with a different payload. Do not add a schema field unless characterization disproves this route.
- Treat the current `sourceTransactionID` check as unproven for concurrency: it has no storage uniqueness. Before implementation, add a two-context race test and choose the smallest mechanism that actually passes it (serialized writer plus deterministic graph IDs, or a persisted unique operation model with an explicit migration). Add a CloudKit merge/reconciliation test; do not describe local commit atomicity as cross-device atomicity.
- Detect existing fingerprints together with their `cardID`. Same-account duplicates may be skipped; unassigned or other-account duplicates require an explicit review conflict and must never be silently reparented.
- Publish learning and one finance/cashflow refresh only after durable commit.
- Tests first: success graph, every injected stage/save failure, zero operations, local duplicate, duplicate within request, concurrent/double apply, conflict, closed-month race and no post-failure learning/event.

### [x] Phase 3 — create-flow composition using existing review

- Add the optional statement CTA only for debit card and bank account forms; preserve the current manual create path unchanged.
- Compose/reuse the existing file selection, controller, category resolver, dispositions and review presentation behind a context object instead of copying SwiftUI screens.
- In onboarding context hide account picker: the target is the pending account ID. Keep category/transfer/duplicate behavior identical.
- Add balance confirmation UI with clear provenance and `as of` date; manual fallback is explicit and never prefilled from derived turnover.
- Final confirmation shows account identity, balance/date, counts/totals, exclusions and unchanged-balance guarantee.
- Preserve draft form values across file picker cancel, backend error and review back navigation; switching product type invalidates incompatible statement draft explicitly.
- Pure policy/view-model tests cover CTA visibility, state transitions, back/cancel/retry, currency/multi-month blocking and command construction.

### [x] Phase 3A — external file ingress and Share Sheet UX

- Define one allowlisted `IncomingStatementFilePolicy` only for formats with an active backend adapter (v1: XLSX, CSV and PDF) using UTType plus content signature/size checks; the filename extension alone is not trusted. OFX is a separate adapter/contract phase and stays unregistered until then.
- Register statement document types for public `Open in Millio`; extend the existing `.onOpenURL` router without mixing backup and statement behavior.
- Immediately balanced-access and bounded-copy every security-scoped external URL into app-owned temporary storage before async preview.
- Add `IncomingStatementCoordinator` as the only owner of direct URLs and App Group inbox items; it routes into the same controller/review used by in-app import and account onboarding.
- Define the destination state machine. If an onboarding draft is active, attach the preview to it; otherwise show an explicit post-preview choice between creating a new account and the existing Cashflow import path. Never persist or guess an account from filename/bank metadata.
- Add a minimal `Save to Millio` Share Extension target. It copies exactly one validated file into `group.com.millio.app/StatementInbox` using a temporary name plus atomic rename and writes only a safe manifest: version, random item ID, received timestamp, UTType and byte count.
- The extension performs no backend request, auth, parsing, categorization or financial persistence and never stores original paths/account metadata in logs or manifests.
- Main app drains one item on activation, keeps the queue deterministic and uses content hash/item ID to avoid repeated-share duplication. Define cancel/retry/expiry cleanup without deleting unreviewed user input.
- Gate presentation on app unlock, data-store readiness and resolved user/guest scope. Serialize statement/backup URLs and modal presentation so cold launch, recovery and simultaneous incoming URLs cannot overwrite each other.
- Apply iOS file protection to staged bytes, exclude them from backup/indexing, and define a crash-safe lifecycle: atomic ready marker, retain through retry/cancel, explicit discard, bounded TTL and cleanup only after durable handoff.
- Enforce parser resource limits on both sides of the trust boundary: compressed/uncompressed bytes, rows/pages, nesting and wall time. Include XLSX ZIP bombs, malformed shared strings, password-protected files and CSV formula-like values in negative tests.
- Tests: UTType/signature matrix, security-scope balance, traversal/symlink/directory/zero/oversize rejection, atomic partial-copy crash, duplicate share, multiple queued files, locked/offline app, direct route and deferred route convergence.
- Device acceptance: Files app and T-Bank browser share sheet show honest `Open in Millio`/`Save to Millio` behavior; direct route opens review, deferred route survives extension termination and appears on next app activation.

### [ ] Phase 4 — integration, localization and device acceptance

- Add end-to-end in-memory integration test: preview DTO -> reviewed operations -> atomic graph -> balance engine/Cashflow fetch/totals visible without relaunch.
- Run focused backend bank-statement suite/build and iOS statement/product-factory/onboarding suites, then Cashflow + AccountsCore regression gate.
- Complete RU/EN/zh-Hans strings, VoiceOver order/actions, Dynamic Type, Reduce Motion and keyboard-safe final action.
- Capture 375/390 light/dark states: no file, processing, backend unavailable, unsupported, balance detected, manual balance, attention review, final confirmation, success.
- Test physical-device import with sanitized Alfa and T-Bank fixtures; verify no PII/amounts in logs and correct account/Cashflow results.
- Audit every ASI acceptance criterion and update plan/status/reflection. No production deployment in this phase.

### [ ] Phase 5 — separately authorized backend release

- Prepare immutable backend candidate and verify contract compatibility with the currently released iOS app.
- Record rollback artifact/procedure, run focused tests/build and preview-route smoke gate.
- Deploy only after explicit user authorization; verify new balance fields with sanitized fixture and confirm old-client compatibility.
- This phase does not authorize App Store/TestFlight publication.

## Verification

- Unit tests: backend balance extraction/contract; iOS decode, balance policy, reusable staging, onboarding coordinator, create-flow state and idempotency.
- Integration/build checks: atomic whole graph, balance unchanged by Cashflow projections, fingerprint dedupe, closed-month race, old/new schema compatibility, backend build and iOS simulator build.
- Acceptance criteria audit: ASI-C1…ASI-C30 each mapped to an automated test, screenshot or named manual device check.

## Stress-check

| Failure mode | Evidence / probability | Impact | Mitigation |
|---|---|---|---|
| Closing balance plus imported rows both affect balance | Existing apply already disables balance effect; regression probability medium | Critical double count | Preserve `affectsCardBalance=false`; invariant/integration tests |
| Bank format has no balance | Current v1 has no balance fields; high | Wrong fabricated balance | Required explicit manual confirmation |
| Stale statement presented as live | Statements have bounded period; high | Misleading current position | Always show `balance as of date`; no sync wording |
| Account saved but rows fail | Two-step naive flow; medium | Partial onboarding | One isolated-context commit through graph enricher |
| Mixed currency rows | Contract allows per-row currency; medium | Corrupt account attribution/totals | Fail closed before create |
| Closed month changes during review | Existing mutation policy; low/medium | Bypass month lock | Revalidate all dates at final staging |
| Double tap/retry | SwiftUI/network/user behavior; medium | Duplicate account and transactions | Stable onboarding ID, disabled applying state, persisted idempotency proof |
| Backend offline | Existing network dependency; medium | Cannot preview file | Clear retry/cancel; manual account creation remains available |
| Adapter template drift | Existing strict adapters; medium | Wrong balance extraction | Label/header fixtures, confidence/reasons, fail closed |
| Raw bank data leaks | File upload/preview path; high impact | Privacy/compliance incident | No persistence/logs/analytics of bytes or identifiers; redaction tests |
| 200-row review on weak device | Existing supported review size; low/medium | UI stalls | Reuse precomputed/lazy presentation; performance acceptance |
| Old app receives new payload | Backend contract evolution; medium | Decode failure | Optional additive fields or version negotiation; predeploy old-client contract test |
| OFX is offered before a parser exists | Current iOS/backend statement path does not support OFX; certain | Dead-end UX and false product promise | Register only PDF/CSV/XLSX in v1; add OFX only with adapter fixtures and contract tests |
| External file arrives without an active create draft | Normal Files/Share Sheet entry; high | File has no target account or is attached to the wrong flow | Preview first, then explicit destination choice; no persistence before confirmation |
| Two coordinators pass check-then-save | IDs/source keys are not storage-unique; medium | Duplicate account graph and cashflow rows | Two-context race test; serialized writer + deterministic IDs or persisted uniqueness gate |
| CloudKit delivers a partial graph | Local save is not a cross-device transaction; low/medium | Account without anchor/rows or orphan projections | Define incomplete-graph detection and deterministic repair/fail-closed behavior |
| Existing fingerprint belongs to another account | Global statement dedupe already exists; medium | New account silently misses or steals history | Compare attribution; show typed conflict; never silently reparent |
| Manual balance inherits statement end date | Operations export may contain no balance evidence; high | Historically false balance anchor | Require an explicit `balance as of` date; do not infer it from operation period |
| Incoming file appears while app is locked/not ready | App lock and launch recovery already exist; medium | Privacy leak, lost route or wrong data scope | Queue until unlock/store/scope readiness; serialize URL/modal routing |
| App Group copy survives indefinitely or enters backup | Planned local inbox contains raw bank data; medium | Data-retention/privacy breach | File protection, backup/index exclusion, crash-safe handoff and bounded TTL |
| Compressed-size check misses parser bomb | XLSX is ZIP-based; low probability/high impact | Extension/app/backend memory or CPU exhaustion | Compressed + expanded limits, row/page/time caps and adversarial fixtures |
| Supplied T-Bank file spans two months | Real fixture proves this; certain for current test | v1 cannot legally apply it under one-month contract | Use as negative fixture with explicit rejection; no hidden split |

## Journal

- 2026-08-16: traced current create-flow, AccountsCore factory, Cashflow statement preview/review/apply and backend adapters. Confirmed that parser/category/dedupe/account-attribution foundations already exist and imported statement rows intentionally do not mutate balance.
- 2026-08-16: selected closing-balance snapshot + Cashflow projection model; rejected replaying statement rows into AccountEvent and rejected a two-save onboarding flow.
- 2026-08-16: research/spec/plan created under `$millio-bulletproof`. No production code, schema, tests or remote resources changed.
- 2026-08-16: Phase 1 additive contract implemented. Backend accepts optional exact-decimal opening/closing evidence, validates date/currency/source/confidence and forces `needs_review` when bank anchors do not reconcile. iOS decodes both old payloads without `balances` and new typed evidence without a `Double` boundary.
- 2026-08-16: Sanitized Alfa XLSX and T-Bank `Справка о движении средств` fixtures prove turnover totals only and therefore return no balance evidence. Auto-extraction was deliberately not invented. A sanitized real statement with an explicit opening/closing balance is required to finish adapter mapping.
- 2026-08-16: Verification: backend bank-statement suite 87/87 passed; Nest build passed; iOS `CashflowStatementImportContractTests` passed on iPhone 17 Pro simulator, iOS 26.5. One unrelated AppIntents metadata warning remains.
- 2026-08-16: Real T-Bank operations XLSX characterized locally: 67 rows, operations/transfers and bank-specific columns, but no exact opening/closing balance. No real values or identifiers were copied into repository artifacts.
- 2026-08-16: External share UX added as Phase 3A. Chosen public document ingress for direct launch plus a minimal App Group inbox extension for deferred save; rejected private force-launch hacks.
- 2026-08-16: Adversarial stress-test found three release blockers: unsupported OFX was promised by ingress, external files had no target flow without an active draft, and `sourceTransactionID` idempotency lacked storage uniqueness. Spec expanded to ASI-C30; Phase 2/3A now require concurrency, CloudKit reconciliation, attribution-conflict, app-lock/scope and raw-file lifecycle gates.
- 2026-08-16: Phase 2 implemented. Statement validation/insertion is now persistence-neutral and reused by ordinary Cashflow import. `AccountStatementOnboardingCoordinator` serializes local writers, revalidates the final command, stages Account + opening anchor + reviewed Cashflow rows in one disposable context and performs one durable save.
- 2026-08-16: Stable onboarding marker, payload digest, deterministic graph IDs and statement fingerprint identities make identical retries converge and conflicting retries fail closed. Existing fingerprints assigned to another or no account are explicit conflicts; rows are never silently reparented.
- 2026-08-16: Scope reconciliation now identifies imported rows by source + statement fingerprint. The new merge test exposed that Cashflow export carried import provenance while import dropped it; round-trip restoration was fixed and `uniqueID` is now preserved when present.
- 2026-08-16: Verification passed on iPhone 17 Pro simulator: 26 focused onboarding/apply/scope-merge tests plus 8 AccountProductFactory regression tests. Local SwiftData commit is atomic; this does not claim cross-device CloudKit transaction atomicity. Deterministic reconciliation handles duplicate statement projections, while partial remote graph recovery remains an explicit Phase 4 integration/device gate.
- 2026-08-16: Phase 3 implemented. Debit-card and bank-account create forms now expose an optional statement CTA; credit cards, deposits and other products do not. The flow reuses the existing preview controller, category/disposition policies and `CashflowStatementReviewView` through an explicit review context instead of copying a reviewer.
- 2026-08-16: Onboarding fixes the pending account ID and never shows an account picker. Bank-declared closing balance is shown with provenance/date; absent balance requires an explicit manual amount/date confirmation and is never derived from turnover. Currency mismatch, multi-month scope, reconciliation failure, duplicate attribution and backend errors fail before persistence while the parent form remains intact.
- 2026-08-16: Final confirmation shows account identity, balance/date, included/excluded/reclassified counts, currency totals and the unchanged-balance guarantee. Zero included rows remain legal only for account onboarding with an explicit balance snapshot; ordinary Cashflow import still rejects an empty apply.
- 2026-08-16: Verification: 29 focused create-flow/controller/coordinator/apply tests passed; 16 localization-catalog regression tests and 5 all-presets graph tests passed. Simulator build-for-testing passed. Visual, accessibility and full RU/EN/zh-Hans copy acceptance remain Phase 4 gates.
- 2026-08-16: Phase 3A implemented. PDF/CSV/XLSX are registered for direct open; OFX remains intentionally absent. Direct and Share Extension routes converge on one protected App Group inbox and the existing preview/review controller. The extension is named `Save to Millio`, accepts exactly one file and performs no network or financial persistence.
- 2026-08-16: Incoming bytes are bounded to 25 MiB, checked by UTType plus signature, copied through a partial file, protected until first unlock, excluded from backup, deduplicated by SHA-256 and expired after seven days. Locked/store-unready/modal-busy states retain the deterministic queue. An active account-onboarding draft consumes the queued preview directly; otherwise the user explicitly chooses create-account or ordinary Cashflow import.
- 2026-08-16: Verification passed: the complete `millio` build-for-testing (including widget and statement Share Extension targets) succeeded, and 4 focused ingress tests passed on iPhone 17 Pro simulator (signature/type policy, directory/symlink/zero/mismatch rejection, dedupe/TTL and readiness gating). Physical Files/T-Bank Share Sheet acceptance remains a named Phase 4 device gate.
