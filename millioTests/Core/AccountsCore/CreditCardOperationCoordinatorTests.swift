import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Credit-card operation coordinator")
@MainActor
struct CreditCardOperationCoordinatorTests {
    private func fixture() throws -> (ModelContainer, ModelContext, Account, Account) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let factory = AccountProductFactory(modelContext: context)
        let cardID = try factory.create(CreateProductCommand(
            productType: .creditCard, name: "Card", currency: "RUB", openingBalance: 100_000,
            metadata: .init(card: CardMeta(creditLimit: 100_000))
        ))
        let cashID = try factory.create(CreateProductCommand(
            productType: .cash, name: "Cash", currency: "RUB", openingBalance: 10_000
        ))
        let accounts = try context.fetch(FetchDescriptor<Account>())
        return (
            container, context,
            try #require(accounts.first { $0.id == cardID }),
            try #require(accounts.first { $0.id == cashID })
        )
    }

    @Test("Purchase creates one typed event and one expense exactly once")
    func purchaseIsAtomicAndIdempotent() throws {
        let (container, context, card, _) = try fixture()
        _ = container
        let coordinator = CreditCardOperationCoordinator(modelContext: context)
        let command = CreditCardCashflowCommand(
            operationID: "purchase-1", kind: .purchase, amount: 1_500, categoryID: "food"
        )
        let first = try coordinator.record(card: card, command: command)
        let second = try coordinator.record(card: card, command: command)

        #expect(!first.wasAlreadyPersisted)
        #expect(second.wasAlreadyPersisted)
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).count == 1)
        let linkedEvents = try context.fetch(FetchDescriptor<AccountEvent>()).filter { $0.sourceTransactionID == "purchase-1" }
        #expect(linkedEvents.count == 1)
        #expect(linkedEvents.first?.type == .creditCardPurchase)
        #expect(first.cashflowTransaction?.transactionType == .expense)
        #expect(first.cashflowTransaction?.shouldAffectCashflowTotals == true)
        #expect(throws: CreditCardOperationError.duplicateOperationConflict) {
            try coordinator.record(card: card, command: .init(
                operationID: "purchase-1", kind: .purchase, amount: 1_501
            ))
        }
    }

    @Test("Fee and interest each project one Cashflow expense")
    func feeAndInterestProjection() throws {
        let (container, context, card, _) = try fixture()
        _ = container
        let coordinator = CreditCardOperationCoordinator(modelContext: context)
        _ = try coordinator.record(card: card, command: .init(
            operationID: "fee-1", kind: .fee, amount: 100
        ))
        _ = try coordinator.record(card: card, command: .init(
            operationID: "interest-1", kind: .interest, amount: 200
        ))
        let transactions = try context.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(transactions.count == 2)
        #expect(transactions.allSatisfy { $0.transactionType == .expense && $0.shouldAffectCashflowTotals })
        let types = Set(try context.fetch(FetchDescriptor<AccountEvent>()).map(\.type))
        #expect(types.contains(.creditCardFee))
        #expect(types.contains(.creditCardInterest))
    }

    @Test("Refund is capped by the remaining purchase and reduces expense")
    func refundCap() throws {
        let (container, context, card, _) = try fixture()
        _ = container
        let coordinator = CreditCardOperationCoordinator(modelContext: context)
        _ = try coordinator.record(card: card, command: .init(
            operationID: "purchase-1", kind: .purchase, amount: 1_000
        ))
        let refund = try coordinator.record(card: card, command: .init(
            operationID: "refund-1", kind: .refund, amount: 600, purchaseID: "purchase-1"
        ))
        #expect(refund.cashflowTransaction?.transactionType == .expense)
        #expect(refund.cashflowTransaction?.amount == -600)
        #expect(throws: CreditCardOperationError.refundExceedsPurchase) {
            try coordinator.record(card: card, command: .init(
                operationID: "refund-2", kind: .refund, amount: 401, purchaseID: "purchase-1"
            ))
        }
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).count == 2)
    }

    @Test("Repayment writes both event legs and a transfer excluded from Cashflow totals")
    func repayment() throws {
        let (container, context, card, cash) = try fixture()
        _ = container
        let result = try CreditCardOperationCoordinator(modelContext: context).repay(
            card: card, from: cash,
            command: .init(operationID: "repay-1", amount: 2_000)
        )
        #expect(result.cardEvent.type == .creditCardRepayment)
        #expect(result.sourceEvent?.type == .transferOut)
        #expect(result.cardEvent.transferID == result.sourceEvent?.transferID)
        #expect(result.cashflowTransaction?.transactionType == .transfer)
        #expect(result.cashflowTransaction?.shouldAffectCashflowTotals == false)
        #expect(try context.fetch(FetchDescriptor<AccountEvent>()).filter { $0.sourceTransactionID == "repay-1" }.count == 2)
    }

    @Test("Repayment rejects invalid sources, currency mismatch and insufficient funds")
    func repaymentPolicy() throws {
        let (container, context, card, cash) = try fixture()
        _ = container
        let coordinator = CreditCardOperationCoordinator(modelContext: context)
        #expect(throws: CreditCardOperationError.insufficientFunds) {
            try coordinator.repay(card: card, from: cash, command: .init(operationID: "large", amount: 10_001))
        }
        cash.currency = "USD"
        try context.save()
        #expect(throws: CreditCardOperationError.currencyMismatch) {
            try coordinator.repay(card: card, from: cash, command: .init(operationID: "fx", amount: 1))
        }
        cash.currency = "RUB"
        cash.archivedAt = .now
        try context.save()
        #expect(throws: CreditCardOperationError.invalidRepaymentSource) {
            try coordinator.repay(card: card, from: cash, command: .init(operationID: "archived", amount: 1))
        }
    }

    @Test("Save failure rolls back the whole linked graph")
    func rollback() throws {
        struct Failure: Error {}
        let (container, context, card, _) = try fixture()
        _ = container
        let baselineEvents = try context.fetch(FetchDescriptor<AccountEvent>()).count
        let coordinator = CreditCardOperationCoordinator(modelContext: context, saveOperation: { _ in throw Failure() })
        #expect(throws: AccountsCorePersistenceError.self) {
            try coordinator.record(card: card, command: .init(
                operationID: "failed", kind: .purchase, amount: 100
            ))
        }
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AccountEvent>()).count == baselineEvents)
        #expect(!context.hasChanges)
    }

    @Test("Closed month blocks credit-card purchase before any graph insert")
    func closedMonthBlocksPurchase() throws {
        let (container, context, card, _) = try fixture()
        _ = container
        let date = Date(timeIntervalSince1970: 1_751_328_000)
        let monthStart = try #require(Calendar.autoupdatingCurrent.dateInterval(of: .month, for: date)?.start)
        context.insert(CashflowMonthClosureEvent(monthStart: monthStart, kind: .close, occurredAt: .now))
        try context.save()

        #expect(throws: CashflowMonthMutationPolicyError.closedMonth) {
            try CreditCardOperationCoordinator(modelContext: context).record(
                card: card,
                command: .init(operationID: "closed-purchase", kind: .purchase, amount: 100, date: date)
            )
        }
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AccountEvent>()).allSatisfy { $0.sourceTransactionID != "closed-purchase" })
    }
}
