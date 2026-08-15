# Spec: stock product vertical

## Problem

The current market-investment flow tracks quantity but does not maintain lots, correct cost basis, realized P&L, fees, or an oversell invariant. UI owns financial formulas and historical fallback can masquerade as a quote.

## Goal

Make AccountsCore event replay the single source for a stock position and progressively build dedicated stock creation, trade, detail, history and corporate-action UX.

## Financial contract

- Policy: FIFO v1.
- Buy gross = quantity × unit price; acquisition cost = gross + buy fee.
- Sell gross = quantity × unit price; net proceeds = gross − sell fee − tax.
- Realized P&L = net proceeds − FIFO cost basis consumed.
- Unrealized P&L = market value − remaining open cost basis.
- Dividends are separate investment income; they never change position quantity/value.
- Total return amount = realized P&L + unrealized P&L + net dividends. Trade fees are already included once in lot cost/net proceeds.
- Short positions are out of scope; oversell is rejected at the writer boundary.
- Event order is date, createdAt, UUID.

## Acceptance criteria

- [ ] Characterize current creation, replay, quote fallback, totals, cashflow and backup paths.
- [x] Pure deterministic FIFO replay supports multiple/fractional lots, buy/sell fees, partial/full sales and dividends.
- [x] Writer rejects non-positive trade inputs and oversell.
- [ ] Dedicated creation/detail/buy/sell/dividend/edit flows use shared amount input and typed presentation.
- [ ] Atomic linked cash/investment/Cashflow commands save or roll back as one unit.
- [ ] Historical price/value/P&L series have typed freshness and no look-ahead.
- [ ] Split/reverse split, tax and symbol lifecycle have additive persisted contract and backup round-trip.
- [ ] RU/EN/zh-Hans, VoiceOver, Dynamic Type and render matrix pass.

## Scope

Nine phases from research through release audit, implemented incrementally because persistence, accounting and UI must remain reviewable and reversible.

## Non-goals

Short selling, options, merger/spin-off accounting, broker execution, and provider-specific DTOs in UI.

## Constraints and risks

No schema change without migration and backup proof. Existing user changes in overlapping files must be preserved. Missing historical quote or FX must yield incomplete state, never fabricated value.
