# Localization Production Plan

## Current reality

- `Localizable.xcstrings` contains `1548` keys.
- Coverage snapshot on `2026-03-30`:
- `ru`: `1476` translated, `72` missing.
- `en`: `1471` translated, `77` missing.
- `zh-Hans`: `8` translated, `1540` missing.

## Hard findings

- Shipping all desired languages right now is a bad idea.
- `zh-Hans` is not production-ready; exposing it as a normal language creates silent fallback bugs, mixed-language screens, and broken trust.
- Even `ru` and `en` need audit closure before the localization layer can be called fully hardened.
- There is still manual locale branching in code (`hasPrefix("ru")`, RU/EN inline strings, language-specific logic outside `.xcstrings`).

## Production strategy

- Wave 1: ship only release-ready languages in product UX.
- Wave 1 languages: `system`, `en`, `ru`.
- Wave 2: promote `zh-Hans` only after key coverage, legal copy, onboarding, settings, notifications, widget copy, and regression tests are complete.
- Never add a new language directly to user-facing selectors before it passes the release checklist.

## Release checklist for a new language

- `Localizable.xcstrings` coverage is complete for app-critical flows.
- Widget resources and widget copy are localized.
- Legal and subscription copy are reviewed separately.
- Dates, numbers, and currency formatting are verified with locale-specific tests.
- Plurals and interpolation placeholders are validated.
- Hardcoded-string audit passes for onboarding, profile, settings, legal, widget, and notification flows.

## Immediate next engineering steps

- Close missing `ru` and `en` keys and remove format-only noise from coverage reporting.
- Replace remaining manual RU/EN branching with centralized localization helpers or `.xcstrings` keys.
- Add automated xcstrings coverage tests for release-ready locales.
- Audit widget/local notification strings separately from app strings.
- Define naming and sharding rules for `.xcstrings` before the catalog grows further.

## Implemented in this pass

- Centralized locale matching in `LocalizationSupport` so shared code no longer needs ad-hoc `hasPrefix("ru")` checks for the touched flows.
- Moved calendar-range copy, primary currency confirmation copy, legal titles, notification bodies, daily reminder screen copy, and premium diagnostics copy into `Localizable.xcstrings`.
- Added `zh-Hans` strings for the critical flows above and for widget configuration title/description.
- Kept `zh-Hans` behind rollout gating for `.system` and language pickers, because enabling it globally with the current catalog would still ship mixed-language UI.
- Added regression tests for calendar copy, primary currency confirmation copy, legal titles, diagnostics copy, and explicit Simplified Chinese notification copy.

## Remaining blockers

- The app catalog is still nowhere near complete for `zh-Hans`; this pass hardens critical shared surfaces, not the full product.
- There are still manual RU/EN branches outside the areas fixed here, notably in parts of Profile, bulk import flows, and Cashflow history/editor screens.
- `Localizable.xcstrings` still mixes real keys with stale literal-source entries; until that is cleaned up, long-term maintenance will remain fragile.
