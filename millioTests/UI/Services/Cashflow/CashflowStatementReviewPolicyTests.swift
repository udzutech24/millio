import Foundation
import Testing
@testable import millio

struct CashflowStatementReviewPolicyTests {
    private func operation(type: String, fingerprint: String = "row", amount: String = "-10") throws -> CashflowStatementPreviewDTO.Operation {
        let json = #"{"fingerprint":"\#(fingerprint)","operationDate":"2026-07-01","postingDate":null,"description":"Row","merchant":"Store","amount":"\#(amount)","currency":"RUB","type":"\#(type)","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":2,"sequence":0}}"#
        return try JSONDecoder().decode(CashflowStatementPreviewDTO.Operation.self, from: Data(json.utf8))
    }

    @Test("Internal transfers, duplicates and technical rows are locked; external transfer starts excluded")
    func safeDefaults() throws {
        #expect(CashflowStatementReviewDispositionPolicy.initial(for: try operation(type: "transfer_internal"), isLocalDuplicate: false) == .excludedInternalTransfer)
        #expect(CashflowStatementReviewDispositionPolicy.initial(for: try operation(type: "transfer_external"), isLocalDuplicate: false) == .excludedExternalTransfer)
        #expect(CashflowStatementReviewDispositionPolicy.initial(for: try operation(type: "technical"), isLocalDuplicate: false) == .excludedTechnical)
        #expect(CashflowStatementReviewDispositionPolicy.initial(for: try operation(type: "card_purchase"), isLocalDuplicate: true) == .excludedDuplicate)
    }

    @Test("Only external transfers can be explicitly converted")
    func reclassificationBoundary() throws {
        #expect(CashflowStatementReviewDispositionPolicy.canReclassify(try operation(type: "transfer_external")))
        #expect(!CashflowStatementReviewDispositionPolicy.canReclassify(try operation(type: "transfer_internal")))
        #expect(!CashflowStatementReviewDispositionPolicy.canReclassify(try operation(type: "card_purchase")))
    }

    @Test("Groups never combine kind or currency")
    func groupingBoundary() throws {
        let rows = [
            CashflowStatementReviewRow(operation: try operation(type: "card_purchase", fingerprint: "rub-expense"), disposition: .included(.expense), categoryRaw: "groceries", needsAttention: false),
            CashflowStatementReviewRow(operation: try operation(type: "card_purchase", fingerprint: "income", amount: "10"), disposition: .included(.income), categoryRaw: "salary", needsAttention: false),
            CashflowStatementReviewRow(operation: try operation(type: "card_purchase", fingerprint: "usd-expense"), disposition: .included(.expense), categoryRaw: "groceries", needsAttention: false, currencyOverride: "USD")
        ]
        let groups = CashflowStatementReviewPresentationBuilder.groups(rows: rows)
        #expect(groups.count == 3)
        #expect(Set(groups.map(\.key.currency)) == ["RUB", "USD"])
        #expect(Set(groups.map(\.key.kind)) == [.income, .expense])
    }

    @Test("Needs-attention filter is the safe default and supports large input")
    func filtersLargeInput() throws {
        let base = try operation(type: "card_purchase")
        let rows = (0..<200).map { index in
            CashflowStatementReviewRow(operation: base, fingerprintOverride: "row-\(index)", disposition: .included(.expense), categoryRaw: index < 52 ? "other" : "groceries", needsAttention: index < 52)
        }
        #expect(CashflowStatementReviewPresentationBuilder.rows(rows, filter: .needsAttention).count == 52)
        #expect(CashflowStatementReviewPresentationBuilder.rows(rows, filter: .all).count == 200)
    }

    @Test("Confirmation separates proposed totals by currency")
    func confirmationTotals() throws {
        let rows = [
            CashflowStatementReviewRow(operation: try operation(type: "card_purchase", fingerprint: "a", amount: "-10.25"), disposition: .included(.expense), categoryRaw: "groceries", needsAttention: false),
            CashflowStatementReviewRow(operation: try operation(type: "card_purchase", fingerprint: "b", amount: "20"), disposition: .included(.income), categoryRaw: "salary", needsAttention: false, currencyOverride: "USD")
        ]
        let summary = CashflowStatementConfirmationSummary(rows: rows)
        #expect(summary.includedCount == 2)
        #expect(summary.totalsByCurrency["RUB"] == Decimal(string: "-10.25"))
        #expect(summary.totalsByCurrency["USD"] == 20)
    }

    @Test("Statement account picker keeps current legacy and AccountsCore accounts")
    func statementAccountsUseCanonicalResolver() {
        let legacy = Card(name: "Legacy card", cardNumber: "1234", bank: .other, cardType: .debit, currency: "RUB", balance: 0)
        let core = Account(name: "Main account", kind: .bankAccount, currency: "RUB")
        let options = CashflowStatementAccountSelectionPolicy.options(
            cards: [legacy], newCoreAccounts: [core], statementCurrencies: ["RUB"]
        )
        #expect(options.map(\.title).contains("Legacy card"))
        #expect(options.map(\.title).contains("Main account"))
        #expect(CashflowStatementAccountSelectionPolicy.isValid(core.id.uuidString, in: options))
    }

    @Test("Account picker filters unrelated currencies and rejects stale selection")
    func statementAccountCurrencyAndRevalidation() {
        let rub = Account(name: "RUB", kind: .bankAccount, currency: "RUB")
        let usd = Account(name: "USD", kind: .bankAccount, currency: "USD")
        let options = CashflowStatementAccountSelectionPolicy.options(
            cards: [], newCoreAccounts: [rub, usd], statementCurrencies: ["RUB"]
        )
        #expect(options.map(\.title) == ["RUB"])
        #expect(!CashflowStatementAccountSelectionPolicy.isValid(usd.id.uuidString, in: options))
    }
}
