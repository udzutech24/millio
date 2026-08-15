# Phase 5 incomplete-series device diagnosis

## Evidence

The physical-device log reported `7/8` and `183/184` incomplete points. Root causes were
`marketPrice/evidence_unavailable`, `fxRate/previous_close_ineligible`, and the secondary
`cache/close_repository_failed` marker.

Code tracing proved three independent causes:

1. Dynamics warmed an independently sampled set of about 90 FX dates, while the structured
   producer requested the chart skeleton's exact dates.
2. `AccountMarketPriceService` persisted only today's live quote although the existing backend and
   iOS client already exposed daily chart candles.
3. `HistoricalValuationCloseStore` attempted to publish an incomplete closed result, obscuring its
   primary dependency failure with `close_repository_failed`.

## Decision

- Warm the exact producer dates.
- Reuse the existing authenticated market client; do not add another provider.
- Fetch one daily chart per missing symbol and append missing closes to `HistoricalAssetPrice`.
- Never overwrite a historical row and never perform network I/O during replay.
- Treat CBR/global fiat evidence as a versioned Monday–Friday calendar, allowing previous close only
  across explicit closed days. Stocks use the same conservative business-day policy; crypto stays
  exact 24/7.
- Do not send an incomplete result to the close repository.

## Operational constraint

The backend DTO previously capped `outputsize` at 120, which is insufficient for a one-year daily
backfill. The local contract is raised to 5,000. Production devices need the matching backend
version deployed before requesting more than 120 candles.
