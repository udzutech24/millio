# Plan: offline resilience for backend outage

**Status:** IMPLEMENTATION IN PROGRESS — Phase 0 is not signed off.

## Inputs

- Research: `thoughts/research/2026-08-15-offline-resilience-stress-test.md`
- Spec: `specs/2026-08-15-offline-resilience.md`

## Decision

- Chosen approach: retain local SwiftData as finance source of truth; add durable stale cache for server reads and a coalesced latest-snapshot queue solely for existing portfolio-symbol metadata.
- Rejected: universal SwiftData sync, generic request queue, CloudKit as live-sync transport, in-memory-only retries.
- Rollback: feature flag each cache/queue reader; persisted cache rows are non-authoritative and may be ignored. Do not remove user finance data. Backend migration must be additive; old clients keep current `PUT /portfolio/symbols` behaviour until rollout completes.

## Preconditions / release gates

- [ ] Product owner explicitly confirms this scope does **not** promise cross-device live finance sync.
- [ ] Inventory every `MarketDataClientProtocol` response: whether it is cacheable, max stale age, scope, and UI state owner.
- [ ] Privacy review approves cache retention and deletion semantics.
- [ ] Existing red test/build gates are recorded separately; no phase may relabel unrelated failures as this feature's pass.

## Phases

- [ ] **Phase 0 — five-second local-ready path, availability state and failure harness**
  - Replace the blocking startup availability resolution with a deterministic local runtime resolution plus one non-blocking availability probe. The 5-second deadline is owned by a testable clock/deadline policy, not by a scattered `Task.sleep` in a view.
  - Introduce a small `BackendAvailability` state machine: `checking`, `online`, `offline(reason)`. It is independent from endpoint selection and auth state; one failed request must not force sign-out.
  - At T+5, publish `.offline(.probeTimedOut)` when no success is known, continue `initializeColdStart`, and retain a task that may transition to `.online` on a later verified response. Never probe preferred and fallback serially when they are the same URL.
  - Add one reusable top-level status icon in the root app chrome (not duplicated per screen). It is non-blocking, VoiceOver-labelled, opens a concise explanation/retry action, and is visible only for `.offline`; `checking` remains quiet.
  - Define `CacheState<Value>` (`fresh`, `stale`, `unavailable`) and typed retryable/permanent error classification; do not expose raw HTTP errors in views.
  - Add deterministic clock, network reachability abstraction, HTTP stubs and lifecycle test harness.
  - Map OR-0…OR-9 to tests before production edits.
  - Evidence: tests prove T+5 local ready/indicator, late recovery, failure classification, no scope reset, DNS, 429, 5xx, 401 and cancellation.

- [ ] **Phase 1 — durable read cache**
  - Add a scope-keyed, schema-versioned SwiftData cache record (payload is validated `Codable`, fetched timestamp, expiry/max-stale metadata). Keep it outside finance calculation models and exclude it from financial export/import semantics unless explicitly required.
  - Wrap only selected read endpoints after the Phase-0 inventory. Read cache first; refresh opportunistically; on retryable failure return stale only within agreed max age.
  - UI renders `fresh/stale/unavailable`, localized and VoiceOver-accessible.
  - Tests: disk reopen, malformed payload eviction, scope isolation, expiry boundary, stale fallback, no fallback for 401/forbidden.
  - Graph continuity: reuse existing scope-local `HistoricalRate` and `HistoricalAssetPrice` evidence before any network request. A stale quote must not hold the finance graph/header spinner; show its timestamp at the graph consumer. Do not invent a second authority cache for financial valuations.

- [ ] **Phase 2 — server-safe portfolio snapshot contract**
  - Add an additive Prisma migration with `lastAcceptedRevision` (or a dedicated sync-state row) keyed by user; atomically reject/ignore lower revisions and replay the same revision with the stored response.
  - Extend request/response contract with `clientSnapshotID` and monotonically increasing `revision`; validate UUID/size and bind both to the authenticated user.
  - Retain server throttling and specify `429 Retry-After` behaviour.
  - Tests: duplicate delivery, response-lost retry, stale revision after newer one, concurrent requests, two server instances/transaction boundary, unauthorised caller.

- [ ] **Phase 3 — iOS coalesced portfolio queue and scheduler**
  - Persist one latest normalized snapshot per hashed data scope: revision, snapshot ID, symbols, attempt metadata and next eligible attempt. Replace atomically on each local change.
  - Serialize flushes in an actor. Triggers: app active, authenticated startup, explicit market refresh, path changes to satisfied. Do not claim OS-guaranteed terminated-app delivery.
  - On success clear only the matching revision; on retryable failure retain it and schedule capped exponential backoff with full jitter; on 401 stop and require auth resolution; on validation/4xx surface safe permanent-failure state.
  - Tests: termination/relaunch, rapid edits coalesce, sign-out/account switch isolation, cancellation, retry storm, old request completes after new revision, restore/data-reset behaviour.

