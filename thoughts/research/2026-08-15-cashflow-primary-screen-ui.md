# Research: Cashflow primary screen UI

## Evidence

- Screenshot supplied by the user shows the compact chart occupying roughly a third of the first viewport while the selected period's result is only inferred from small labels.
- `CashflowView.cashflowChartContent` reserves `CashflowInsightsControlsStyle.compactBarsHeight` (200 pt), has a separate 44 pt text action for expansion, and adds 18 pt internal stack spacing.
- The selected bar currently presents income/expense labels at opposite chart edges. The period total is repeated only later in `assetBreakdownSection` as “Result”.
- `monthContextActions` renders two equal large buttons even though adding a transaction is the primary action and opening a month workspace is contextual navigation.
- The existing chart geometry is intentionally tested (`CashflowChartVariantALayoutTests`) and should be preserved; this task is not a chart-math rewrite.

## Alternatives

1. Cosmetic-only: adjust colors/spacing. Rejected: it does not make the period result legible or reduce the wasted primary viewport.
2. Replace the chart with a different visualization. Rejected: destroys tested comparison semantics and expands scope without evidence.
3. Preserve chart geometry, introduce a compact selected-period summary and hierarchy-led chrome. Chosen: fixes the visible problem while preserving data semantics and routes.

## Risks

| Failure mode | Mitigation |
|---|---|
| A shorter chart hides small non-zero bars | retain `CashflowChartVariantALayout.minimumVisibleHeight` and existing common-scale calculation |
| Large Dynamic Type clips date/result controls | use wrapping or `ViewThatFits`; preserve 44 pt targets |
| Selected-period and full-screen state drift | use the existing `CashflowInsightsPresentation` as the only source for labels and selection |
| Month navigation becomes undiscoverable | retain a labelled secondary control and accessibility identifier `cashflow.action.month` |
