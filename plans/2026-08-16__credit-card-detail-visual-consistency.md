# Plan: единый визуальный стиль кредитной карты

## Status

`PLANNED` — research/spec complete; no code started.

## Inputs

- Research: `../thoughts/research/2026-08-16-credit-card-detail-visual-consistency.md`
- Spec: `../specs/2026-08-16-credit-card-detail-visual-consistency.md`

## Phases

### [ ] Phase 1 — localization boundary

- Replace hard-coded credit-card labels with catalog keys in `CreditCardDetailSection` and `AccountDetailView` action/sheet override.
- Add complete RU/EN/zh-Hans entries and a focused localization-key test.

### [ ] Phase 2 — compact action layout

- Add a pure compact-tile layout policy and apply it only to `genericActions`.
- Use consistent width/height, two-line text limit, icon-first hierarchy and accessible minimum hit size.
- Add layout tests for English and Russian long action labels.

### [ ] Phase 3 — QA

- Run targeted tests and build.
- Verify 375/390 iPhone screen widths, English/Russian/Chinese, accessibility Dynamic Type, light/dark.
- Confirm actions retain their existing sheet routes and balance semantics.
