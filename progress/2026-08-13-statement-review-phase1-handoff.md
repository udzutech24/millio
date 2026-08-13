# Handoff: statement review plan Phase 1

- Phase 1 complete: canonical system taxonomy v1 and deterministic backend category rules.
- Backend fixture: `millio-back/src/bank-statement-import/fixtures/v1/system-category-taxonomy.json`.
- Mirrored iOS fixture: `millio/UI/Services/Cashflow/StatementImport/Fixtures/system-category-taxonomy.json`; byte-for-byte parity verified and Swift test proves equality with current `IncomeCategory`/`ExpenseCategory` raw values.
- `statement-category-rule-matcher.ts` normalizes NFKC/case/punctuation/`ё`, matches conservative rules and always validates the result against the taxonomy kind.
- Covered: groceries, dining, taxi, public transport, subscriptions, fees, cash withdrawal/movement, salary, bonus, interest and refunds. Unknown/ambiguous strings remain `other` at confidence `0.35`.
- Cash withdrawal maps to expense-system `transfers`; there is no shared cash category, and a backend-only category was rejected as an architectural violation.
- `validateBankStatementPreview` rejects custom, unknown and wrong-kind category IDs. Backend cannot emit a local custom ID through the validated API contract.
- Alfa adapter calls the matcher only after sensitive-text redaction. Adapter golden proves non-`other` groceries and transfer suggestions.
- Evidence: backend bank-statement suite 50/50 passed; Nest/SWC build passed; iOS parity test passed. Existing compiler warnings are outside phase scope.
- New matcher/taxonomy files pass ESLint and both taxonomy fixtures are byte-identical. Whole touched-folder lint is not green because the pre-existing untracked Alfa adapter/spec already contains formatting, irregular-whitespace and unused-parameter violations; bulk-reformatting that user-owned baseline was intentionally refused.
- Initial implementation made no remote changes. On 2026-08-13 the user separately authorized production deployment.
- Production now runs an isolated Phase 1 overlay image containing only the matcher, taxonomy, contract and Alfa-adapter runtime artifacts. The server's dirty checkout was not changed or rebuilt.
- Deployment evidence: focused backend tests 29/29, Nest build green, candidate and active matcher smoke tests green, protected preview endpoint returned expected unauthenticated `401`, zero recent runtime errors.
- Rollback is preserved as `millio-back:rollback-pre-statement-phase1-20260813`.
- Phone acceptance still needs one fresh statement selection: the automated relaunch was rejected because the physical iPhone was locked, and an already-open preview cannot be recalculated client-side.
- Next phase requires: `Реализуй фазу 2 по плану plans/2026-08-13__statement-review-ux-and-categorization.md`.
