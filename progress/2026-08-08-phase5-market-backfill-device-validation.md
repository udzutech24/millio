# Phase 5: historical evidence backfill — device validation handoff

## Completed locally

- Dynamics requests the exact chart date skeleton for FX and market prefetch.
- Historical market closes are loaded cache-first, fetched once per missing symbol, and saved append-only.
- RUB pairs use CBR first; Frankfurter fallback now actually accepts RUB.
- Incomplete valuation results are no longer published as closed cache entries.
- iOS Release build was signed, installed on the connected iPhone, and preserves existing app data.
- Focused historical valuation and market-price tests pass; the project builds for testing.
- The grouped legacy migration regression was repaired: group prerequisites are committed before
  invoking the converter's clean-context atomic boundary; the formerly failing focused cases pass.
- Physical-device logs no longer contain the former manifest semantic, revision-reason, or RUB
  historical-fetch failures, and the 1W chart renders.
- Screenshot arithmetic is consistent across historical consumers:
  `98,898,259 + 958,897 = 99,857,156` in both Dynamics and Cashflow.

## Remaining acceptance checks

1. Complete the policy-required 30 observations over 7 civil days.
2. Exercise the physical-device offline transition and repeat the rendered-range checks.
3. Execute and record the explicit rollback drill before deleting compatibility code.
4. Publish the backend `outputsize <= 5000` change. Production may retain the previous limit of 120 until that publication reaches the running environment.

## Accepted valuation-basis difference

The current Accounts/Dashboard total is `99,967,312 RUB`, while the historical endpoint is
`99,857,156 RUB`, a difference of `110,156 RUB`. The historical value is internally consistent and
uses eligible historical closes; the live total uses current valuation. Do not forward-fill or
rewrite evidence merely to force these two valuation bases to match.

## Verification evidence

Focused historical and migration XCTest suites pass. Backend validation is performed in the
backend repository before publication.
