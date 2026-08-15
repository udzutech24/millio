# Research: redesign of the real-estate detail screen

- Date: 2026-08-10
- Scope: `AccountDetailView` and `RealEstateDetailSection`; the existing staged-photo editor remains the write boundary.
- Reproduction/evidence:
  - The supplied iPhone screenshot shows a portrait cover occupying most of the first viewport, while the important valuation data starts below the fold.
  - `RealEstateDetailSection.body` renders `hero`, `valuationCard`, `valuationChart`, `gallery`, and `aboutCard` in sequence.
  - `hero` uses a fixed 16:9 container with `scaledToFill`; a portrait photo is therefore heavily cropped and visually dominates the screen.
  - `AccountDetailView` then renders the generic `header` after the entire real-estate section, duplicating the primary monetary context far below the product-specific summary.
  - The read screen contains write controls for add, cover selection, reorder, and deletion even though `RealEstateEditSheet` already implements staged photo management with an atomic save.
- Current architecture and constraints:
  - SwiftUI + SwiftData; `RealEstateValuationCalculator` is the existing source for current value, delta, percent, date, and age.
  - Photo mutations on the read screen currently bypass the staged editor and write through `AccountAttachmentService` immediately.
  - Archived/deleted accounts are read-only.
  - Existing user changes in `millio/Localizable.xcstrings` must not be overwritten.
- Options considered:
  1. Put all numbers over the image. Rejected: contrast depends on arbitrary user photos and Dynamic Type makes the overlay unstable.
  2. Keep the current 16:9 hero and only reduce its height. Rejected: it does not remove duplicated headers or mixed read/edit responsibilities.
  3. Recommended: a compact edge-to-edge cover with a bottom fade, followed immediately by one product summary; make the gallery read-only and route all photo management through the existing editor.
- Recommended option and why:
  - Option 3 keeps visual continuity without sacrificing legibility, removes duplicate information, and restores a clear separation between viewing and editing.
  - No new storage model, dependency, or service is needed.
- Risks and unknowns:
  - Moving real estate away from the generic header must preserve balance/current-value semantics and the excluded-from-total badge.
  - No-photo, corrupt-photo, one-valuation, long currency value, Dynamic Type, VoiceOver, and archived states need explicit coverage.
  - The navigation-level edit entry point must remain discoverable; photo actions must not disappear without a replacement path.
- Relevant files/tests:
  - `millio/UI/Services/Finances/AccountsCore/AccountDetailView.swift`
  - `millio/UI/Services/Finances/AccountsCore/RealEstateDetailSection.swift`
  - `millio/UI/Services/Finances/AccountsCore/RealEstateEditSheet.swift`
  - `millioTests/Core/AccountsCore/RealEstateProductTests.swift`
