# Spec: real-estate detail redesign

## Problem

The cover consumes the first viewport, core valuation figures are visually secondary, the generic account header duplicates monetary information, and photo mutations are mixed into the read-only detail experience.

## Goal

Make the property screen understandable at a glance: a restrained photographic cover flows into a legible valuation summary, while photo management is performed only in the existing edit flow.

## Acceptance criteria

- [x] The cover is visually limited to approximately 220–260 pt on a standard iPhone and does not grow with a portrait image.
- [x] The bottom of the cover fades smoothly into the screen background; the transition has no hard card gap.
- [x] Current property value and currency are the first and largest numeric content immediately following the cover.
- [x] Absolute change, percentage change, valuation date/age, and equity when available are grouped in one compact, readable summary.
- [x] Missing valuation values render an intentional empty state (`—`), not a misleading zero.
- [x] The generic account header is not rendered for real estate, so value/note content is not duplicated.
- [x] The detail gallery is browse-only: preview and count are allowed; add, cover, reorder, and delete controls are absent.
- [x] A clear edit/settings entry continues to open `RealEstateEditSheet`, where existing staged photo management remains available.
- [x] No-photo and corrupt-cover states keep the same layout and expose accessible labels.
- [x] Archived/deleted accounts remain viewable and cannot expose mutation controls.
- [x] Long values, Dynamic Type, VoiceOver, and narrow widths do not clip the primary summary or metric labels.
- [x] Existing valuation calculation and attachment persistence behavior are unchanged.

## Scope

- Real-estate detail composition and presentation.
- Extraction of deterministic presentation data if needed for unit testing.
- Relevant localization/accessibility text and tests.

## Non-goals

- Changing photo limits, compression, persistence, or CloudKit schema.
- Redesigning the generic account detail screen or the complete real-estate edit form.
- Adding carousel libraries, custom gestures, or a new design system.

## Constraints and risks

- Use existing colors, typography, spacing, services, and `RealEstateValuationCalculator`.
- Preserve unrelated local changes in `Localizable.xcstrings`.
- Prefer adaptive SwiftUI layout (`ViewThatFits`, wrapping, accessibility grouping) over fixed widths.
