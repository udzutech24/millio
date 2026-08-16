import Foundation
import Testing
@testable import millio

@Suite("Account statement create-flow policy")
@MainActor
struct AccountStatementOnboardingFlowTests {
    @Test("Statement CTA is limited to debit cards and bank accounts")
    func eligibility() {
        #expect(AccountStatementOnboardingPresentationPolicy.isEligible(option: .card, cardType: .debit))
        #expect(AccountStatementOnboardingPresentationPolicy.isEligible(option: .account, cardType: nil))
        #expect(!AccountStatementOnboardingPresentationPolicy.isEligible(option: .card, cardType: .credit))
        #expect(!AccountStatementOnboardingPresentationPolicy.isEligible(option: .deposit, cardType: nil))
        #expect(!AccountStatementOnboardingPresentationPolicy.isEligible(option: .investment, cardType: nil))
    }

    @Test("Bank-declared closing balance wins with explicit provenance and date")
    func bankBalance() throws {
        let preview = try makePreview(balanceJSON: #", "balances":{"opening":null,"closing":{"amount":"1250.40","asOf":"2026-07-31"},"currency":"RUB","source":"statement_header","confidence":1,"reasons":[]}"#)

        let confirmation = try AccountStatementBalanceResolver.resolve(
            preview: preview,
            accountCurrency: "rub",
            manualAmount: 999,
            manualDate: Date(timeIntervalSince1970: 0),
            isManualConfirmed: true
        )

        guard case .bankDeclared(let amount, let currency, let date, let source) = confirmation else {
            Issue.record("Expected bank-declared confirmation")
            return
        }
        #expect(amount == Decimal(string: "1250.40"))
        #expect(currency == "RUB")
        #expect(source == "statement_header")
        #expect(Calendar(identifier: .gregorian).dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date).day == 31)
    }

    @Test("Missing bank balance requires an explicit manual amount and as-of date")
    func manualBalance() throws {
        let preview = try makePreview(balanceJSON: "")
        let date = Date(timeIntervalSince1970: 1_786_032_000)

        #expect(throws: AccountStatementBalanceResolverError.manualConfirmationRequired) {
            try AccountStatementBalanceResolver.resolve(
                preview: preview,
                accountCurrency: "RUB",
                manualAmount: 500,
                manualDate: date,
                isManualConfirmed: false
            )
        }
        let confirmation = try AccountStatementBalanceResolver.resolve(
            preview: preview,
            accountCurrency: "RUB",
            manualAmount: 500,
            manualDate: date,
            isManualConfirmed: true
        )
        #expect(confirmation == .manual(amount: 500, currency: "RUB", asOf: date))
    }

    @Test("Bank balance in another currency fails closed")
    func bankCurrencyMismatch() throws {
        let preview = try makePreview(balanceJSON: #", "balances":{"opening":null,"closing":{"amount":"10","asOf":"2026-07-31"},"currency":"USD","source":"statement_header","confidence":1,"reasons":[]}"#)
        #expect(throws: AccountStatementBalanceResolverError.currencyMismatch) {
            try AccountStatementBalanceResolver.resolve(
                preview: preview,
                accountCurrency: "RUB",
                manualAmount: nil,
                manualDate: .now,
                isManualConfirmed: false
            )
        }
    }

    @Test("Balance confirmation replaces only opening balance and anchor date")
    func commandConstruction() {
        let id = UUID()
        let groupID = UUID()
        let original = CreateProductCommand(
            accountID: id,
            productType: .debitCard,
            name: "Daily",
            currency: "RUB",
            openingBalance: 0,
            includeInTotal: false,
            order: 7,
            groupID: groupID,
            metadata: .init(card: .init(bank: "tbank", last4: "1234")),
            note: "note"
        )
        let asOf = Date(timeIntervalSince1970: 1_785_427_200)

        let result = AccountStatementCreateDraft(createTemplate: original)
            .command(openingBalance: 321, asOf: asOf)

        #expect(result.accountID == id)
        #expect(result.productType == .debitCard)
        #expect(result.openingBalance == 321)
        #expect(result.date == asOf)
        #expect(result.groupID == groupID)
        #expect(result.order == 7)
        #expect(result.includeInTotal == false)
        #expect(result.metadata.card?.last4 == "1234")
    }

    @Test("Reviewed rows are assigned to the pending account without an account picker")
    func reviewedRowsUsePendingAccount() async throws {
        let data = Data(#"{"schemaVersion":1,"status":"ready","statement":{"bankId":"fixture","templateVersion":"v1","format":"xlsx","accountScope":"opaque","period":{"from":"2026-07-01","to":"2026-07-31"}},"operations":[{"fingerprint":"expense","operationDate":"2026-07-02","postingDate":null,"description":"Store","amount":"-10","currency":"RUB","type":"card_purchase","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":2,"sequence":0}}],"reconciliation":{"balanced":true,"declaredIncome":"0","declaredExpense":"10","computedIncome":"0","computedExpense":"10","difference":"0","reasons":[]},"warnings":[]}"#.utf8)
        let preview = try JSONDecoder().decode(CashflowStatementPreviewDTO.self, from: data)
        let month = try #require(StatementISODateParser.date("2026-07-01"))
        let controller = CashflowStatementImportController(
            client: AccountStatementPreviewClient(preview: preview),
            selectedMonth: month
        )
        await controller.preview(fileURL: URL(fileURLWithPath: "/tmp/fixture.xlsx"))

        let rows = try CashflowApprovedStatementOperationBuilder.build(
            preview: preview,
            controller: controller,
            accountID: "pending-account"
        )

        #expect(rows.count == 1)
        #expect(rows.first?.accountID == "pending-account")
        #expect(rows.first?.type == .expense)
        #expect(rows.first?.amount == -10)
    }

    private func makePreview(balanceJSON: String) throws -> CashflowStatementPreviewDTO {
        let json = #"{"schemaVersion":1,"status":"ready","statement":{"bankId":"fixture","templateVersion":"v1","format":"xlsx","accountScope":"opaque","period":{"from":"2026-07-01","to":"2026-07-31"}},"operations":[],"reconciliation":{"balanced":true,"declaredIncome":"0","declaredExpense":"0","computedIncome":"0","computedExpense":"0","difference":"0","reasons":[]},"warnings":[]"# + balanceJSON + "}"
        return try JSONDecoder().decode(CashflowStatementPreviewDTO.self, from: Data(json.utf8))
    }
}

private struct AccountStatementPreviewClient: CashflowStatementImportClient {
    let availability: CashflowStatementImportAvailability = .available
    let preview: CashflowStatementPreviewDTO

    func preview(fileURL: URL) async throws -> CashflowStatementPreviewDTO { preview }
}
