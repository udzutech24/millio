# Cashflow hero: semantic and visual proof before implementation

## Failure

The agent inferred that the top Cashflow hero should show `periodTotalChange` and accepted a responsive vertical fallback without validating the result on the target phone width. This produced both a semantic mismatch and a visibly different layout.

## Rule

For financial hero blocks, name the business equation in the spec before coding and map every displayed value to its source. For an approved fixed composition, run the real screenshot test at the narrowest supported width before marking the phase complete; a compile or pure layout test is insufficient proof.

## Expected effect

Prevents visually correct-looking mockups from drifting in production and prevents similarly named financial totals from being substituted for one another.
