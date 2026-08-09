import Foundation
import SwiftData
import Testing
@testable import millio

/// Production contract: every preset visible in the add-account UI resolves one complete product
/// command and the atomic factory persists the expected identity, metadata and initial graph.
@Suite("All visible presets use AccountProductFactory")
@MainActor
struct AllPresetsOnNewCoreTests {
    private struct Expectation {
        let product: AccountProductType
        let kind: AccountKind
        let meta: AccountMetaKind?
        let balance: Decimal
        let hasBuy: Bool
    }

    private func makeInput(
        for option: FinanceAddAccountProductOption,
        date: Date
    ) -> (FinanceProductCreationInput, Expectation) {
        switch option {
        case .card:
            return (.init(
                option: option, name: "Card", currency: "RUB", amount: 100,
                cardType: .debit, bank: .sberbank, cardLast4: "1234", date: date
            ), .init(product: .debitCard, kind: .debitCard, meta: .card, balance: 100, hasBuy: false))
        case .account:
            return (.init(option: option, name: "Account", currency: "RUB", amount: 100, date: date),
                    .init(product: .bankAccount, kind: .bankAccount, meta: nil, balance: 100, hasBuy: false))
        case .deposit:
            let termEnd = Calendar(identifier: .gregorian).date(byAdding: .month, value: 3, to: date)
            let meta = DepositMeta(
                rate: 12, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
                allowsTopUp: true, allowsEarlyClose: false, earlyClosePenalty: nil,
                remindEnd: false, autoRollover: false
            )
            return (.init(
                option: option, name: "Deposit", currency: "RUB", amount: 100,
                depositMeta: meta, date: date
            ), .init(product: .deposit, kind: .deposit, meta: .deposit, balance: 100, hasBuy: false))
        case .credit:
            let meta = AccountsCoreAdditionBridge.loanMeta(
                principal: 100, monthlyPayment: 10, paymentDay: 10, termEnd: nil
            )
            return (.init(
                option: option, name: "Loan", currency: "RUB", amount: 100,
                loanMeta: meta, date: date
            ), .init(product: .loan, kind: .loan, meta: .loan, balance: -100, hasBuy: false))
        case .debt:
            return (.init(
                option: option, name: "Debt", currency: "RUB", amount: 100,
                debtDirection: .owedByMe, date: date
            ), .init(product: .payable, kind: .debt, meta: .debt, balance: -100, hasBuy: false))
        case .investment:
            return (.init(
                option: option, name: "ETF", currency: "USD", amount: 999,
                marketSymbol: " voo ", marketQuantity: 2, marketUnitPrice: 50, date: date
            ), .init(product: .genericMarketInvestment, kind: .marketInvestment, meta: .market, balance: 100, hasBuy: true))
        case .house:
            return (.init(option: option, name: "House", currency: "RUB", amount: 100, date: date),
                    .init(product: .realEstate, kind: .manualAsset, meta: nil, balance: 100, hasBuy: false))
        case .stocks:
            return (.init(
                option: option, name: "Stock", currency: "USD", amount: 999,
                marketSymbol: "aapl", marketQuantity: 2, marketUnitPrice: 50, date: date
            ), .init(product: .marketStock, kind: .marketInvestment, meta: .market, balance: 100, hasBuy: true))
        case .business:
            return (.init(option: option, name: "Business", currency: "RUB", amount: 100, date: date),
                    .init(product: .business, kind: .manualAsset, meta: nil, balance: 100, hasBuy: false))
        case .crypto:
            return (.init(
                option: option, name: "Crypto", currency: "USD", amount: 999,
                marketSymbol: "btc", marketQuantity: 2, marketUnitPrice: 50, date: date
            ), .init(product: .marketCrypto, kind: .marketInvestment, meta: .market, balance: 100, hasBuy: true))
        case .other:
            return (.init(option: option, name: "Other", currency: "RUB", amount: 100, date: date),
                    .init(product: .otherManualAsset, kind: .manualAsset, meta: nil, balance: 100, hasBuy: false))
        }
    }

