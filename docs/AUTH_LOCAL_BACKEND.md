# Auth Backend Configuration

## Configuration

- `AUTH_BASE_URL` can be provided directly from environment, but `xcconfig` should use split fields because `http://` is parsed as a comment there.
- Default app values are:
  - `AUTH_BASE_SCHEME = https`
  - `AUTH_BASE_HOST = api.udzutech.com`
  - `AUTH_BASE_PORT =`
  - `AUTH_BASE_PATH = /api/v1`
- For local backend development, override the values in `millio/Config/Secrets.local`, for example:
  - `AUTH_BASE_SCHEME = http`
  - `AUTH_BASE_HOST = localhost`
  - `AUTH_BASE_PORT = 3000`
  - `AUTH_BASE_PATH = /api/v1`

## Architecture

- `AuthAPIClient` talks to NestJS endpoints.
- `AuthService` owns token lifecycle, refresh, and logout.
- `AuthManager` is the SwiftUI-facing state holder injected through the app environment.
- `AuthDiagnosticsLogger` writes a safe client-side trace for the full auth flow.
- `AuthErrorMapper` converts typed auth failures into user-facing messages without collapsing everything into one generic toast.
- `MarketAPIClient` reuses the same backend base URL and gets Bearer tokens from `AuthService`.
- `refreshToken` is stored in Keychain only.
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
