# Currency Policy

## Profile Currency Contract

- `primaryCurrencyCode` is the app-level base currency for defaults.
- `favoriteCurrencyCodes` contains only additional quick-pick currencies.
- `favoriteCurrencyCodes` never includes `primaryCurrencyCode`.
- Favorites are normalized (trim + uppercase + unique) and limited to **5** items.
- Effective profile setup is always: **1 primary + up to 5 favorites**.
- When `primaryCurrencyCode` changes, previous primary is prepended to favorites (if different), then normalization is applied.

## Runtime Behavior

- Primary currency can be changed only from Profile (`primaryCurrencyCode`).
- In `Cashflow` and `Finances`, display currency selection is session-only (preview mode):
  - it affects only visualization;
  - accounting source data and calculations remain based on saved amounts;
  - after leaving the module, display currency resets from Profile primary currency.
- Stored display currencies are migrated only for account-specific modules that keep persisted display settings:
  - `card_display_currency`
  - `investment_display_currency`
  - `credit_display_currency`

## Converter Scope

- Converter keeps independent `conv_*` settings by design.
- Profile `primary`/`favorites` do not override converter selected currencies.
