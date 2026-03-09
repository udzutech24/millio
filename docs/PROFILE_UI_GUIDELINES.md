# Profile UI Guidelines

## Goals
- Keep profile sections visually consistent with iOS settings-style scan path.
- Avoid raw localization keys in UI when a translation is missing.
- Preserve readable spacing rhythm between headers, cards, and rows.

## Layout Rules
- Use shared layout tokens from `ProfileView.ProfileLayout`.
- Keep section spacing consistent (`sectionSpacing`).
- Keep card horizontal insets consistent (`contentHorizontalInset`).
- Build profile menu rows as a compact list with row dividers.

## Localization Safety
- Section IDs expose:
  - `localizationKey` for localized lookup.
  - `fallbackTitle` for guaranteed readable text.
- Resolve section headers via `AppLocalization.string(..., fallback: ...)`.
