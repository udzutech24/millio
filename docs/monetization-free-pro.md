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

## Debug override and diagnostics

- Profile now has a dedicated debug toggle for `debug premium override`.
- The toggle changes only the debug override. It does not pretend to cancel a real App Store subscription.
- Profile also has a `Premium diagnostics` screen that shows:
  - effective access source: `Free` / `Trial` / `Subscription` / `Debug premium`
  - current premium state
  - all known monetization points in the app

## Code locations for monetization points

- Converter crypto:
  - `millio/UI/Services/Courses/ConverterView.swift`
- Tracked tickers in finances:
  - `millio/UI/Services/Finances/Editors/FinanceAddAccountView.swift`
  - `millio/UI/Services/Finances/InvestmentEditorView.swift`
- Tracked tickers during quick setup:
  - `millio/UI/QuickSetup/QuickSetupViewModel.swift`
  - `millio/UI/QuickSetup/QuickSetupApplier.swift`
- Cashback card limit and screenshot import:
  - `millio/UI/Services/Cashback/CashbackView.swift`
- Premium widget behavior:
  - `millioCurrencyWidgetExtension/CurrencyConverterPremiumWidget.swift`
