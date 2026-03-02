# Currency Policy

## Profile Currency Contract

- `primaryCurrencyCode` is the app-level base currency for defaults.
- `favoriteCurrencyCodes` contains only additional quick-pick currencies.
- `favoriteCurrencyCodes` never includes `primaryCurrencyCode`.
- Favorites are normalized (trim + uppercase + unique) and limited to **5** items.
- Effective profile setup is always: **1 primary + up to 5 favorites**.
- When `primaryCurrencyCode` changes, previous primary is prepended to favorites (if different), then normalization is applied.

## Runtime Behavior

- In `Cashflow` and `Finances`, display currency selection is session-only (preview mode):
  - changes are used only for current screen session;
  - after leaving and reopening the module, display currency is reset from profile settings.
- When `primaryCurrencyCode` changes, stored module display currencies are migrated only if they were equal to the previous primary currency:
  - `card_display_currency`
  - `investment_display_currency`
  - `credit_display_currency`
- This keeps modules that followed primary in sync, while preserving explicit custom choices.

## Converter Scope

- Converter keeps independent `conv_*` settings by design.
- Profile `primary`/`favorites` do not override converter selected currencies.
