import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Credit-card signed financial contract")
struct CreditCardFinancialContractTests {
    @Test("Legacy available balance maps to one signed net position")
    func legacyAvailableBalanceCharacterization() throws {
        let snapshot = try #require(CreditCardFinancialContract.snapshot(
            rawAvailableBalance: 80_000,
            creditLimit: 100_000
        ))
        #expect(snapshot.netPosition == -20_000)
        #expect(snapshot.debt == 20_000)
        #expect(snapshot.availableLimit == 80_000)
        #expect(snapshot.utilization == Decimal(string: "0.2"))
        #expect(snapshot.overpayment == 0)
    }

    @Test("Settled and overpaid cards remain distinct")
    func settledAndOverpaid() throws {
        let settled = try #require(CreditCardFinancialContract.snapshot(
            rawAvailableBalance: 100_000,
            creditLimit: 100_000
        ))
        let overpaid = try #require(CreditCardFinancialContract.snapshot(
            rawAvailableBalance: 105_000,
            creditLimit: 100_000
        ))
        #expect(settled.netPosition == 0)
        #expect(settled.debt == 0)
        #expect(settled.availableLimit == 100_000)
        #expect(overpaid.netPosition == 5_000)
        #expect(overpaid.overpayment == 5_000)
        #expect(overpaid.availableLimit == 100_000)
        #expect(overpaid.utilization == 0)
    }

    @Test("Over-limit debt is explicit and utilization is not clipped")
    func overLimit() throws {
        let snapshot = try #require(CreditCardFinancialContract.snapshot(
            rawAvailableBalance: -20_000,
            creditLimit: 100_000
        ))
        #expect(snapshot.debt == 120_000)
        #expect(snapshot.availableLimit == -20_000)
        #expect(snapshot.utilization == Decimal(string: "1.2"))
        #expect(snapshot.isOverLimit)
    }

    @Test("Invalid limits do not produce presentation values", arguments: [Decimal.zero, -1])
    func rejectsInvalidLimit(limit: Decimal) {
        #expect(CreditCardFinancialContract.snapshot(rawAvailableBalance: 0, creditLimit: limit) == nil)
    }

    @Test("Only typed card fee and interest events are accrued")
    func accruedCharges() throws {
        let events = [
            AccountEvent(date: .now, type: .creditCardFee, amount: 300),
            AccountEvent(date: .now, type: .creditCardInterest, amount: 700),
            AccountEvent(date: .now, type: .fee, amount: 900),
            AccountEvent(date: .now, type: .creditCardFee, amount: -50)
        ]
        let snapshot = try #require(CreditCardFinancialContract.snapshot(
            rawAvailableBalance: 99_000,
            creditLimit: 100_000,
            events: events
        ))
        #expect(snapshot.accruedFees == 300)
        #expect(snapshot.accruedInterest == 700)
    }

    @Test("Historical signed value changes only at real event timestamps")
    func historicalReplay() {
        let openingDate = Date(timeIntervalSince1970: 1_700_000_000)
        let purchaseDate = openingDate.addingTimeInterval(86_400)
        let events = [
            AccountEvent(date: openingDate, type: .openingBalance, amount: 100_000),
            AccountEvent(date: purchaseDate, type: .creditCardPurchase, amount: 25_000)
        ]
        let beforePurchase = AccountBalanceEngine.balanceAt(
            events: events,
            kind: .debitCard,
            on: purchaseDate.addingTimeInterval(-1)
        )
        let atPurchase = AccountBalanceEngine.balanceAt(
            events: events,
            kind: .debitCard,
            on: purchaseDate
        )
        #expect(AccountTotalsContribution.signedValue(
            rawBalance: beforePurchase,
            kind: .debitCard,
            creditLimit: 100_000
        ) == 0)
        #expect(AccountTotalsContribution.signedValue(
            rawBalance: atPurchase,
            kind: .debitCard,
            creditLimit: 100_000
        ) == -25_000)
    }
}

@Suite("Credit-card typed events")
@MainActor
struct CreditCardEventContractTests {
    private func makeCard() throws -> (ModelContainer, ModelContext, Account) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let id = try AccountProductFactory(modelContext: context).create(CreateProductCommand(
            productType: .creditCard,
            name: "Card",
            currency: "RUB",
            openingBalance: 100_000,
            metadata: .init(card: CardMeta(
                bank: nil, last4: "1234", creditLimit: 100_000, statementDay: nil,
                dueDay: nil, minPayment: nil, graceDays: nil, overdraftLimit: nil
            ))
        ))
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first { $0.id == id })
        return (container, context, account)
    }

    @Test("Purchase/fee/interest increase debt; refund/repayment decrease it")
    func operationSigns() throws {
        let (container, context, card) = try makeCard()
        _ = container
        let service = AccountsCoreService(modelContext: context)

        try service.recordCreditCardEvent(account: card, operation: .purchase, amount: 10_000)
        try service.recordCreditCardEvent(account: card, operation: .fee, amount: 500)
        try service.recordCreditCardEvent(account: card, operation: .interest, amount: 1_000)
        try service.recordCreditCardEvent(account: card, operation: .refund, amount: 2_000)
        try service.recordCreditCardEvent(account: card, operation: .repayment, amount: 4_000)

        let raw = AccountBalanceEngine.balanceAt(events: card.events ?? [], kind: card.kind, on: .now)
        let snapshot = try #require(CreditCardFinancialContract.snapshot(
            rawAvailableBalance: raw,
            creditLimit: 100_000,
            events: card.events ?? []
        ))
        #expect(snapshot.netPosition == -5_500)
        #expect(snapshot.debt == 5_500)
        #expect(AccountTotalsContribution.signedValue(
            rawBalance: raw,
            kind: card.kind,
            creditLimit: card.cardMeta?.creditLimit
        ) == -5_500)
    }

    @Test("Typed events are credit-card-only, positive and blocked after archive")
    func validationBoundary() throws {
        let (container, context, card) = try makeCard()
        _ = container
        let service = AccountsCoreService(modelContext: context)

        #expect(throws: AccountsCoreServiceError.self) {
            try service.recordCreditCardEvent(account: card, operation: .purchase, amount: 0)
        }
        card.archivedAt = .now
        try context.save()
        #expect(throws: AccountsCoreServiceError.self) {
            try service.recordCreditCardEvent(account: card, operation: .purchase, amount: 100)
        }
    }

    @Test("Catalog exposes typed events only for credit cards")
    func catalogBoundary() {
        for operation in CreditCardOperationKind.allCases {
            #expect(ProductDefinitionCatalog.isEvent(operation.eventType, allowedFor: .creditCard))
            #expect(!ProductDefinitionCatalog.isEvent(operation.eventType, allowedFor: .debitCard))
            #expect(!ProductDefinitionCatalog.isEvent(operation.eventType, allowedFor: .cash))
        }
    }
}
