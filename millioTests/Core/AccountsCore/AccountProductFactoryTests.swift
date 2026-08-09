import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("AccountProductFactory atomic graph")
@MainActor
struct AccountProductFactoryTests {
    private func makeStack() throws -> (ModelContainer, ModelContext, AccountProductFactory) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        return (container, container.mainContext, AccountProductFactory(modelContext: container.mainContext))
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func depositCommand(id: UUID = UUID()) -> CreateProductCommand {
        CreateProductCommand(
            accountID: id,
            productType: .deposit,
            name: "Deposit",
            currency: "rub",
            openingBalance: 100_000,
            metadata: .init(deposit: DepositMeta(
                rate: 12,
                capitalization: .monthly,
                termEnd: utcCalendar.date(from: DateComponents(year: 2025, month: 4, day: 1)),
                payoutDay: nil,
                allowsTopUp: true,
                allowsEarlyClose: false,
                earlyClosePenalty: nil,
                remindEnd: false,
                autoRollover: false
            )),
            date: utcCalendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!,
            calendar: utcCalendar
        )
    }

    @Test("Deposit account, opening anchor and full schedule commit together")
    func depositGraphCommitsInOneSave() throws {
        let (_, context, factory) = try makeStack()
        let accountID = try factory.create(depositCommand())
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first { $0.id == accountID })

        #expect(account.productType == .deposit)
        #expect(account.kind == .deposit)
        #expect(account.currency == "RUB")
        let events = try context.fetch(FetchDescriptor<AccountEvent>()).filter { $0.account?.id == account.id }
        #expect(events.filter { $0.type == .openingBalance }.count == 1)
        #expect(events.filter { $0.type == .interest }.count == 3)
    }

    @Test("Market account never commits without its mandatory buy")
    func marketGraphRequiresAndCommitsBuy() throws {
        let (_, context, factory) = try makeStack()
        let metadata = AccountProductMetadata(market: MarketMeta(symbol: "AAPL", assetClass: .stock))
        let invalid = CreateProductCommand(
            productType: .marketStock,
            name: "AAPL",
            currency: "USD",
            openingBalance: 0,
            metadata: metadata
        )
        #expect(throws: AccountProductFactoryError.missingMarketPurchase) {
            try factory.create(invalid)
        }
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)

        let valid = CreateProductCommand(
            productType: .marketStock,
            name: "AAPL",
            currency: "USD",
            openingBalance: 0,
            metadata: metadata,
            initialMarketPurchase: .init(quantity: 2, unitPrice: 180)
        )
        let accountID = try factory.create(valid)
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first { $0.id == accountID })
        let events = try context.fetch(FetchDescriptor<AccountEvent>()).filter { $0.account?.id == account.id }
        #expect(events.filter { $0.type == .openingBalance }.count == 1)
        #expect(events.filter { $0.type == .buy }.count == 1)
        #expect(events.first(where: { $0.type == .buy })?.quantity == 2)
    }

    @Test("Every injected build/save stage leaves store and caller context clean", arguments: ProductCreationStage.allCases)
    func everyStageFailureIsClean(stage: ProductCreationStage) throws {
        let (_, context, factory) = try makeStack()
        let failedID = UUID()
        let command: CreateProductCommand
        if stage == .marketPurchase {
            command = CreateProductCommand(
                accountID: failedID,
                productType: .marketStock,
                name: "AAPL",
                currency: "USD",
                openingBalance: 0,
                metadata: .init(market: MarketMeta(symbol: "AAPL", assetClass: .stock)),
                initialMarketPurchase: .init(quantity: 1, unitPrice: 100)
            )
        } else {
            command = depositCommand(id: failedID)
        }

        #expect(throws: AccountProductFactoryError.injectedFailure(stage)) {
            try factory.create(command) { visited in
                if visited == stage { throw AccountProductFactoryError.injectedFailure(stage) }
            }
        }

        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AccountEvent>()) == 0)

        let unrelated = AccountGroup(name: "Unrelated")
        context.insert(unrelated)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<AccountGroup>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AccountEvent>()) == 0)
    }

    @Test("Factory rejects unknown and contradictory identity before insertion")
    func invalidIdentityDoesNotMutateCaller() throws {
        let (_, context, factory) = try makeStack()
        let unknown = CreateProductCommand(
            productType: .unknownLegacy,
            name: "Unknown",
            currency: "RUB",
            openingBalance: 0
        )
        #expect(throws: ProductCatalogValidationError.unknownLegacyCannotBeCreated) {
            try factory.create(unknown)
        }

        let invalidCard = CreateProductCommand(
            productType: .creditCard,
            name: "Broken card",
            currency: "RUB",
            openingBalance: 0,
            metadata: .init(card: CardMeta(
                bank: nil, last4: nil, creditLimit: 0, statementDay: nil, dueDay: nil,
                minPayment: nil, graceDays: nil, overdraftLimit: nil
            ))
        )
        #expect(throws: ProductCatalogValidationError.invalidCreditLimit) {
            try factory.create(invalidCard)
        }
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
    }

    @Test("Actual save failure rolls back and later unrelated save cannot resurrect graph")
    func actualSaveFailureIsClean() throws {
        struct SaveFailure: Error {}
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let factory = AccountProductFactory(modelContext: context) { _ in throw SaveFailure() }

        #expect(throws: SaveFailure.self) {
            try factory.create(depositCommand())
        }
        #expect(!context.hasChanges)
        context.insert(AccountGroup(name: "Unrelated"))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AccountEvent>()) == 0)
    }

    @Test("Interactive factory rejects an unsaved group without leaking account rows")
    func unsavedGroupIsRejected() throws {
        let (_, context, factory) = try makeStack()
        let group = AccountGroup(name: "Pending")
        context.insert(group)
        let command = CreateProductCommand(
            productType: .cash,
            name: "Cash",
            currency: "RUB",
            openingBalance: 100,
            groupID: group.id
        )

        #expect(throws: AccountProductFactoryError.missingGroup(group.id)) {
            try factory.create(command)
        }
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 0)
    }

    @Test("Initial visibility and order are part of the atomic graph")
    func initialAccountOptionsPersist() throws {
        let (_, context, factory) = try makeStack()
        let id = try factory.create(CreateProductCommand(
            productType: .cash,
            name: "Hidden marker",
            currency: "RUB",
            openingBalance: 0,
            includeInTotal: false,
            order: 17
        ))
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first { $0.id == id })
        #expect(account.includeInTotal == false)
        #expect(account.order == 17)
        #expect(account.productType == .cash)
        #expect((account.events ?? []).contains { $0.type == .openingBalance })
    }
}
