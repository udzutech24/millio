# Monetization: Free vs PRO

## Current rules in code

- Converter:
  - Free: fiat currencies.
  - PRO: crypto currencies.
- Finances / market assets:
  - Free: stocks and crypto are locked.
  - PRO: stocks and crypto are available.
- Finances / tracked tickers (stocks + crypto):
  - Free: up to 5 tracked tickers.
  - PRO: unlimited tracked tickers.
- Finances / products:
  - Free: up to 15 products total across cards, credits, and investments.
  - PRO: no product count limit.
- Finances / charts:
  - Free: charts are locked.
  - PRO: charts are available.
- Cashback cards:
  - Free: up to 3 cards for cashback setup.
  - PRO: no card count limit.
- Cashback categories:
  - Free: up to 10 cashback categories per month.
  - PRO: unlimited cashback categories.
- Cashback screenshot import:
  - Free: locked.
  - PRO: available.
- Cashflow:
  - Free: chart is locked.
  - PRO: chart is available.

## Source of truth

- `EntitlementPolicy` in `Core/AppState/AppState.swift` is the only place for limits.
- UI/modules must use policy methods instead of hardcoded checks.

## Debug override and diagnostics

- Profile now has a dedicated debug toggle for `debug premium override`.
- Profile also has a dedicated debug toggle to disable trial (`trial disabled override`), so you can test Free mode even during an active trial.
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
- Cashback category limit:
  - `millio/UI/Services/Cashback/CashbackView.swift`
- Finance charts:
  - `millio/UI/Services/Finances/FinanceDynamicsView.swift`
  - `millio/UI/Services/Finances/Components/FinanceOverviewCardView.swift`
- Cashflow chart:
  - `millio/UI/Services/Cashflow/CashflowView.swift`
- Home Screen widget is not paywalled:
  - `millioCurrencyWidgetExtension/CurrencyConverterPremiumWidget.swift`
