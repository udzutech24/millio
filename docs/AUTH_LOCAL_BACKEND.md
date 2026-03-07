# Local Auth Backend

## Configuration

- `AUTH_BASE_URL` can be provided directly from environment, but `xcconfig` should use split fields because `http://` is parsed as a comment there.
- Default debug values are:
  - `AUTH_BASE_SCHEME = http`
  - `AUTH_BASE_HOST = localhost`
  - `AUTH_BASE_PORT = 3000`
  - `AUTH_BASE_PATH = /api/v1`
- For a physical device, override `AUTH_BASE_HOST` in `millio/Config/Secrets.local.xcconfig` with your machine IP, for example `192.168.1.10`.

## Architecture

- `AuthAPIClient` talks to NestJS endpoints.
- `AuthService` owns token lifecycle, refresh, and logout.
- `AuthManager` is the SwiftUI-facing state holder injected through the app environment.
- `refreshToken` is stored in Keychain only.
- `accessToken` is kept in memory and renewed through `/auth/refresh`.

## Flow

1. Open Profile.
2. Tap `Sign in with Apple`.
3. The app sends `identityToken`, plus optional Apple name/email, to `/auth/apple`.
4. The backend response is persisted in memory plus Keychain.
5. `GET /auth/me` refreshes the current authenticated user.
