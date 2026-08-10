# Plan: real-estate detail redesign

**Status:** IMPLEMENTED

## Inputs

- Research: [`thoughts/research/2026-08-10-real-estate-detail-redesign.md`](../thoughts/research/2026-08-10-real-estate-detail-redesign.md)
- Spec: [`specs/2026-08-10-real-estate-detail-redesign.md`](../specs/2026-08-10-real-estate-detail-redesign.md)

## Decision

- Chosen approach: compact cover with bottom fade, followed by a single real-estate summary; suppress the generic header; keep the detail gallery browse-only and use `RealEstateEditSheet` as the sole photo-management UI.
- Rejected alternatives: numeric overlay on arbitrary photos (unreliable contrast); cosmetic hero resize only (leaves duplication and mixed responsibilities); new carousel/dependency (unnecessary complexity).
- Rollback strategy: presentation-only commits can be reverted without data migration; persistence contracts remain unchanged.

## Phases

- [x] Phase 1 — Presentation contract and regression tests
  - Introduce the smallest deterministic presentation model/helper only if the view cannot be tested directly.
  - Cover current value, missing valuation, signed delta/percent, age/date, equity, and long-value formatting.
  - Add a regression assertion that real estate selects the product-specific header path rather than the generic header.
  - Evidence: focused `RealEstateProductTests` pass.
- [x] Phase 2 — SwiftUI composition and photo-management boundary
  - Recompose `RealEstateDetailSection`: compact cover, background fade, summary immediately below, optional chart, browse-only gallery, about card.
  - Remove direct attachment mutations and `PhotosPicker` state from the detail view; retain photo preview.
  - Prevent `AccountDetailView` from appending `standardHeader` for real estate.
  - Confirm the existing edit/settings action opens `RealEstateEditSheet`; add a localized entry only if the current one is not discoverable.
  - Preserve no-photo, corrupt-photo, archived, excluded-from-total, Dynamic Type, and accessibility states.
  - Evidence: focused tests, iOS build, and visual QA on at least one narrow and one standard iPhone simulator.
- [x] Phase 3 — Self-audit and documentation
  - Audit every acceptance criterion and check for duplicate value/note rendering.
  - Verify there are no new direct photo writes on the detail screen and no persistence/schema changes.
  - Update plan status/journal and session history with actual command evidence.

## Verification

- Unit tests: `RealEstateProductTests` plus any new presentation tests.
- Integration/build checks: build the iOS target with the repository's documented simulator command; run the focused suite before the broader gate.
- Visual checks: standard iPhone and narrow-width simulator, with photo/no photo, one/multiple valuations, large Dynamic Type, and archived account.
- Acceptance criteria audit: record pass/fail beside every criterion after Phase 2; do not mark complete from screenshots alone.

## Journal

- 2026-08-10: research/spec/plan created. Implementation not started because the required guard phrase has not been issued.
- 2026-08-10: Phase 1 implemented. Added locale-aware `RealEstateDetailPresentation` and explicit `AccountDetailDescriptor.showsGenericHeader` contract. The three affected tests pass. Full `RealEstateProductTests` result is 16/17: the pre-existing `atomicEditRollback()` fails because the account name remains mutated after an injected save failure; no transaction/edit-service code was changed in this phase.
- 2026-08-10: Phase 2 implemented. The detail cover is fixed at 240 pt with a bottom fade; the primary valuation summary follows immediately; the generic header is suppressed; the gallery is browse-only; a read-only-aware gear opens the existing staged editor. Targeted presentation/render tests and Debug/Release simulator builds succeeded. Visual QA passed on 375 pt and 390 pt simulators; screenshots are in `/tmp/millio-real-estate-detail-screenshots/`.
- 2026-08-10: Phase 3 complete. All 12 acceptance criteria audited and marked complete. Added corrupt-cover/archived render coverage at 375/390 pt with accessibility Dynamic Type and reused `RealEstateEditPolicy` as the read-only source. Five affected tests and the Debug simulator build passed. Full `RealEstateProductTests`: 17 passed, 1 pre-existing failure (`atomicEditRollback()` leaves `account.name == "After"` after injected save failure). Static audit found no `PhotosPicker`/`AccountAttachmentService` write path in the detail view and no schema/migration changes.

## Acceptance audit

- Layout: fixed 240 pt cover, 112 pt bottom fade, summary directly below; visually verified at 375/390 pt.
- Information hierarchy: current value/currency precede delta, percent, date/age and optional equity; missing values are unit-tested as `—`.
- Duplication: `showsGenericHeader == false` for real estate is unit-tested and used by `AccountDetailView`; note remains only in `aboutCard`.
- Photo boundary: detail supports preview/count only; all mutations remain staged in `RealEstateEditSheet`.
- Edge states: no photo, corrupt cover, archived state, long values and accessibility Dynamic Type have render/presentation coverage.
- Data safety: valuation calculator, attachment service, schema and migrations were not changed; rollback is a presentation-code revert.
