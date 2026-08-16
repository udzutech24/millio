# Bank statement test fixtures

## T-Bank export procedure

Use this procedure when collecting a real statement for local parser development:

1. Open `Банк → Операции`.
2. Select exactly one account or card, not the combined `Счета и карты` scope.
3. Select one complete calendar month. Statement onboarding v1 intentionally rejects multi-month input.
4. Include transfers. Do not use the `Без переводов` filter: removing rows prevents balance reconciliation and transfer classification tests.
5. Prefer OFX as the long-term canonical machine-readable fixture when available. Also retain Excel for investigating bank-specific columns and CSV as a simple fallback.
6. Separately obtain a formal account statement/reference that explicitly shows opening or closing balance and its date. An operations export may contain only rows and turnover totals.

## Format priority

1. **OFX** — preferred canonical import format: structured fields, stable transaction identity and potential ledger balance/date fields.
2. **Excel** — preferred diagnostic companion: preserves bank-specific headers, categories and summary cells.
3. **CSV** — useful fallback, but locale separators, encoding and unstable column names make it weaker as the primary contract.

Current implementation note: Millio already has a proven T-Bank PDF `Справка о движении средств` adapter and an Alfa XLSX adapter. OFX support is the recommended next bank-export adapter, not an already supported production format.

## Real T-Bank operations XLSX characterization (2026-08-16)

A user-supplied local operations export was inspected structurally without copying or persisting its values:

- one worksheet and 67 operation rows;
- transaction/payment dates, descriptions, categories, card attribution, operation/payment amounts and currencies;
- transfer rows are present;
- no formulas;
- no exact opening-balance or closing-balance field.

Conclusion: this XLSX is suitable as evidence for a T-Bank operations adapter and Cashflow import, but it cannot establish the account balance. Account onboarding must request a manual balance or a separate formal statement with a declared balance.

The original real file remains outside the repository. Any checked-in fixture derived from it must be synthetic and preserve only structural/header behavior.

## iOS file ingress decision

- Register supported statement UTTypes as document types for `Open in Millio`. This is the direct-launch path: the host app receives the external file URL and opens statement review.
- Add a Share Extension only as a secondary `Save to Millio` path. It copies the file into an App Group inbox and finishes; the host app imports it on next activation.
- Do not use private responder-chain or URL-scheme hacks to force-launch the host app from a Share Extension. iOS does not guarantee that behavior.
- Both paths converge on one `IncomingStatementCoordinator`; parsing and financial writes never live in the extension.

## Privacy

- Real files stay local and must not be committed.
- Fixtures checked into the repository must be synthetic or fully sanitized.
- Remove account/card identifiers, names, phone/email/address data and unique merchant references.
- Do not store real amounts or raw descriptions in logs, analytics, memory or history notes.
