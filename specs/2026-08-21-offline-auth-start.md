# Offline authenticated start specification

## Goal

An already authenticated user with a mounted local data scope must see the ready application immediately, even when remote token refresh cannot reach the backend.

## Contract

- `AppLifecycleState.launching` resolves to `launching`.
- `AuthManagerStatus.restoring` with no authenticated session resolves to `launching`.
- `AuthManagerStatus.restoring` with an authenticated cached session and lifecycle `ready` resolves to `ready`.
- Failed or slow refresh does not erase local data or block the UI.

## Non-goal

This change does not make an unreachable backend reachable. Russian reachability needs a separate deployed endpoint and network validation.
