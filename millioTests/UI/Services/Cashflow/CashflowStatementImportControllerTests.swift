import Foundation
import Testing
@testable import millio

private struct StatementClientStub: CashflowStatementImportClient {
    let availability: CashflowStatementImportAvailability = .available
    let result: Result<CashflowStatementPreviewDTO, Error>
    func preview(fileURL: URL) async throws -> CashflowStatementPreviewDTO { try result.get() }
}

@Suite(.serialized)
@MainActor
struct CashflowStatementImportControllerTests {
    private var august2026: Date {
        Calendar(identifier: .gregorian).date(from: .init(year: 2026, month: 8, day: 1))!
    }

    @Test("Technical, transfer and duplicate rows start excluded")
    func reviewDefaultsAreSafe() async throws {
        let data = Data(#"{"schemaVersion":1,"status":"ready","statement":{"bankId":"fixture","templateVersion":"v1","format":"csv","accountScope":"opaque","period":{"from":"2026-07-01","to":"2026-07-31"}},"operations":[{"fingerprint":"purchase","operationDate":"2026-07-31","postingDate":null,"description":"Store","amount":"-10","currency":"RUB","type":"card_purchase","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":2,"sequence":0}},{"fingerprint":"transfer","operationDate":"2026-07-31","postingDate":null,"description":"Transfer","amount":"-20","currency":"RUB","type":"transfer_internal","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":3,"sequence":1}},{"fingerprint":"duplicate","operationDate":"2026-07-31","postingDate":null,"description":"Copy","amount":"-10","currency":"RUB","type":"card_purchase","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":["duplicate"],"sourceReference":{"row":4,"sequence":2}}],"reconciliation":{"balanced":true,"declaredIncome":"0","declaredExpense":"40","computedIncome":"0","computedExpense":"40","difference":"0","reasons":[]},"warnings":[]}"#.utf8)
        let preview = try JSONDecoder().decode(CashflowStatementPreviewDTO.self, from: data)
        let july2026 = Calendar(identifier: .gregorian).date(from: .init(year: 2026, month: 7, day: 1))!
        let controller = CashflowStatementImportController(
            client: StatementClientStub(result: .success(preview)),
            selectedMonth: july2026
        )

        await controller.preview(fileURL: URL(fileURLWithPath: "/tmp/fixture.csv"))

        #expect(controller.state == .needsReview(operationCount: 3))
        #expect(controller.includedFingerprints == ["purchase"])
    }

    @Test("Backend failure has an explicit state")
    func backendUnavailableIsExplicit() async {
        let controller = CashflowStatementImportController(client: UnavailableCashflowStatementImportClient())
        await controller.preview(fileURL: URL(fileURLWithPath: "/tmp/fixture.csv"))
        #expect(controller.state == .backendUnavailable)
    }

    @Test("Statement period must fit the selected calendar month")
    func statementPeriodCannotLeakAcrossMonths() {
        #expect(CashflowStatementMonthPolicy.validate(
            periodFrom: "2026-08-01", periodTo: "2026-08-31", selectedMonth: august2026
        ) == .matches)
        #expect(CashflowStatementMonthPolicy.validate(
            periodFrom: "2026-07-31", periodTo: "2026-08-31", selectedMonth: august2026
        ) == .mismatch)
        #expect(CashflowStatementMonthPolicy.validate(
            periodFrom: "bad", periodTo: "2026-08-31", selectedMonth: august2026
        ) == .invalidPeriod)
        #expect(CashflowStatementMonthPolicy.resolve(
            periodFrom: "2026-07-01", periodTo: "2026-07-31"
        ) == .singleMonth(year: 2026, month: 7))
        #expect(CashflowStatementMonthPolicy.resolve(
            periodFrom: "2026-07-31", periodTo: "2026-08-01"
        ) == .multipleMonths)
    }

    @Test("Month mismatch can recover locally without a second preview request")
    func monthMismatchRecoveryReusesPreview() async throws {
        let data = Data(#"{"schemaVersion":1,"status":"ready","statement":{"bankId":"fixture","templateVersion":"v1","format":"csv","accountScope":"opaque","period":{"from":"2026-07-01","to":"2026-07-31"}},"operations":[{"fingerprint":"purchase","operationDate":"2026-07-31","postingDate":null,"description":"Store","amount":"-10","currency":"RUB","type":"card_purchase","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":2,"sequence":0}}],"reconciliation":{"balanced":true,"declaredIncome":"0","declaredExpense":"10","computedIncome":"0","computedExpense":"10","difference":"0","reasons":[]},"warnings":[]}"#.utf8)
        let preview = try JSONDecoder().decode(CashflowStatementPreviewDTO.self, from: data)
        let controller = CashflowStatementImportController(
            client: StatementClientStub(result: .success(preview)), selectedMonth: august2026
        )

        await controller.preview(fileURL: URL(fileURLWithPath: "/tmp/fixture.csv"))
        #expect(controller.state == .monthMismatch)
        let detected = try #require(controller.detectedStatementMonth)

        controller.selectMonth(detected)

        #expect(controller.state == .needsReview(operationCount: 1))
        #expect(controller.preview == preview)
        #expect(Calendar.current.isDate(controller.selectedMonth, equalTo: detected, toGranularity: .month))
    }

    @Test("Internal and external transfers cannot be included")
    func everyTransferKindIsExcluded() throws {
        let data = Data(#"{"fingerprint":"transfer","operationDate":"2026-07-01","postingDate":null,"description":"Transfer","amount":"300","currency":"RUB","type":"transfer_external","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":2,"sequence":0}}"#.utf8)
        let operation = try JSONDecoder().decode(CashflowStatementPreviewDTO.Operation.self, from: data)
        let controller = CashflowStatementImportController(client: UnavailableCashflowStatementImportClient())
        #expect(!controller.canInclude(operation))
    }

    @Test("Review summary separates included, duplicates, transfers and technical rows")
    func reviewSummaryIsExplicit() throws {
        let data = Data(#"{"schemaVersion":1,"status":"ready","statement":{"bankId":"fixture","templateVersion":"v1","format":"xlsx","accountScope":"opaque","period":{"from":"2026-07-01","to":"2026-07-31"}},"operations":[{"fingerprint":"purchase","operationDate":"2026-07-01","postingDate":null,"description":"Store","amount":"-10","currency":"RUB","type":"card_purchase","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":2,"sequence":0}},{"fingerprint":"transfer","operationDate":"2026-07-02","postingDate":null,"description":"Transfer","amount":"-20","currency":"RUB","type":"transfer_external","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":3,"sequence":1}},{"fingerprint":"duplicate","operationDate":"2026-07-03","postingDate":null,"description":"Copy","amount":"-10","currency":"RUB","type":"card_purchase","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":["duplicate"],"sourceReference":{"row":4,"sequence":2}},{"fingerprint":"technical","operationDate":"2026-07-04","postingDate":null,"description":"Service row","amount":"-1","currency":"RUB","type":"technical","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":5,"sequence":3}}],"reconciliation":{"balanced":true,"declaredIncome":"0","declaredExpense":"41","computedIncome":"0","computedExpense":"41","difference":"0","reasons":[]},"warnings":[]}"#.utf8)
        let preview = try JSONDecoder().decode(CashflowStatementPreviewDTO.self, from: data)
        let summary = CashflowStatementReviewSummary(preview: preview, includedFingerprints: ["purchase"])

        #expect(summary.total == 4)
        #expect(summary.included == 1)
        #expect(summary.excluded == 3)
        #expect(summary.duplicates == 1)
        #expect(summary.transfers == 1)
        #expect(summary.technical == 1)
        #expect(CashflowStatementExclusionReason.resolve(preview.operations[1]) == .transfer)
        #expect(CashflowStatementExclusionReason.resolve(preview.operations[2]) == .duplicate)
        #expect(CashflowStatementExclusionReason.resolve(preview.operations[3]) == .technical)
    }

    @Test("Category breakdown includes only selected rows and sums exact decimal amounts")
    func categoryBreakdownTracksReviewSelection() throws {
        let data = Data(#"{"schemaVersion":1,"status":"ready","statement":{"bankId":"fixture","templateVersion":"v1","format":"xlsx","accountScope":"opaque","period":{"from":"2026-07-01","to":"2026-07-31"}},"operations":[{"fingerprint":"food-a","operationDate":"2026-07-01","postingDate":null,"description":"Cafe","amount":"-10.25","currency":"RUB","type":"card_purchase","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":2,"sequence":0}},{"fingerprint":"food-b","operationDate":"2026-07-02","postingDate":null,"description":"Shop","amount":"-20.15","currency":"RUB","type":"card_purchase","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":3,"sequence":1}},{"fingerprint":"excluded","operationDate":"2026-07-03","postingDate":null,"description":"Taxi","amount":"-99","currency":"RUB","type":"card_purchase","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":4,"sequence":2}}],"reconciliation":{"balanced":true,"declaredIncome":"0","declaredExpense":"129.40","computedIncome":"0","computedExpense":"129.40","difference":"0","reasons":[]},"warnings":[]}"#.utf8)
        let preview = try JSONDecoder().decode(CashflowStatementPreviewDTO.self, from: data)
        let food = CashflowCategoryOption(rawValue: "food", displayName: "Food", icon: "fork.knife", isCustom: false)

        let result = CashflowStatementCategoryBreakdown.make(
            preview: preview,
            includedFingerprints: ["food-a", "food-b"],
            categoryByFingerprint: ["food-a": "food", "food-b": "food", "excluded": "transport"],
            categoryOptionsByRawValue: ["food": food]
        )

        #expect(result.count == 1)
        #expect(result.first?.categoryRaw == "food")
        #expect(result.first?.transactionCount == 2)
        #expect(result.first?.amount == Decimal(string: "-30.40"))
    }

    @Test("Existing persisted fingerprints are annotated and excluded during review")
    func localDuplicatesAreExcluded() async throws {
        let data = Data(#"{"schemaVersion":1,"status":"ready","statement":{"bankId":"fixture","templateVersion":"v1","format":"csv","accountScope":"opaque","period":{"from":"2026-07-01","to":"2026-07-31"}},"operations":[{"fingerprint":"persisted","operationDate":"2026-07-01","postingDate":null,"description":"Store","merchant":"Store","amount":"-10","currency":"RUB","type":"card_purchase","categorySuggestion":null,"extractionConfidence":1,"reviewReasons":[],"sourceReference":{"row":2,"sequence":0}}],"reconciliation":{"balanced":true,"declaredIncome":"0","declaredExpense":"10","computedIncome":"0","computedExpense":"10","difference":"0","reasons":[]},"warnings":[]}"#.utf8)
        let preview = try JSONDecoder().decode(CashflowStatementPreviewDTO.self, from: data)
        let july = Calendar(identifier: .gregorian).date(from: .init(year: 2026, month: 7, day: 1))!
        let controller = CashflowStatementImportController(
            client: StatementClientStub(result: .success(preview)), selectedMonth: july
        )
        await controller.preview(fileURL: URL(fileURLWithPath: "/tmp/fixture.csv"))
        controller.annotateLocalDuplicates(["persisted", "unrelated"])
        #expect(controller.localDuplicateFingerprints == ["persisted"])
        #expect(controller.includedFingerprints.isEmpty)
        #expect(controller.isLocalDuplicate(preview.operations[0]))
    }
}
