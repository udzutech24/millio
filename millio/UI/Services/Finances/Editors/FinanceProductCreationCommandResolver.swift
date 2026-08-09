import Foundation

/// Pure production boundary between the visible add-account preset and the atomic product
/// factory. Keeping this mapping outside SwiftUI makes the complete persisted tuple testable.
struct FinanceProductCreationInput {
    let option: FinanceAddAccountProductOption
    let name: String
    let currency: String
    let amount: Decimal
    let includeInTotal: Bool
    let groupID: UUID?
    let cardType: CardType?
    let bank: Bank?
    let cardLast4: String?
    let creditLimit: Decimal?
    let depositMeta: DepositMeta?
    let loanMeta: LoanMeta?
    let debtDirection: DebtDirection?
    let marketSymbol: String?
    let marketQuantity: Decimal?
    let marketUnitPrice: Decimal?
    let note: String?
    let date: Date

    init(
        option: FinanceAddAccountProductOption,
        name: String,
        currency: String,
        amount: Decimal,
        includeInTotal: Bool = true,
        groupID: UUID? = nil,
        cardType: CardType? = nil,
        bank: Bank? = nil,
        cardLast4: String? = nil,
        creditLimit: Decimal? = nil,
        depositMeta: DepositMeta? = nil,
        loanMeta: LoanMeta? = nil,
        debtDirection: DebtDirection? = nil,
        marketSymbol: String? = nil,
        marketQuantity: Decimal? = nil,
        marketUnitPrice: Decimal? = nil,
        note: String? = nil,
        date: Date = Date()
    ) {
        self.option = option
        self.name = name
        self.currency = currency
        self.amount = amount
        self.includeInTotal = includeInTotal
        self.groupID = groupID
        self.cardType = cardType
        self.bank = bank
        self.cardLast4 = cardLast4
        self.creditLimit = creditLimit
        self.depositMeta = depositMeta
        self.loanMeta = loanMeta
        self.debtDirection = debtDirection
        self.marketSymbol = marketSymbol
        self.marketQuantity = marketQuantity
        self.marketUnitPrice = marketUnitPrice
        self.note = note
        self.date = date
    }
}

enum FinanceProductCreationCommandError: Error, Equatable {
    case missingCardType
    case missingCreditLimit
    case missingDepositMeta
    case missingLoanMeta
    case missingDebtDirection
    case missingMarketPosition
}

enum FinanceProductCreationCommandResolver {
    static func resolve(_ input: FinanceProductCreationInput) throws -> CreateProductCommand {
        let common = { (
            productType: AccountProductType,
            openingBalance: Decimal,
            metadata: AccountProductMetadata,
            purchase: InitialMarketPurchase?
        ) in
            CreateProductCommand(
                productType: productType,
                name: input.name,
                currency: input.currency,
                openingBalance: openingBalance,
                includeInTotal: input.includeInTotal,
                groupID: input.groupID,
                metadata: metadata,
                note: input.note,
                date: input.date,
                initialMarketPurchase: purchase
            )
        }

        switch input.option {
        case .card:
            guard let cardType = input.cardType else {
                throw FinanceProductCreationCommandError.missingCardType
            }
            let productType: AccountProductType = cardType == .credit ? .creditCard : .debitCard
            if cardType == .credit {
                guard let limit = input.creditLimit, limit > 0 else {
                    throw FinanceProductCreationCommandError.missingCreditLimit
                }
            }
            let meta = CardMeta(
                bank: input.bank == nil || input.bank == .other ? nil : input.bank?.rawValue,
                last4: input.cardLast4?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                creditLimit: cardType == .credit ? input.creditLimit : nil
            )
            return common(productType, input.amount, .init(card: meta), nil)

        case .account:
            return common(.bankAccount, input.amount, .init(), nil)

        case .deposit:
            guard let meta = input.depositMeta else {
                throw FinanceProductCreationCommandError.missingDepositMeta
            }
            return common(.deposit, input.amount, .init(deposit: meta), nil)

        case .credit:
            guard let meta = input.loanMeta else {
                throw FinanceProductCreationCommandError.missingLoanMeta
            }
            return common(.loan, magnitude(input.amount), .init(loan: meta), nil)

        case .debt:
            guard let direction = input.debtDirection else {
                throw FinanceProductCreationCommandError.missingDebtDirection
            }
            let amountMagnitude = magnitude(input.amount)
            let signed = direction == .owedToMe ? amountMagnitude : -amountMagnitude
            let productType: AccountProductType = direction == .owedToMe ? .receivable : .payable
            return common(
                productType,
                signed,
                .init(debt: AccountsCoreAdditionBridge.debtMeta(direction: direction)),
                nil
            )

        case .investment:
            if normalizedSymbol(input.marketSymbol) != nil {
                return try marketCommand(input, productType: .genericMarketInvestment, assetClass: .stock)
            }
            return common(
                .otherManualAsset,
                input.amount,
                .init(manualAsset: AccountsCoreAdditionBridge.manualAssetMeta()),
                nil
            )

        case .stocks:
            return try marketCommand(input, productType: .marketStock, assetClass: .stock)

        case .crypto:
            return try marketCommand(input, productType: .marketCrypto, assetClass: .crypto)

        case .house:
            return common(
                .realEstate,
                input.amount,
                .init(manualAsset: AccountsCoreAdditionBridge.manualAssetMeta()),
                nil
            )

        case .business:
            return common(
                .business,
                input.amount,
                .init(manualAsset: AccountsCoreAdditionBridge.manualAssetMeta()),
                nil
            )

        case .other:
            return common(
                .otherManualAsset,
                input.amount,
                .init(manualAsset: AccountsCoreAdditionBridge.manualAssetMeta()),
                nil
            )
        }
    }

    private static func marketCommand(
        _ input: FinanceProductCreationInput,
        productType: AccountProductType,
        assetClass: MarketAssetClass
    ) throws -> CreateProductCommand {
        guard let symbol = normalizedSymbol(input.marketSymbol),
              let quantity = input.marketQuantity,
              let unitPrice = input.marketUnitPrice else {
            throw FinanceProductCreationCommandError.missingMarketPosition
        }
        return CreateProductCommand(
            productType: productType,
            name: input.name,
            currency: input.currency,
            openingBalance: 0,
            includeInTotal: input.includeInTotal,
            groupID: input.groupID,
            metadata: .init(market: MarketMeta(symbol: symbol, assetClass: assetClass)),
            note: input.note,
            date: input.date,
            initialMarketPurchase: .init(quantity: quantity, unitPrice: unitPrice)
        )
    }

    private static func normalizedSymbol(_ raw: String?) -> String? {
        raw?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.uppercased()
    }

    private static func magnitude(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
