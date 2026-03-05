# Monetization: Free vs PRO

## Current rules in code

- Converter:
  - Free: fiat currencies.
  - PRO: crypto currencies.
- Finances / tracked tickers (stocks + crypto):
  - Free: up to 5 tracked tickers.
  - PRO: unlimited tracked tickers.
- Cashback cards:
  - Free: up to 3 cards for cashback setup.
  - PRO: no card count limit.
- Cashflow:
  - Free: no additional monetization limits.

## Source of truth

- `EntitlementPolicy` in `Core/AppState/AppState.swift` is the only place for limits.
- UI/modules must use policy methods instead of hardcoded checks.
