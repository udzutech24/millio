import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Deposit confirmed-interest Cashflow projection", .serialized)
@MainActor
struct DepositCashflowProjectionTests {
    private struct InjectedFailure: Error {}

    private func fixture() throws -> (ModelContainer, ModelContext, UUID, Date, Calendar) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let maturity = calendar.date(byAdding: .month, value: 3, to: opening)!
        let id = try AccountProductFactory(modelContext: context).create(CreateProductCommand(
            productType: .deposit, name: "Deposit", currency: "RUB", openingBalance: 100_000,
            metadata: .init(deposit: DepositMeta(
                rate: 12, capitalization: .monthly, termEnd: maturity, payoutDay: nil,
                allowsTopUp: true, allowsEarlyClose: true, earlyClosePenalty: nil,
                remindEnd: false, autoRollover: false
            )), date: opening, calendar: calendar
        ))
        return (container, context, id, opening, calendar)
    }

    private func projectedRows(_ context: ModelContext) throws -> [CashflowTransaction] {
        try context.fetch(FetchDescriptor<CashflowTransaction>()).filter {
            $0.importSourceRaw == DepositCashflowProjector.importSource
        }
    }

    @Test("Confirmation and Cashflow row commit atomically and publish once")
    func confirmationIsAtomicAndPublishesOnce() throws {
        let (container, context, depositID, opening, calendar) = try fixture()
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first { $0.id == depositID })
        let missing = AccountEvent(account: account, date: opening, type: .interest, amount: 10)
        let duplicateA = AccountEvent(
            account: account, date: opening, type: .interest, amount: 10,
            sourceTransactionID: "duplicate-confirmation"
        )
        let duplicateB = AccountEvent(
            account: account, date: opening, type: .interest, amount: 20,
            sourceTransactionID: "duplicate-confirmation"
        )
        context.insert(missing)
        context.insert(duplicateA)
        context.insert(duplicateB)
        let diagnosticReport = try DepositCashflowProjector.project(
            events: [missing, duplicateA, duplicateB], through: opening, context: context
        )
        #expect(diagnosticReport.insertedCount == 0)
        #expect(diagnosticReport.diagnostics.contains(.missingSourceID(eventID: missing.id)))
        #expect(diagnosticReport.diagnostics.contains(.duplicateSourceEvent(sourceID: "duplicate-confirmation")))
        context.rollback()

        let date = calendar.date(byAdding: .month, value: 1, to: opening)!
        var refreshCount = 0
        let coordinator = DepositOperationCoordinator(
            modelContext: context, publishCommitted: { refreshCount += 1 }
        )
        let command = DepositInterestConfirmationCommand(
            operationID: "confirmed-interest-1", amount: 1_000, date: date
        )

        _ = try coordinator.confirmInterest(depositID: depositID, command: command, calendar: calendar)
        _ = try coordinator.confirmInterest(depositID: depositID, command: command, calendar: calendar)

        let verification = ModelContext(container)
        let row = try #require(projectedRows(verification).only)
        #expect(row.importReferenceKey == "confirmed-interest-1")
        #expect(row.amount == 1_000)
        #expect(row.affectsCardBalance == false)
        #expect(row.recurrenceRule == .none)
        #expect(refreshCount == 1)
    }

    @Test("Failed outer save persists and publishes nothing")
    func failedSaveLeavesNoProjectionOrRefresh() throws {
        let (container, context, depositID, opening, calendar) = try fixture()
        let date = calendar.date(byAdding: .month, value: 1, to: opening)!
        var refreshCount = 0
        let coordinator = DepositOperationCoordinator(
            modelContext: context,
            saveOperation: { _ in throw InjectedFailure() },
            publishCommitted: { refreshCount += 1 }
        )

        #expect(throws: AccountsCorePersistenceError.self) {
            try coordinator.confirmInterest(
                depositID: depositID,
                command: .init(operationID: "failed-confirmation", amount: 1_000, date: date),
                calendar: calendar
            )
        }

        let verification = ModelContext(container)
        #expect(try projectedRows(verification).isEmpty)
        #expect(try verification.fetch(FetchDescriptor<AccountEvent>()).contains {
            $0.sourceTransactionID == "failed-confirmation"
        } == false)
        #expect(refreshCount == 0)
    }

}

private extension Collection {
    var only: Element? { count == 1 ? first : nil }
}