- [ ] **Phase 4 — UX, observability and release proof**
  - Add a compact degraded-service indicator that does not block local finance; stale market timestamp must be visible at the consuming screen, not only in a global banner.
  - Emit aggregate safe telemetry and document support diagnostics/runbook; no token/payload/PII logging.
  - Run focused iOS unit tests, focused backend unit/e2e contract tests, then the full gates that are currently healthy. Perform physical-device outage exercise: launch offline with prior session, edit local finance, terminate/relaunch, restore network, verify stale data and eventual symbol delivery.

## Failure matrix that blocks phase sign-off

| Scenario | Must prove |
|---|---|
| Probe has no response at T+5 | OR-0; root local UI remains usable and icon appears exactly once |
| Probe succeeds at T+5.1 | icon clears without navigation/data-scope recreation or user-visible reset |
| Server unreachable before startup | OR-1; no forced logout/no guest-store data loss |
| Server dies after local investment edit | local edit is durable; exactly one latest symbol snapshot remains |
| HTTP request applied but response lost | same revision replay does not duplicate/rewind server state |
| Three edits while offline, then reconnect | only newest revision is delivered |
| Device A/B, old A reconnects last | lower revision cannot overwrite newer accepted revision |
| Logout then another user login | no cache/queue data crosses scope |
| Cache payload corrupted / app downgraded | entry is discarded safely; network fallback or honest unavailable UI |
| 401 / forbidden / invalid input | no blind retry and no stale data is presented as authorised data |
| CloudKit unavailable independently | local finance and API resilience remain independent |

## Verification

- Unit tests: cache repository, state mapping, queue actor, retry schedule, lifecycle/scope isolation.
- Backend: PortfolioService unit tests plus e2e contract tests against Prisma transaction semantics.
- Integration/build checks: focused suites per phase, then iOS and NestJS full gates subject to existing unrelated blockers.
- Acceptance criteria audit: Phase 4 records evidence for every OR-1…OR-9 and explicitly records any untested physical-device step.

## Stress-test verdict

**GO only for the narrow slice above.** The original universal outbox/"everything synchronizes later" plan is **NO-GO**: it conflicts with the documented local-only finance architecture and lacks a financial conflict, privacy and server-authority model. High availability of the single API origin remains a separate infrastructure plan; it must be tested with health checks, alerting, backup restore and controlled failover before any availability claim. The T+5 indicator is an outage UX fallback, not proof of device-wide offline state.

## Change log

- 2026-08-15 — created from outage analysis; status `STRESS-TESTED`.
- 2026-08-15 — added product requirement: T+5 local-ready deadline and non-blocking top offline icon; blocking two-probe startup is explicitly rejected.
- 2026-08-15 — Phase 0 started. Static endpoint selection and a separate availability state machine/root indicator were added. Sign-off is blocked: `AuthManager.restoreSession()` still participates in the cold-start critical path and can wait for the backend, so OR-0/OR-1 are not yet proven. Focused xcodebuild also did not start because CoreSimulator reported `simdiskimaged` unavailable and package dependencies could not resolve. No later phase may start until the local-ready path is independently bounded and this gate is repaired/re-run.
- 2026-08-15 — Added explicit graph-continuity requirement (OR-3a) after observing finance UI with locally available accounts but a loading chart during outage. `CurrencyRateService` now reads a persisted repository snapshot before network and returns an existing stale quote immediately while refreshing in the background. This is a Phase-1 precursor; timestamp/UI-state work and persisted market-close verification remain open.

## Phase 0 self-audit (in progress — not a sign-off)

- Implemented: static backend runtime resolution; one non-blocking availability probe; pure `checking`/`online`/`offline(reason)` transition state; deadline transition at T+5; one root-level VoiceOver-labelled icon with explanation and Retry; late probe success changes availability only; cold start now binds the locally persisted auth session snapshot before running refresh-token I/O in the background.
- Tentatively addressed: the former duplicated sequential 8-second runtime probes (part of OR-0).
- Not closed: OR-0, OR-1 and OR-9. The required UI/lifecycle test has not run; localization strings for the new control still need catalog entries; background terminal-auth handling needs an explicit scope-transition audit.
- Test evidence: `xcodebuild ... -only-testing:millioTests/BackendAvailabilityStateMachineTests -only-testing:millioTests/BackendStartupResolverTests test` failed before compilation: CoreSimulator `simdiskimaged` was unavailable and Xcode could not resolve package dependencies.
- Remaining risks: current probe task awaits the five-second deadline before consuming an early failure; retry/lifecycle handling is intentionally incomplete until the cold-start contract is corrected and verified.
