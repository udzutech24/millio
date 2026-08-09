# Research: stock product vertical

- Date: 2026-08-09
- Scope: AccountsCore market-stock creation, event replay, valuation, cashflow, persistence and product UI.
- Reproduction/evidence:
  - `AccountsCoreService.sell` accepts any positive or negative quantity and never checks available quantity.
  - `AccountBuySellSheet` explicitly leaves Save enabled when quantity exceeds the position.
  - `AccountDetailView.unrealizedPL` is `market value - all buys + all sells`; it mixes realized and unrealized P&L and ignores fees.
  - Buy/sell events persist quantity and unit price; `amount` is unused, so the existing schema can carry per-trade fees without a migration.
  - `AccountBalanceEngine.marketBalance` falls back to the last trade price for every requested date. That fallback is not a historical market quote and has no freshness status.
  - Market `openingBalance` is only a zero-valued existence anchor. The initial position is a separate `.buy` event created by the product factory.
- Current architecture and constraints:
  - `AccountEvent` is the financial source of truth; Account contains no balance field.
  - Current event types have buy, sell, dividend and fee, but no split, tax, reversal or symbol-change event.
  - `MarketMeta` stores only symbol and asset class; exchange, canonical instrument identity and instrument currency are not persisted separately.
  - Existing dirty changes overlap AccountsCore and finance UI and must not be overwritten.
- Options considered:
  1. Keep aggregate average-cost UI math: rejected because partial sales cannot produce correct realized/open cost basis.
  2. Add a deterministic FIFO engine over existing events and store trade fees in `amount`: chosen for the safe first slice; no schema migration.
  3. Add all corporate-action and tax fields immediately: rejected until a persisted contract and migration/backup proof exist.
- Recommended option and why: FIFO is explicit, deterministic, tax-auditable, handles partial lots, and can be introduced as a pure adapter over existing events. Hard-reject oversells in the writer boundary.
- Risks and unknowns: historical quote availability/freshness lacks a typed result; atomic investment+cash+Cashflow needs a dedicated transaction command; split/tax/exchange require an additive persisted contract.
- Relevant files/tests: `AccountEvent.swift`, `AccountsCoreService.swift`, `AccountBalanceEngine.swift`, `AccountDetailView.swift`, `AccountMarketPriceService.swift`, AccountsCore market and historical valuation tests.
