import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Account product transition coordinator")
@MainActor
struct AccountProductTransitionCoordinatorTests {
    private struct Failure: Error {}

    @Test func correctionMutatesFullTupleOnceAndRetryIsIdempotent() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let sourceID = try AccountProductFactory(modelContext: context).create(.init(
            productType: .cash, name: "Cash", currency: "RUB", openingBalance: 500
        ))
        let command = AccountProductCorrectionCommand(
            operationID: "correction-1", sourceID: sourceID, target: .bankAccount,
            targetMetadata: .init(), effectiveDate: Date()
        )
        let coordinator = AccountProductTransitionCoordinator(modelContext: context)
        try coordinator.correct(command)
        try coordinator.correct(command)

        let verify = ModelContext(container)
        let account = try #require(try verify.fetch(FetchDescriptor<Account>()).first { $0.id == sourceID })
        #expect(account.productType == .bankAccount)
        #expect(account.kind == .bankAccount)
        #expect(try verify.fetch(FetchDescriptor<AccountEvent>()).filter {
            $0.sourceTransactionID == "product-correction:correction-1"
        }.count == 1)
    }

    @Test func replacementArchivesSourceAndHandsOffBalanceWithoutOverlap() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let opening = Date(timeIntervalSince1970: 1_700_000_000)
        let sourceID = try AccountProductFactory(modelContext: context).create(.init(
            productType: .deposit, name: "Deposit", currency: "RUB", openingBalance: 1_000,
            metadata: .init(deposit: .init(
                rate: 10, capitalization: .monthly, termEnd: opening.addingTimeInterval(90 * 86_400),
                payoutDay: nil, allowsTopUp: false, allowsEarlyClose: true,
                earlyClosePenalty: 0, remindEnd: false, autoRollover: false
            )), date: opening
        ))
        let targetID = UUID(), effective = opening.addingTimeInterval(10 * 86_400)
        let command = AccountProductConversionCommand(
            operationID: "conversion-1", sourceID: sourceID, targetID: targetID,
            target: .bankAccount, targetMetadata: .init(), effectiveDate: effective
        )
        let coordinator = AccountProductTransitionCoordinator(modelContext: context)
        try coordinator.convert(command); try coordinator.convert(command)

        let verify = ModelContext(container)
        let accounts = try verify.fetch(FetchDescriptor<Account>())
        let source = try #require(accounts.first { $0.id == sourceID })
        let target = try #require(accounts.first { $0.id == targetID })
        #expect(source.archivedAt == effective)
        #expect(!source.participates(on: effective))
        #expect(target.participates(on: effective))
        #expect(target.group?.id == source.group?.id)
        #expect(AccountBalanceEngine.balanceAt(events: target.events ?? [], kind: target.kind, on: effective) == 1_000)
        #expect(accounts.filter { $0.id == targetID }.count == 1)
    }

    @Test func saveFailureLeavesSourceUntouchedAndNoTargetGraph() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let sourceID = try AccountProductFactory(modelContext: context).create(.init(
            productType: .deposit, name: "Deposit", currency: "RUB", openingBalance: 1_000,
            metadata: .init(deposit: .init(
                rate: 10, capitalization: .monthly, termEnd: Date().addingTimeInterval(90 * 86_400),
                payoutDay: nil, allowsTopUp: false, allowsEarlyClose: true,
                earlyClosePenalty: 0, remindEnd: false, autoRollover: false
            ))
        ))
        let targetID = UUID()
        let coordinator = AccountProductTransitionCoordinator(
            modelContext: context, saveOperation: { _ in throw Failure() }
        )
        #expect(throws: AccountsCorePersistenceError.self) {
            try coordinator.convert(.init(
                operationID: "failure", sourceID: sourceID, targetID: targetID,
                target: .bankAccount, targetMetadata: .init(), effectiveDate: Date()
            ))
        }
        let verify = ModelContext(container)
        let accounts = try verify.fetch(FetchDescriptor<Account>())
        #expect(accounts.first { $0.id == sourceID }?.archivedAt == nil)
        #expect(accounts.allSatisfy { $0.id != targetID })
    }
}
