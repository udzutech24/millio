# FX UI stress-test: Dashboard, Accounts, Dynamics

**Date:** 2026-08-09
**Mode:** read-only diagnosis; no product-code changes

## Verdict

The current system is not bulletproof. Pair direction, inversion and the CBR `Nominal` formula are
sound, but evidence semantics are not. A plausible number can be published with stronger quality
than its provenance proves.

## Failure matrix

| Priority | Scenario | Result | Evidence | Blast radius |
|---|---|---|---|---|
| Critical | An open-day live FX value is requested through the historical API | `getHistoricalRate(today)` returns `getRate`; the store persists it as `historical` + `.exact`; local evidence keeps it exact on an open day | `CurrencyRateService.swift:187-188`, `HistoricalRateStore.swift:61-70`, `HistoricalValuationLocalEvidenceSnapshot.swift:115-136`; the test `historicalFXRemainsExactOnOpenDay` explicitly locks this behavior | Dynamics today; after day rollover the same untyped row can remain historical evidence |
| High | CBR effective rate exists for Saturday | Prefetch rewrites every weekend date to Friday and the fiat policy declares Saturday closed | `HistoricalRateStore.swift:95-139`, `HistoricalValuationResolutionPolicy.swift:65-75`; CBR publishes dated Saturday rates | Dynamics weekend points |
| High | Audit needs to distinguish CBR exact, Frankfurter fallback, live cache and stale cache | All stored FX rows use `historical[ _prefetch ]|tz=...`; provider, payload date and fallback kind are lost | `HistoricalRateStore.swift:63-68,112-117`; `HistoricalValuationLocalEvidenceSnapshot.swift:116-129` | Incident diagnosis, close immutability, Dashboard/Accounts/Dynamics reconciliation |
| High | Production boundary provenance contract | Expanded gate fails: expected `local-fx-exact-only-v1`, actual `historical-fiat-business-days-v1` | `AccountsTotalsHistoricalValuationTests.swift:556`; xcresult from 2026-08-09 07:11 | Structured Accounts/Dynamics historical path; contract drift is currently unacknowledged |
| Medium | App is offline with an old current-rate snapshot | Dashboard and Accounts intentionally return a number, but UI does not expose source age/staleness | `CurrencyRatesWidget.swift:132-151`, current-rate offline tests | Dashboard and current Accounts total; user can mistake stale reference data for current rate |
| Medium | Historical provider miss with any older cached row | Compatibility `HistoricalRateStore.getRate` accepts the latest arbitrary prior row before live fallback, without applying the versioned calendar policy | `HistoricalRateStore.swift:75-83` | Compatibility consumers and any path still calling `totalAt`/store directly |
| Low | Direction, inverse and cross conversion | Correct: `1 FROM = rTo/rFrom TO`; inverse cache lookup is reciprocal | Current CBR and historical inversion tests pass | No defect proved |
| Low | CBR nominal greater than one | Parser correctly stores `Value / Nominal` | `HistoricalRateProviders.swift:323-339` | Formula correct, but there is no explicit nominal>1 regression fixture |

## Test gate

Command: selected currency and historical valuation suites on iPhone 17 Pro / iOS 26.5.

Result: **failed**. The only reported failure was
`AccountsTotalsHistoricalValuationTests.structuredBoundaryUsesProductionLocalEvidenceAdapterAndPreservesProvenance`:

```text
calendarPolicyID actual: historical-fiat-business-days-v1
calendarPolicyID expected: local-fx-exact-only-v1
```

All executed direction, inverse, CBR normalization, resolver fail-closed, timezone, stale-current,
weekend-policy and cache tests passed. Passing tests do not clear the Critical/High findings: two
of those tests encode the disputed semantics (open-day FX as exact; every Saturday as closed).

## Stress conclusion

The observed device delta `99,967,312 - 99,857,156 = 110,156 RUB` remains a legitimate
live-versus-close basis difference and must not be "fixed" by forcing equality. The unsafe part is
that current metadata cannot always prove which side of that distinction a stored value belongs to.

Release-quality exit requires, before implementation is accepted:

1. a typed FX evidence kind (`officialClose`, `providerClose`, `liveEstimate`, `staleEstimate`);
2. provider ID, requested day, provider effective day, fetched-at and inversion provenance;
3. a CBR-effective-date policy instead of a generic Monday-Friday fiat calendar;
4. open-day live FX classified as `currentEstimate`, never `exact`;
5. a green production-boundary provenance contract;
6. an explicit nominal>1 fixture and Saturday-effective CBR fixture.
