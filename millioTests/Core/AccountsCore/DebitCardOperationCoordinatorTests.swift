import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Debit-card operation coordinator")
@MainActor
struct DebitCardOperationCoordinatorTests {
    private func fixture(opening: Decimal = 1_000) throws -> (ModelContainer, ModelContext, Account) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let id = try AccountProductFactory(modelContext: context).create(.init(productType: .debitCard, name: "Debit", currency: "RUB", openingBalance: opening, metadata: .init(card: CardMeta())))
        return (container, context, try #require(try context.fetch(FetchDescriptor<Account>()).first { $0.id == id }))
    }

    @Test("Expense and Cashflow projection are atomic and idempotent")
    func expenseExactlyOnce() throws {
        let (container, context, account) = try fixture()
        _ = container
        let coordinator = DebitCardOperationCoordinator(modelContext: context)
        let command = DebitCardOperationCommand(operationID: "expense-1", kind: .expense, amount: 250)
        let first = try coordinator.record(account: account, command: command)
        let retry = try coordinator.record(account: account, command: command)
        #expect(!first.wasAlreadyPersisted)
        #expect(retry.wasAlreadyPersisted)
        #expect(try context.fetch(FetchDescriptor<AccountEvent>()).filter { $0.sourceTransactionID == "expense-1" }.count == 1)
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).filter { $0.uniqueID == "expense-1" }.count == 1)
        #expect(throws: DebitCardOperationCoordinatorError.duplicateOperationConflict) {
            try coordinator.record(account: account, command: .init(operationID: "expense-1", kind: .expense, amount: 251))
        }
    }

    @Test("Failure rolls the whole graph back and cannot be resurrected")
    func rollback() throws {
        struct Failure: Error {}
        let (container, context, account) = try fixture()
        _ = container
        let baseline = try context.fetch(FetchDescriptor<AccountEvent>()).count
        let coordinator = DebitCardOperationCoordinator(modelContext: context, saveOperation: { _ in throw Failure() })
        #expect(throws: AccountsCorePersistenceError.self) {
            try coordinator.record(account: account, command: .init(operationID: "failed", kind: .expense, amount: 10))
        }
        #expect(!context.hasChanges)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<AccountEvent>()).count == baseline)
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).isEmpty)
    }

    @Test("Refund is linked to and capped by the original expense")
    func refund() throws {
        let (container, context, account) = try fixture()
        _ = container
        let coordinator = DebitCardOperationCoordinator(modelContext: context)
        _ = try coordinator.record(account: account, command: .init(operationID: "purchase", kind: .expense, amount: 600))
        let refund = try coordinator.record(account: account, command: .init(operationID: "refund", kind: .refund(originalOperationID: "purchase"), amount: 400))
        #expect(refund.cashflowTransaction?.operationGroupID == "purchase")
        #expect(refund.cashflowTransaction?.amount == -400)
        #expect(throws: DebitCardOperationCoordinatorError.refundExceedsExpense) {
            try coordinator.record(account: account, command: .init(operationID: "refund-2", kind: .refund(originalOperationID: "purchase"), amount: 201))
        }
        _ = try coordinator.record(account: account, command: .init(operationID: "purchase-2", kind: .expense, amount: 10))
        #expect(throws: DebitCardOperationCoordinatorError.duplicateOperationConflict) {
            try coordinator.record(account: account, command: .init(operationID: "refund", kind: .refund(originalOperationID: "purchase-2"), amount: 400))
        }
    }

    @Test("Transfer has two linked legs and no Cashflow income/expense effect")
    func transfer() throws {
        let (container, context, source) = try fixture()
        let destinationID = try AccountProductFactory(modelContext: context).create(.init(productType: .bankAccount, name: "Bank", currency: "RUB", openingBalance: 0))
        let destination = try #require(try context.fetch(FetchDescriptor<Account>()).first { $0.id == destinationID })
        _ = container
        let result = try DebitCardOperationCoordinator(modelContext: context).transfer(from: source, to: destination, operationID: "transfer", amount: 300)
        #expect(result.events.count == 2)
        #expect(Set(result.events.compactMap(\.transferID)).count == 1)
        #expect(result.cashflowTransaction?.transactionType == .transfer)
        #expect(result.cashflowTransaction?.shouldAffectCashflowTotals == false)
    }

    @Test("Two concurrently submitted withdrawals cannot overspend")
    func concurrentDoubleSpend() async throws {
        let (container, seedContext, seeded) = try fixture(opening: 100)
        let accountID = seeded.id
        _ = seedContext

        @MainActor func attempt(_ operationID: String) -> Bool {
            let context = ModelContext(container)
            guard let account = try? context.fetch(FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == accountID })).first else { return false }
            do {
                _ = try DebitCardOperationCoordinator(modelContext: context).record(account: account, command: .init(operationID: operationID, kind: .expense, amount: 60))
                return true
            } catch DebitCardContractError.insufficientFunds {
                return false
            } catch {
                return false
            }
        }

        async let first = attempt("race-1")
        async let second = attempt("race-2")
        let committed = await [first, second].filter { $0 }.count
        #expect(committed == 1)

        let verification = ModelContext(container)
        let events = try verification.fetch(FetchDescriptor<AccountEvent>(predicate: #Predicate<AccountEvent> { $0.account?.id == accountID }))
        #expect(AccountBalanceEngine.balanceAt(events: events, kind: .debitCard, on: .distantFuture) == 40)
    }

    @Test("Negative opening balance is rejected before insertion")
    func openingValidation() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        #expect(throws: AccountProductFactoryError.invalidDebitOpeningBalance) {
            try AccountProductFactory(modelContext: context).create(.init(productType: .debitCard, name: "Debit", currency: "RUB", openingBalance: -1, metadata: .init(card: CardMeta())))
        }
        #expect(try context.fetch(FetchDescriptor<Account>()).isEmpty)
    }

    @Test("Closed month blocks debit expense and transfer before insertion")
    func closedMonthBlocksWrites() throws {
        let (container, context, source) = try fixture()
        _ = container
        let destinationID = try AccountProductFactory(modelContext: context).create(.init(
            productType: .bankAccount, name: "Bank", currency: "RUB", openingBalance: 0
        ))
        let destination = try #require(try context.fetch(FetchDescriptor<Account>()).first { $0.id == destinationID })
        let date = Date(timeIntervalSince1970: 1_751_328_000)
        let monthStart = try #require(Calendar.autoupdatingCurrent.dateInterval(of: .month, for: date)?.start)
        context.insert(CashflowMonthClosureEvent(monthStart: monthStart, kind: .close, occurredAt: .now))
        try context.save()
        let baselineEvents = try context.fetch(FetchDescriptor<AccountEvent>()).count

        #expect(throws: CashflowMonthMutationPolicyError.closedMonth) {
            try DebitCardOperationCoordinator(modelContext: context).record(
                account: source,
                command: .init(operationID: "closed-expense", kind: .expense, amount: 10, date: date)
            )
        }
        #expect(throws: CashflowMonthMutationPolicyError.closedMonth) {
            try DebitCardOperationCoordinator(modelContext: context).transfer(
                from: source, to: destination, operationID: "closed-transfer", amount: 10, date: date
            )
        }
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AccountEvent>()).count == baselineEvents)
    }
}
