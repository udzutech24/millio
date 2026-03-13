# Auth Backend Configuration

## Configuration

- Backend endpoints are defined in one place:
  - `RU_API_BASE_URL = https://apiru.udzutech.com/api/v1`
  - `DE_API_BASE_URL = https://api.udzutech.com/api/v1`
- Startup resolver rule:
  - country `RU` selects `RU_API_BASE_URL`
  - every other country code, including missing/unknown, selects `DE_API_BASE_URL`
- The app probes `GET /runtime/server-info` on startup, logs region/base URL mismatches, and falls back to the secondary backend once if the preferred backend does not answer.
- The selected backend is kept for the current app session and reused by both `AuthAPIClient` and `MarketAPIClient`.
- The auth welcome screen always shows a compact backend status banner, including TestFlight/release builds, so QA can verify the exact login target server before signing in.
- QA/debug override is available in debug builds through:
  - `BACKEND_FORCE_REGION = RU|DE`
  - `BACKEND_FORCE_BASE_URL = https://...`
- Legacy `AUTH_BASE_*` keys remain only as a compatibility fallback for local-only tooling/tests and should not be treated as the main source of truth anymore.
- For local backend development, override the values in `millio/Config/Secrets.local`, for example:
  - `DE_API_BASE_URL = http://localhost:3000/api/v1`
  - `RU_API_BASE_URL = http://localhost:3001/api/v1`

## Architecture

- `AuthAPIClient` talks to NestJS endpoints.
- `AuthService` owns token lifecycle, refresh, and logout.
- `AuthManager` is the SwiftUI-facing state holder injected through the app environment.
- `AuthDiagnosticsLogger` writes a safe client-side trace for the full auth flow.
- `AuthErrorMapper` converts typed auth failures into user-facing messages without collapsing everything into one generic toast.
- `MarketAPIClient` reuses the exact same runtime-selected backend base URL and gets Bearer tokens from `AuthService`.
- `refreshToken` is stored in Keychain only, namespaced by backend base URL/region.
- `accessToken` is kept in memory and renewed through `/auth/refresh`.
- SwiftData is isolated by session scope:
  - guest mode uses `millio_guest` persistent store
  - authenticated mode uses `millio_user_<sha256(userId)>` persistent store
  - switching auth session swaps `ModelContainer`, so guest cannot read signed-in user data

## Flow

1. Open Profile.
2. Tap `Sign in with Apple`.
3. `AuthManager` logs the start of the Apple Sign In attempt and blocks duplicate in-flight auth actions.
4. After Apple returns a credential, the app logs only safe metadata:
   - token presence and length
   - email/name presence
   - no raw `identityToken`, `accessToken`, or `refreshToken`
5. `AuthAPIClient` sends every `/auth/*` request with:
   - `x-request-id: <UUID>`
   - `x-platform: ios`
   - `x-app-version: <app version>`
6. `AuthAPIClient` logs request start, HTTP status, response `x-request-id`, duration, and typed failure category.
7. `429 Too Many Requests` on `/auth/apple` and `/auth/refresh` starts a local cooldown:
   - the client respects backend `Retry-After` when present
   - otherwise it applies exponential backoff locally
   - repeated auth attempts during cooldown fail fast on the client instead of sending more requests
8. The backend response is persisted in memory plus Keychain.
9. `AuthService` explicitly logs:
   - access token received
   - refresh token received
   - token persistence success or failure
10. `AuthManager` explicitly logs:
   - session state updated
   - authorized navigation route resolved
11. `GET /auth/me` refreshes the current authenticated user with the same request diagnostics headers.

## Error Categories

- `noInternet`
- `timeout`
- `requestCancelled`
- `tls`
- `transport`
- `unauthorized`
- `forbidden`
- `rateLimited`
- `serverUnavailable`
- `invalidResponse`
- `tokenPersistence`
- `business`

## Notes

- `x-request-id` from the client and `x-request-id` returned by the backend are both logged, so one failed attempt can be matched across iOS and NestJS logs.
- Transport cancellation is logged but does not show a toast, which avoids noisy UI when a request is cancelled intentionally.
- Auth diagnostics live in the auth/networking layer, not in SwiftUI views.
