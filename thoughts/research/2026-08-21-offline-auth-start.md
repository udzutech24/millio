# Offline authenticated start

## Observation

With a locally restored authenticated session, the app synchronizes the SwiftData scope and reaches `ready`. In parallel, `AuthManager` refreshes the token remotely and temporarily reports `restoring`. `RootViewResolver` treated every `restoring` state as the launch screen, so an unavailable API hid already available local data behind the splash animation.

## Decision

Only the actual application lifecycle `launching`, or an unauthenticated session restoration, may show the launch screen. A cached authenticated session continues to the ready route while the remote refresh stays in the background.

## Russia connectivity finding

The client currently has no distinct Russian backend route: `BackendEndpoints.live` resolves only `DE_API_BASE_URL` and assigns it to both `ru` and `de`. Both bundled defaults also point to `https://api.iqdrop.ru/api/v1`. VPN therefore changes the network path to the same origin; it is not evidence that an in-app regional fallback works.
