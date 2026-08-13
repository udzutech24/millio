import Foundation
import SwiftData
import Testing
@testable import millio

@MainActor
struct CashflowStatementApplyServiceTests {
    private static var retainedContainers: [ModelContainer] = []

    private func context() throws -> ModelContext {
        let schema = Schema([CashflowMonthClosureEvent.self, CashflowTransaction.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    private func operation(fingerprint: String, amount: Decimal = -100, accountID: String? = "account") -> CashflowApprovedStatementOperation {
        .init(fingerprint: fingerprint, date: Date(timeIntervalSince1970: 1_783_814_400), amount: amount,
              currency: "RUB", type: .expense, categoryRaw: ExpenseCategory.bills.rawValue,
              accountID: accountID, note: "Merchant")
    }

    @Test("Import can remain unlinked and never affects an account balance")
    func unlinkedImport() throws {
        let context = try context()
        let service = CashflowStatementApplyService(modelContext: context)
        let result = try service.apply([operation(fingerprint: "unlinked", accountID: nil)])
        #expect(result.insertedFingerprints == ["unlinked"])
        #expect(result.skippedFingerprints.isEmpty)
        let transaction = try #require(context.fetch(FetchDescriptor<CashflowTransaction>()).first)
        #expect(transaction.cardID == nil)
        #expect(transaction.affectsCardBalance == false)
    }

    @Test("Reimport is idempotent and equal amounts with distinct fingerprints survive")
    func idempotency() throws {
        let context = try context()
        let service = CashflowStatementApplyService(modelContext: context)
        let first = try service.apply([operation(fingerprint: "a"), operation(fingerprint: "b")])
        #expect(first.insertedFingerprints == ["a", "b"])
        #expect(first.skippedFingerprints.isEmpty)
        let second = try service.apply([operation(fingerprint: "a"), operation(fingerprint: "b")])
        #expect(second.insertedFingerprints.isEmpty)
        #expect(second.skippedFingerprints == ["a", "b"])
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).count == 2)
    }

    @Test("Invalid batch is rejected before any insert")
    func atomicPreflight() throws {
        let context = try context()
        let service = CashflowStatementApplyService(modelContext: context)
        #expect(throws: CashflowStatementApplyError.invalidOperation) {
            try service.apply([operation(fingerprint: "valid"), operation(fingerprint: "", amount: 0)])
        }
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).isEmpty)
    }

    @Test("Closed month rejects the whole batch before insert")
    func closedMonthIsAtomic() throws {
        let context = try context()
        let item = operation(fingerprint: "closed")
        context.insert(CashflowMonthClosureEvent(
            monthStart: item.date,
            kind: .close,
            occurredAt: item.date.addingTimeInterval(1)
        ))
        try context.save()
        let service = CashflowStatementApplyService(modelContext: context)
        #expect(throws: CashflowStatementApplyError.closedMonth) { try service.apply([item]) }
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).isEmpty)
    }
}
