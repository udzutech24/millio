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

## Global Rate Source

- The app-wide preferred rate source is stored in `UserDefaults` under key `"preferred_rate_source"`.
- Default value is `.millio`; unknown raw values fall back to `.millio`.
- **Single write point:** `CurrencyRateService.setRateSource(_ source:)` is the only place that writes `preferred_rate_source`. No other code may write to this key.
- `CurrencyRateService.shared` is initialized from `RateSourcePreferenceStore.shared.preferred` at app launch, so the persisted choice survives restarts.
- `buildFallbackChain()` constructs the provider chain dynamically: `[preferred] + RateSource.allCases.filter { $0 != preferred }`. The preferred source is always first; no hardcoded order.
- Changing the source calls `setRateSource`, which:
  1. Updates `rateSource` and writes `preferred_rate_source` via `RateSourcePreferenceStore`.
  2. Increments `cacheGeneration` so any in-flight refresh with the old generation is discarded.
  3. Clears `cachedRates` (leaving `["USD": 1.0]`) and resets `lastUpdateTS`.
  4. Posts `Notification.Name.currencyRateSourceDidChange` on `NotificationCenter.default`.
- `FinanceViewModel` and `CashflowViewModel` observe `currencyRateSourceDidChange` and trigger their respective recalculation methods. Observers are removed in `deinit`.
- `DataResetService.reset()` clears `preferred_rate_source` via `RateSourcePreferenceStore.shared.reset()`.

## Widget Sync Source

- The home-screen widget reads the rate source from the shared App Group `UserDefaults` under `CurrencyWidgetShared.Keys.rateSource`.
- Since Phase 1c, `CurrencyWidgetSyncService.bootstrapFromStandardDefaults` copies `"preferred_rate_source"` (not `"conv_rate_source"`) to the widget container.
- `CurrencyWidgetSyncService.knownRateSources` is derived from `RateSource.allCases.map(\.rawValue)` — it grows automatically as new sources are added.
- Widget-source sync on source change is performed exclusively in `RateSourcePickerViewModel.selectSource`, not in `ConverterViewModel`.

## Converter Scope

- Converter keeps independent `conv_*` settings by design.
- Profile `primary`/`favorites` do not override converter selected currencies.
- Converter selected currency list must stay unique: the same code cannot be selected in two different rows.
- **Converter rate source override (`conv_rate_source`)** is read and written only via `RateSourcePreferenceStore.converterOverride`. A `nil` value means "follow the global preferred source".
  - Setting the converter source to the current preferred → clears the override (stores nil).
  - Setting it to a different source → stores the override raw value.
  - `conv_rate_source` is **not** mirrored to iCloud or to the widget; it is a local session preference.
- The converter UI shows `rateSourceDisplayLabel`: `"По умолчанию (X)"` when no override is set, or `source.title` when an override is active (F11 contract).
- Converter supports fiat + crypto codes:
  - fiat rates are loaded from the active `RateSource` (global preferred or converter override);
  - crypto rates are loaded from CoinGecko and merged into converter rates as `1 USD = X CRYPTO`.
- Crypto visibility is paywalled by `EntitlementPolicy.canUseConverterCrypto`:
  - Free: crypto is hidden and removed from selected converter currencies;
  - Pro: crypto can be added and converted.
- `visibleSources(context:primaryCurrencyCode:favoriteCurrencyCodes:)` must be used in all rate-source pickers (profile and converter); `RateSource.allCases` must not be iterated directly in UI.

## Rate Source Picker (Profile)

- Accessible from Profile → «Источник курсов» (`NavigationLink`).
- Displays a card per `visibleSources` (filtered by `RateSourcePickerViewModel.visibleSources()`).
- Each card shows preview rates for 4–5 favorite currencies against `primaryCurrencyCode`, loaded in parallel via `withTaskGroup`.
- The current global source is marked with a filled checkmark (`checkmark.circle.fill`).
- Tapping a card calls `selectSource(_:)` immediately — no «Save» button.
- `selectSource(_:)` calls `CurrencyRateService.shared.setRateSource` and syncs the widget via `CurrencyWidgetSyncService`; it does **not** write `store.preferred` directly.

## CBR Routing

- `.cbr` has `capability.scope == .rubOfficialDaily` — optimized for RUB-involved pairs.
- **RUB-pair routing:** `CurrencyRateService.getRate(from:to:)` detects that the active source is `.cbr` and at least one of `from`/`to` is `"RUB"`. In this case, the snapshot from `CBRLatestRateProvider` is used directly.
- **Non-RUB-pair routing:** When `.cbr` is the preferred source but the requested pair does not involve RUB (e.g. EUR→CNY), `CurrencyRateService` transparently creates a temporary `globalFiat` service instance and delegates the call. No error is surfaced to the caller.
- **USD-base normalization:** `CBRLatestRateProvider.normalizeToUSD(rubPerCurrency:)` converts CBR's `rubPerX` values to a USD-base dict (`cachedRates["X"] = rubPerUSD / rubPerX`). Missing USD in the XML → returns `[:]` → error thrown → fallback chain kicks in.
- **`refreshRates()` for `.cbr`:** bypasses `RateRepository` and calls `cbrLatestProvider.fetchRates()` directly, then persists the result to `UserDefaults` under the same per-source keys used by the repository.
- **Picker visibility:** `RateSourcePickerViewModel.visibleSources()` includes `.cbr` when **at least one** of the following is true: `primaryCurrencyCode == "RUB"`, `favoriteCurrencyCodes` contains `"RUB"`, or the resolved app locale language code is `"ru"` (covers both explicit Russian and system=Russian). In all other cases `.cbr` is hidden.

## Historical Rates Policy

- Historical `exact` rates are resolved via provider chain:
  1. `Frankfurter` (ECB-aligned default source).
  2. `CBR` fallback for RUB-involved pairs (`RUB -> X` / `X -> RUB`).
- If both providers miss, app falls back to:
  - previously cached historical rate (`previous`);
  - then current spot rate (`current`) as estimated value.
- Manual `Refresh rates` clears in-memory negative caches for historical providers,
  so transient misses can be retried without app restart.
