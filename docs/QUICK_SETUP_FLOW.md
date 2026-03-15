# Quick Setup Flow

## Goal
`QuickSetup` replaces promo-only onboarding with an operational setup flow that configures language, currencies, expense categories, and initial finance products.

## Start Flow
- First launch opens `QuickSetupView` immediately in onboarding mode.
- There is no separate intro/promo screen before the first setup step.
- If the user leaves onboarding, the app still proceeds to the workspace without marking quick setup as completed.

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
- The picker is backed by the shared `ExpenseCategoryCatalog` with canonical system categories and alias coverage for import.
- If a hidden system category is later used in manual entry or bulk screenshot import, it is automatically shown again instead of being downgraded to `Other`.
- Category names in quick setup are localized based on the currently selected app language.

3. `products`
- Build finance groups first, then add one or many products in a row:
  - one-tap group presets are based on the same finance group templates as the main finance editor;
  - the selected group becomes the target for the next product draft;
  - if no group is selected, the product falls back to the system `Ungrouped` group.
- Why this exists:
  - totals and dynamics are clearer from day one;
  - user does not need to re-sort accounts right after onboarding;
  - quick setup stays fast because groups can be picked from ready-made presets.
- Supported product types:
  - account (`Card`)
  - asset (`Investment.other`)
  - stock (`Investment.stocks`)
  - crypto (`Investment.crypto`)

4. `summary` (security slide)
- Explain data safety and storage model before completing setup.
- User selects backup preference:
  - `localOnly`: data stays local in SwiftData, backup remains disabled.
  - `cloudBackup`: snapshots are uploaded to user's Private CloudKit database.
- Default quick setup suggestion is `cloudBackup` (`Local + iCloud`) so backup is opt-out rather than easy to miss.
- Security note on this slide clarifies backup encryption options:
  - AES-GCM with device key (Keychain-backed key).
  - AES-GCM with passphrase (portable mode, configured in Profile -> Backup).

## Entry Points
- First launch: `OnboardingView` opens `QuickSetupView` directly in onboarding mode.
- Main screen: a dismissible `Quick setup` banner is shown until setup is completed.
- Existing users after update: banner is suppressed by default (no quick setup completion flag stored yet, but a prior app version was seen).
- Profile: dedicated row in `Settings` (under `App security`) to re-open `Quick setup` anytime.

## Persistence
`SettingsManager` keys:
- `quickSetupCompleted`
- `quickSetupBannerHidden`
- `quickSetupExpenseCategoryIDs`

## Notes
- Onboarding can be skipped; app still proceeds to `ready` state.
- Completing quick setup sets `quickSetupCompleted = true`.
