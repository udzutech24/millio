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
- Converter selected currency list must stay unique: the same code cannot be selected in two different rows.
- Converter supports fiat + crypto codes:
  - fiat rates are loaded from selected `RateSource` (`erapi`/`frankfurter`);
  - crypto rates are loaded from CoinGecko and merged into converter rates as `1 USD = X CRYPTO`.
- Crypto visibility is paywalled by `EntitlementPolicy.canUseConverterCrypto`:
  - Free: crypto is hidden and removed from selected converter currencies;
  - Pro: crypto can be added and converted.

## Historical Rates Policy

- Historical `exact` rates are resolved via provider chain:
  1. `Frankfurter` (ECB-aligned default source).
  2. `CBR` fallback for RUB-involved pairs (`RUB -> X` / `X -> RUB`).
- If both providers miss, app falls back to:
  - previously cached historical rate (`previous`);
  - then current spot rate (`current`) as estimated value.
- Manual `Refresh rates` clears in-memory negative caches for historical providers,
  so transient misses can be retried without app restart.
