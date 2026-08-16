import Foundation
import Testing
@testable import millio

struct CashflowStatementImportContractTests {
    @Test("Schema v1 preserves signed decimal amount as text")
    func decodesDecimalWithoutDoubleBoundary() throws {
        let data = Data(#"{"schemaVersion":1,"status":"needs_review","statement":{"bankId":"fixture","templateVersion":"v1","format":"csv","accountScope":"opaque","period":{"from":"2026-07-01","to":"2026-07-31"}},"operations":[{"fingerprint":"sha256:v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","operationDate":"2026-07-31","postingDate":null,"description":"Store","amount":"-123.45","currency":"RUB","type":"card_purchase","categorySuggestion":null,"extractionConfidence":0.9,"reviewReasons":[],"sourceReference":{"row":2,"sequence":0}}],"reconciliation":{"balanced":false,"declaredIncome":null,"declaredExpense":null,"computedIncome":"0","computedExpense":"123.45","difference":"0","reasons":["missing_declared_totals"]},"warnings":[]}"#.utf8)
        let preview = try JSONDecoder().decode(CashflowStatementPreviewDTO.self, from: data)
        #expect(preview.schemaVersion == 1)
        #expect(preview.statement.format == "csv")
        #expect(preview.operations.first?.operationDate == "2026-07-31")
        #expect(preview.operations.first?.amount == "-123.45")
        #expect(preview.operations.first?.validatedAmount == Decimal(string: "-123.45"))
        #expect(preview.reconciliation.balanced == false)
        #expect(preview.balances == nil)
    }

    @Test("Schema v1 decodes additive bank-declared balance evidence exactly")
    func decodesOptionalBalanceEvidence() throws {
        let data = Data(#"{"schemaVersion":1,"status":"ready","statement":{"bankId":"fixture","templateVersion":"v1","format":"csv","accountScope":"opaque","period":{"from":"2026-07-01","to":"2026-07-31"}},"operations":[],"reconciliation":{"balanced":true,"declaredIncome":"0","declaredExpense":"0","computedIncome":"0","computedExpense":"0","difference":"0","reasons":[]},"balances":{"opening":{"amount":"999999999999999999.001","asOf":"2026-07-01"},"closing":{"amount":"999999999999999999.001","asOf":"2026-07-31"},"currency":"RUB","source":"bank_declared","confidence":1,"reasons":[]},"warnings":[]}"#.utf8)
        let preview = try JSONDecoder().decode(CashflowStatementPreviewDTO.self, from: data)

        #expect(preview.balances?.currency == "RUB")
        #expect(preview.balances?.source == "bank_declared")
        #expect(preview.balances?.closing?.asOf == "2026-07-31")
        #expect(preview.balances?.closing?.amount == "999999999999999999.001")
        #expect(preview.balances?.closing?.validatedAmount == Decimal(string: "999999999999999999.001"))
    }

    @Test("Unavailable client fails honestly")
    func unavailableClient() async {
        let client = UnavailableCashflowStatementImportClient()
        #expect(client.availability == .unavailable(reason: "statement_backend_unavailable"))
        await #expect(throws: CashflowStatementImportError.backendUnavailable) {
            try await client.preview(fileURL: URL(fileURLWithPath: "/tmp/not-read"))
        }
    }
}
