# Statement-first account onboarding

- Date: 2026-08-16
- Fact: Millio already has bank-statement extraction/review, while account creation still requires a separately entered balance and a later import route.
- Hypothesis: optional `statement -> reviewed account` onboarding reduces first-value time and data-entry errors without turning Millio into a mandatory bank aggregator.
- Test: measure create completion, statement CTA adoption, successful reviewed imports, manual-balance fallback and abandonment by safe event codes only; never collect account names, amounts, statement text or bank identifiers.
- Guardrail: copy must say `snapshot as of date`, not imply live bank synchronization.
