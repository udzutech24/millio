# Spec: offline resilience for backend outage

## Problem

When the single backend origin is unavailable, core local finance is mostly survivable, but market data disappears after relaunch and held-symbol metadata sync is silently lost. The prior broad proposal incorrectly implied that all local finance data would later sync to the backend.

## Goal

During a backend outage, a previously initialized user can use local finance without data loss; market views show the last known data with an honest stale timestamp; the latest held-symbol snapshot is delivered after a future successful app-active connection.

## Acceptance criteria

- [ ] **OR-0 Five-second local-ready deadline:** startup never waits for backend availability to resolve local finance. At T+5 seconds after launch, a returning user is in the normal local app; if the availability probe has not succeeded, backend state is `.offline` and an always-available top icon is shown. A later successful probe changes only that state, not the data scope or navigation tree.
- [ ] **OR-1 Local finance:** outage/timeout/5xx during startup never blocks opening the last resolved user SwiftData scope when the cached session is valid for resilience fallback.
- [ ] **OR-2 Durable market read:** after successful authenticated market responses, supported market screen data survives process termination, is scope-isolated, and is returned on transport/5xx failure with source timestamp and stale state.
- [ ] **OR-3 No false precision:** stale data is visually and accessibly labelled; a missing cache is an explicit unavailable state, never fabricated values.
- [ ] **OR-3a Offline chart continuity:** finance graph and converted totals use locally persisted historical FX rates and asset closes when present. A stale snapshot renders immediately with its source time; absent evidence renders an explicit unavailable state and never an indefinite loading spinner.
- [ ] **OR-4 Coalesced portfolio delivery:** while offline, multiple portfolio changes leave one durable latest normalized symbol snapshot per scope. No quantities, cost basis, pnl, transaction history, credentials, or raw user ID are persisted in this queue.
- [ ] **OR-5 Safe delivery:** backend accepts a scope-local monotonic revision/idempotency key; replay of the same snapshot is harmless and an older revision cannot replace a newer accepted snapshot.
- [ ] **OR-6 Lifecycle:** one scheduler retries only when app is active and authenticated, on explicit refresh, startup, and network recovery; it serializes sends, uses capped exponential backoff with jitter, and honours `Retry-After`.
- [ ] **OR-7 Account isolation:** logout, account switch, data reset and restore cannot deliver or display another scope's cache/queue data.
- [ ] **OR-8 Observability:** safe aggregate events distinguish cache hit/stale/miss, queued/delivered/permanent failure and server availability. Logs contain no tokens, symbols are not sent to Crashlytics as user data, and raw payloads are not logged.
- [ ] **OR-9 Verification:** deterministic unit tests cover the failure matrix; iOS focused tests and backend e2e contract tests pass before release.

## Scope

- iOS local persistence, stale UI state, connection-aware retry scheduler, portfolio snapshot queue.
- NestJS contract and Prisma migration necessary to protect portfolio snapshot ordering/idempotency.
- Documentation and tests.

## Non-goals

- Live synchronization/merge of financial SwiftData entities between devices.
- Uploading finance transactions, amounts or histories to the backend.
- Guaranteed delivery while iOS is terminated.
- Automatic CloudKit restore or changing backup semantics.
- Deploying HA/failover infrastructure in this work item.

## Constraints and risks

- SwiftData schema additions must be optional and participate in backup/import without making cache data authoritative.
- “Offline” here means *Millio backend unavailable or still unconfirmed*, not a claim that the device has no Internet. The icon must have an accessible label and explanatory detail; it must not be a blocking modal.
- A queue for arbitrary POST/PUT/DELETE operations is forbidden until each endpoint has an idempotency and ordering contract.
- Cache freshness depends on payload type; choose explicit per-endpoint bounds instead of a universal 30-second TTL.
- Server revision comparisons must be atomic at database level; in-memory tracking is invalid across replicas.