    @Test
    func everyVisiblePresetPersistsExpectedCompleteGraph() throws {
        #expect(FinanceAddAccountProductOption.visibleOptions.count == 10)
        #expect(!FinanceAddAccountProductOption.visibleOptions.contains(.other))
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        for option in FinanceAddAccountProductOption.visibleOptions {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let context = container.mainContext
            let (input, expected) = makeInput(for: option, date: date)
            let command = try FinanceProductCreationCommandResolver.resolve(input)
            let id = try AccountProductFactory(modelContext: context).create(command)
            let account = try #require(context.fetch(FetchDescriptor<Account>()).first { $0.id == id })
            let events = try context.fetch(FetchDescriptor<AccountEvent>()).filter { $0.account?.id == id }

            #expect(account.productType == expected.product, "\(option)")
            #expect(account.kind == expected.kind, "\(option)")
            #expect(AccountProductMetadata(account: account).presentKinds == Set([expected.meta].compactMap { $0 }), "\(option)")
            #expect(events.filter { $0.type == .openingBalance }.count == 1, "\(option)")
            #expect(events.contains { $0.type == .buy } == expected.hasBuy, "\(option)")
            if option == .deposit {
                #expect(events.contains { $0.type == .interest })
            }
            #expect(AccountBalanceEngine.balanceAt(
                events: events,
                kind: account.kind,
                on: date,
                marketMeta: account.marketMeta
            ) == expected.balance, "\(option)")
            #expect(try context.fetch(FetchDescriptor<Card>()).isEmpty)
            #expect(try context.fetch(FetchDescriptor<Credit>()).isEmpty)
            #expect(try context.fetch(FetchDescriptor<Investment>()).isEmpty)
        }
    }

    @Test
    func creditCardWithoutBankKeepsCreditIdentity() throws {
        let input = FinanceProductCreationInput(
            option: .card, name: "Credit card", currency: "RUB", amount: 20_000,
            cardType: .credit, bank: .other, creditLimit: 100_000
        )
        let command = try FinanceProductCreationCommandResolver.resolve(input)
        #expect(command.productType == .creditCard)
        #expect(command.metadata.card?.bank == nil)
        #expect(command.metadata.card?.creditLimit == 100_000)

        let container = try AppMigrationPlan.makeInMemoryContainer()
        let id = try AccountProductFactory(modelContext: container.mainContext).create(command)
        let account = try #require(container.mainContext.fetch(FetchDescriptor<Account>()).first { $0.id == id })
        #expect(account.kind == .debitCard)
        #expect(account.productType == .creditCard)
    }

    @Test(arguments: [true, false])
    func genericInvestmentUsesTickerToChooseMarketOrManual(hasTicker: Bool) throws {
        let input = FinanceProductCreationInput(
            option: .investment, name: "Investment", currency: "USD", amount: 250,
            marketSymbol: hasTicker ? "VOO" : nil,
            marketQuantity: hasTicker ? 2 : nil,
            marketUnitPrice: hasTicker ? 50 : nil
        )
        let command = try FinanceProductCreationCommandResolver.resolve(input)
        #expect(command.productType == (hasTicker ? .genericMarketInvestment : .otherManualAsset))
        #expect((command.initialMarketPurchase != nil) == hasTicker)
        #expect((command.metadata.market != nil) == hasTicker)
        #expect((command.metadata.manualAsset != nil) == !hasTicker)
    }

    @Test(arguments: [FinanceAddAccountProductOption.stocks, .crypto])
    func explicitMarketPresetRejectsMissingTicker(option: FinanceAddAccountProductOption) {
        #expect(throws: FinanceProductCreationCommandError.missingMarketPosition) {
            try FinanceProductCreationCommandResolver.resolve(.init(
                option: option, name: "Missing ticker", currency: "USD", amount: 100
            ))
        }
    }

    @Test("Membership flag survives resolver and factory for every product shape", arguments: [
        FinanceAddAccountProductOption.card,
        .account, .deposit, .credit, .debt, .investment, .house, .stocks, .business, .crypto, .other
    ])
    func excludedProductStaysExcluded(option: FinanceAddAccountProductOption) throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let (base, _) = makeInput(for: option, date: date)
        let input = FinanceProductCreationInput(
            option: base.option,
            name: base.name,
            currency: base.currency,
            amount: base.amount,
            includeInTotal: false,
            groupID: base.groupID,
            cardType: base.cardType,
            bank: base.bank,
            cardLast4: base.cardLast4,
            creditLimit: base.creditLimit,
            depositMeta: base.depositMeta,
            loanMeta: base.loanMeta,
            debtDirection: base.debtDirection,
            marketSymbol: base.marketSymbol,
            marketQuantity: base.marketQuantity,
            marketUnitPrice: base.marketUnitPrice,
            note: base.note,
            date: base.date
        )

        let command = try FinanceProductCreationCommandResolver.resolve(input)
        #expect(command.includeInTotal == false)

        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let id = try AccountProductFactory(modelContext: context).create(command)
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first { $0.id == id })
        #expect(account.includeInTotal == false)
        #expect(account.participates(on: date) == false)
    }
}
