# Research: credit-card detail visual consistency

- Date: 2026-08-16
- Evidence: supplied iPhone 17 Pro Max screenshot and `AccountDetailView.swift`.

## Proven defects

1. `genericActions` supplies the credit-card action title as the literal Russian string `"Изменить сумму долга"`. It bypasses the app language and causes mixed RU/EN UI.
2. Generic action buttons use intrinsic width (`padding(.horizontal:)`) in a horizontal scroll view. The long debt label becomes materially wider than its peers and destroys the visual rhythm.
3. The payment card itself contains additional hard-coded Russian copy in `CreditCardDetailSection` while the app language is English. This is the same localization boundary failure, not a user setting problem.

## Recommended approach

- Add a localized `credit_card.action.adjust_debt` string and replace the literal at every credit-card adjust entry point, including the sheet title override.
- Introduce a narrow `AccountDetailActionLayoutPolicy` for generic actions: a fixed compact tile width, two-line title cap and Dynamic Type minimum-fit behavior. Do not globally alter market actions, which use a different layout.
- Localize all credit-card detail labels through the existing string catalog; retain financial calculations and action routing unchanged.

## Risks

- Fixed tiles can truncate long translations: test EN/RU/zh-Hans plus accessibility Dynamic Type; title may use two lines but never clip icons or reach an unsafe tap target.
- A broad action-button refactor risks other Account product types: scope to generic actions and snapshot/presentation tests first.
