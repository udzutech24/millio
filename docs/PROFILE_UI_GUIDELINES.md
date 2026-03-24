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
- Keep the PRO upsell card as a distinct hero surface with layered highlights, not a flat banner.
- On narrow widths, preserve the row scan path: keep the status/value on one line with scaling before allowing awkward word breaks, and let the title wrap to at most two lines.

## Icon Styling
- Give each profile row a semantic icon tone instead of one neutral gray for all rows.
- Keep icon size unchanged; only adjust tint so the screen stays recognizable and easier to scan.
- Prefer Apple-like saturated accent colors with restraint: blue/cyan for system and sync actions, green for safe/account state, orange for reminders, purple/pink for experience features, red for destructive actions.

## Localization Safety
- Section IDs expose:
  - `localizationKey` for localized lookup.
  - `fallbackTitle` for guaranteed readable text.
- Resolve section headers via `AppLocalization.string(..., fallback: ...)`.

## Header Name Source
- Resolve profile header name with explicit priority:
  - user-edited profile name (if not guest default);
  - Apple account name (`fullName`, then `firstName + lastName`);
  - localized guest default (`profile.default_guest`).
