# Dynamics visible endpoint projection

## Acceptance criteria

- A requested boundary with `valuation.total == nil` is not treated as a displayed chart endpoint.
- The hero current balance equals the last renderable structured point.
- Absolute and percentage deltas use the first and last renderable structured points.
- Group/account rows use contributions from those same two points.
- Scrubbing resolves to the nearest renderable point.
- If no renderable points exist, the existing incomplete-history warning remains and no fabricated total is shown.
