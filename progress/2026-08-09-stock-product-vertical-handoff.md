# Stock product vertical handoff — 2026-08-09

## Completed

- Captured baseline and financial contract in research/spec/plan.
- Added deterministic FIFO lot replay over AccountEvent.
- Buy fee is capitalized into lot cost; sell fee reduces net proceeds; standalone fees and dividends remain separate.
- AccountsCoreService validates positive quantity/unit price, non-negative fee and rejects backdated/current oversell before attaching or inserting an event.
- AccountDetailView quantity and unrealized P&L now consume the lot engine instead of aggregate UI formulas.
- No schema change.
- Verification: 29 focused tests passed on Millio-375-QA with parallel testing disabled.

## Next safe slice

1. Finish Phase 1 inventory for historical quote/FX/Cashflow/backup and add no-look-ahead characterization tests.
2. Design additive event payload for tax and split, including backup/import and frozen-schema proof.
3. Add one atomic StockTradeCommand that stages investment, cash and Cashflow projection before a single save boundary.
4. Only then build specialized stock create/detail/buy/sell/dividend UI and render matrix.

## Known blockers/risks

- `MarketMeta` cannot represent canonical exchange/instrument currency.
- AccountEvent cannot represent split ratio or distinguish tax from fee.
- Historical market fallback is untyped and can present a trade price as historical market evidence.
- Full AccountsCoreService parallel suite is not isolated reliably; use serial evidence until fixtures are hardened.
