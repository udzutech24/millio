# Quick Setup Flow

## Goal
`QuickSetup` replaces promo-only onboarding with an operational setup flow that configures language, currencies, expense categories, and initial finance products.

## Start Screen
- First launch now opens an onboarding start screen before quick setup.
- The screen explains the setup scope and offers two actions:
  - Start quick setup.
  - Skip and go straight to the workspace.

## Steps
1. `localeAndCurrencies`
- Select app language.
- Select primary currency.
- Select up to 4 favorite currencies.
- Quick setup filters language options by system locale:
  - Russian system locale: `System`, `English`, `Russian`.
  - Non-Russian system locale: `System`, `English`.
- Quick setup prioritizes currencies by system locale:
  - Russian system locale: `RUB`, `USD`, `CNY`, `EUR`, `TRY`.
  - Non-Russian system locale: system currency first, then `USD`, `EUR`, `CNY`, `GBP`, `JPY`, `CHF`, `CAD`, `AUD` (without `RUB` in recommendations).
- For non-Russian system locale, `RUB` is sanitized out from quick setup defaults even when old settings contain it.
- Default favorite currencies for non-Russian system locale are derived from `USD`, `EUR`, `CNY` and never include the selected primary currency.

2. `expenseCategories`
- Choose expense categories to keep visible in Cashflow.
- Non-selected system categories are hidden via `CashflowSystemCategoryOverride`.
- Category names in quick setup are localized based on the currently selected app language.

3. `products`
- Add one or many products in a row:
  - account (`Card`)
  - asset (`Investment.other`)
  - stock (`Investment.stocks`)
  - crypto (`Investment.crypto`)
- Every added product is attached to the ungrouped finance group.

4. `summary` (security slide)
- Explain data safety and storage model before completing setup.
- User selects backup preference:
  - `localOnly`: data stays local in SwiftData, backup remains disabled.
  - `cloudBackup`: snapshots are uploaded to user's Private CloudKit database.
- Security note on this slide clarifies backup encryption options:
  - AES-GCM with device key (Keychain-backed key).
  - AES-GCM with passphrase (portable mode, configured in Profile -> Backup).

## Entry Points
- First launch: `OnboardingView` opens `OnboardingStartView`, then `QuickSetupView` in onboarding mode.
- Main screen: a dismissible `Quick setup` banner is shown until setup is completed.
- Profile: dedicated row in `Settings` (under `App security`) to re-open `Quick setup` anytime.

## Persistence
`SettingsManager` keys:
- `quickSetupCompleted`
- `quickSetupBannerHidden`
- `quickSetupExpenseCategoryIDs`

## Notes
- Onboarding can be skipped; app still proceeds to `ready` state.
- Completing quick setup sets `quickSetupCompleted = true`.
