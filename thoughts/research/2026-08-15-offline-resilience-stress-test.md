# Research: offline-resilience stress test

- Date: 2026-08-15
- Scope: iOS поведение при недоступности `api.iqdrop.ru`; без изменения remote infrastructure и без превращения backend в облачное хранилище финансов.

## Evidence

1. Основной finance state локален: README фиксирует SwiftData как source of truth, а CloudKit — только как snapshot backup/restore. Live CloudKit sync нет.
2. `AuthManager.restoreSession()` сохраняет последний user scope при transient error и применяет `lastKnownSession`; auth snapshot не содержит секретов. См. `Core/Auth/AuthService.swift`.
3. `MarketQuoteCacheStore` — actor только с RAM-кэшем и TTL; после перезапуска данных нет. См. `UI/Services/Investments/MarketData/TwelveDataClient.swift`.
4. `PortfolioSymbolsSyncService` отправляет текущий snapshot после login/investment change/restore, но при ошибке только логирует её. Очереди на диске, reconnect trigger и retry schedule отсутствуют. См. `Core/Portfolio/PortfolioSymbolsSyncService.swift`.
5. Backend `PUT /portfolio/symbols` заменяет набор symbols транзакционно и уже идемпотентен по содержимому snapshot. Он не хранит quantities, prices, pnl или history. См. `millio-back/src/portfolio/portfolio.service.ts`.
6. Backend имеет `/health`, Redis-backed cache/rate limit при конфигурации Redis и cache stale flag для market routes; это не даёт клиенту резервный origin или durable client cache.
7. Cold start сейчас ожидает `BackendStartupResolver.resolve()` до binding/auth/scope resolution. Каждый probe имеет timeout 8 seconds; при обычном запуске preferred и fallback указывают на тот же endpoint. Значит, недоступный backend потенциально задерживает local-ready путь до 16 seconds, а не до желаемых 5. См. `millioApp.resolveBackendRuntimeIfNeeded()` и `BackendRuntime.probe`.

## Current architecture and constraints

- Один production API origin: `BackendEndpoints.endpoint` и `alternate` возвращают тот же DE endpoint. Резервной площадки нет.
- URLSession error не доказывает, был ли серверный mutation применён до обрыва ответа. Повтор mutation допустим только при server-side idempotency contract.
- Финансовые данные не должны уходить в новый backend sync «заодно»: это меняет data residency, privacy model, API, storage, conflict semantics и стоимость.
- CloudKit backup не является очередью синхронизации: snapshot restore заменяет local store и не умеет merge.

## Stress-test findings

| Failure mode | Evidence / likelihood | Impact | Required mitigation |
|---|---|---|---|
| API node/DNS/TLS unavailable at launch | Known incident; current auth fallback exists only with previous session | Core finance usable for returning users; first login and market views degraded | Preserve cached session; do not gate local UI on API; visible non-blocking service state |
| Probe hangs at cold start | Two sequential 8-second probes target same origin | Local-ready UI is delayed beyond product tolerance | Resolve static runtime immediately; run one availability probe asynchronously with 5-second deadline and update state only |
| App killed while API down | RAM market cache is lost | Market screens blank after relaunch despite prior successful response | Per-user persistent read cache with `fetchedAt`, TTL and stale presentation |
| Request reached server, response lost | Normal at-least-once network failure | A generic mutation retry can duplicate money data | No generic financial mutation outbox. Snapshot portfolio retry is safe; future mutations require server idempotency key plus response replay |
| Portfolio changes while offline | Current service logs and forgets failure | Backend popularity/prewarm view becomes stale | Persist only the latest normalized portfolio snapshot, not an unbounded operation log |
| Multiple local edits during outage | Very likely in a personal-finance app | Old queued snapshot can overwrite newer snapshot | Single row per data scope; atomic replace; monotonic local revision; send latest snapshot only |
| Sign out / account switch with queued data | Current per-user stores are isolated but no queue exists | Cross-account disclosure if queue is globally keyed | Queue/cache key must include hashed `DataScope.storeConfigurationName`; purge only that scope on explicit sign-out/reset |
| Offline retry storm after recovery | Existing client/server throttles are narrow | 429s, battery/network waste | One serialized scheduler, exponential backoff + jitter, respect Retry-After; do not poll while app inactive |
| Two devices modify finance data | Product has snapshot backups, not live sync | Pretending reconnect will merge data loses transactions | Explicit non-goal; manual backup/restore remains current cross-device model |
| Backend is alive but market provider is not | Backend documents `isStale` fallback | False precision in price UX | Persist last good response; show timestamp and stale state, never label it live |
| CloudKit unavailable | Existing backup contract allows failure | Backup delayed; local work remains safe | Keep backup independent from API health; do not make it a prerequisite for local writes |

## Options considered

1. **Universal sync engine for all SwiftData models** — rejected. It introduces a cloud ledger and conflict protocol without a product decision, yet cannot safely infer finance merge semantics.
2. **Retry each failed request in memory** — rejected. Loses state on termination and risks retry storms/double mutations.
3. **Offline-resilience slice: persistent read cache + coalesced portfolio snapshot delivery** — chosen. Covers actual API-dependent data without altering the finance source of truth.
4. **Two production API origins / active-active failover** — deferred to an infrastructure runbook. Worth doing for availability, but it cannot replace durable local UX and requires explicit remote-change authorization.

## Recommended option and why

Deliver the smallest correct slice: local finance stays local; market reads are durable and marked stale; the only existing write-like integration (`portfolio/symbols`) gets one coalesced, scope-isolated snapshot queue. Reconnect is a best-effort trigger, not a guarantee of immediate background delivery. The server gets a minimal revision/idempotency contract before client retry is introduced.

The immediate UX requirement is stricter: **at T+5 seconds from launch, the app must enter `.ready` through the local path even if availability remains unknown.** At that deadline show the offline/degraded indicator only when the probe is still unresolved or has failed. A slow successful response arriving later changes the indicator to online; it must not recreate the data scope or block the user.

## Unknowns that block a later broad sync proposal

- Is cross-device live finance synchronization a separately approved product requirement?
- What retention/deletion promise applies to stored portfolio symbols and market cache?
- Is background delivery while the app is terminated required? iOS does not guarantee it; that needs a specific BGTask/product policy.

## Relevant files/tests

- `millio/README.md`
- `millio/Core/Auth/AuthService.swift`
- `millio/Core/Portfolio/PortfolioSymbolsSyncService.swift`
- `millio/Core/Portfolio/PortfolioSymbolsAPIClient.swift`
- `millio/UI/Services/Investments/MarketData/TwelveDataClient.swift`
- `millio-back/src/portfolio/portfolio.controller.ts`
- `millio-back/src/portfolio/portfolio.service.ts`
- `millio-back/test/app.e2e-spec.ts`
