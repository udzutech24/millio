import Foundation

enum AccountMetaKind: String, CaseIterable, Hashable {
    case card
    case deposit
    case loan
    case debt
    case market
    case manualAsset
}

enum ProductOpeningStrategy: String, Hashable {
    case openingBalance
    case openingBalanceAndMarketBuy
    case openingBalanceAndDepositSchedule
}

/// Identifiers only: the actual participation/sign math stays in `AccountTotalsContribution`.
enum ProductTotalPolicyIdentifier: String, Hashable {
    case accountParticipation
}

/// Identifiers only: valuation and fallback formulas stay in the unified valuation resolver.
enum ProductValuationPolicyIdentifier: String, Hashable {
    case nativeBalance
    case marketQuote
    /// Migration-only routing: resolve from the validated stored `AccountKind`; never guess.
    case preserveExistingKind
}

enum AccountProductCapability: String, Hashable {
    case cashflow
    case transfers
    case creditLimit
    case depositTerms
    case loanTerms
    case debtDirection
    case marketQuotes
    case manualRevaluation
    case archive
    case productSpecificDetails
}

/// Pure metadata view used by catalog validation and migration. It deliberately contains no
/// balances, signs, replay logic, FX or market-price formulas.
struct AccountProductMetadata: Equatable {
    var card: CardMeta?
    var deposit: DepositMeta?
    var loan: LoanMeta?
    var debt: DebtMeta?
    var market: MarketMeta?
    var manualAsset: ManualAssetMeta?

    init(
        card: CardMeta? = nil,
        deposit: DepositMeta? = nil,
        loan: LoanMeta? = nil,
        debt: DebtMeta? = nil,
        market: MarketMeta? = nil,
        manualAsset: ManualAssetMeta? = nil
    ) {
        self.card = card
        self.deposit = deposit
        self.loan = loan
        self.debt = debt
        self.market = market
        self.manualAsset = manualAsset
    }

    init(account: Account) {
        self.init(
            card: account.cardMeta,
            deposit: account.depositMeta,
            loan: account.loanMeta,
            debt: account.debtMeta,
            market: account.marketMeta,
            manualAsset: account.manualAssetMeta
        )
    }

    var presentKinds: Set<AccountMetaKind> {
        var result: Set<AccountMetaKind> = []
        if card != nil { result.insert(.card) }
        if deposit != nil { result.insert(.deposit) }
        if loan != nil { result.insert(.loan) }
        if debt != nil { result.insert(.debt) }
        if market != nil { result.insert(.market) }
        if manualAsset != nil { result.insert(.manualAsset) }
        return result
    }
}

struct ProductDefinition {
    let productType: AccountProductType
    /// `nil` is reserved for `unknownLegacy`, which preserves its validated existing kind.
    let canonicalKind: AccountKind?
    /// Older rows may preserve a technically different cash-like discriminator. New writers must
    /// always use `canonicalKind`; this set exists only for the explicit migration matrix.
    let legacyCompatibleKinds: [AccountKind]
    let requiredMeta: Set<AccountMetaKind>
    let allowedMeta: Set<AccountMetaKind>
    let openingStrategy: ProductOpeningStrategy
    let allowedEventTypes: [AccountEventType]
    let capabilities: Set<AccountProductCapability>
    let totalPolicy: ProductTotalPolicyIdentifier
    let valuationPolicy: ProductValuationPolicyIdentifier
}

enum ProductCatalogValidationError: Error, Equatable {
    case unknownLegacyCannotBeCreated
    case invalidKindRaw(String)
    case kindMismatch(expected: AccountKind, actual: AccountKind)
    case missingRequiredMeta(AccountMetaKind)
    case forbiddenMeta(AccountMetaKind)
    case invalidCreditLimit
    case invalidDepositMeta
    case invalidLoanMeta
    case debtDirectionMismatch
    case invalidMarketMeta
    case marketAssetClassMismatch
    case missingUnknownLegacyReason
    case unexpectedMigrationReason
}

/// Single narrow mapping for product identity, technical kind and structural capabilities.
/// Financial calculation rules remain in the balance/totals/valuation components.
enum ProductDefinitionCatalog {
    static let definitions: [AccountProductType: ProductDefinition] = {
        let cashEvents: [AccountEventType] = [
            .openingBalance, .income, .expense, .transferOut, .transferIn, .adjustment, .redenomination
        ]
        let manualEvents: [AccountEventType] = [.openingBalance, .revaluation, .adjustment, .redenomination]
        let marketEvents: [AccountEventType] = [
            .openingBalance, .buy, .sell, .dividend, .fee, .adjustment, .redenomination
        ]
        let basicCapabilities: Set<AccountProductCapability> = [.archive, .productSpecificDetails]

        func definition(
            _ productType: AccountProductType,
            _ kind: AccountKind?,
            required: Set<AccountMetaKind> = [],
            allowed: Set<AccountMetaKind> = [],
            opening: ProductOpeningStrategy = .openingBalance,
            events: [AccountEventType],
            capabilities: Set<AccountProductCapability> = []
        ) -> ProductDefinition {
            ProductDefinition(
                productType: productType,
                canonicalKind: kind,
                legacyCompatibleKinds: productType == .creditCard ? [.cash, .debitCard] : [],
                requiredMeta: required,
                allowedMeta: allowed,
                openingStrategy: opening,
                allowedEventTypes: events,
                capabilities: productType == .unknownLegacy
                    ? [.archive]
                    : basicCapabilities.union(capabilities),
                totalPolicy: .accountParticipation,
                valuationPolicy: productType == .unknownLegacy
                    ? .preserveExistingKind
                    : (kind == .marketInvestment ? .marketQuote : .nativeBalance)
            )
        }

        return [
            .cash: definition(.cash, .cash, events: cashEvents, capabilities: [.cashflow, .transfers]),
            .debitCard: definition(.debitCard, .debitCard, allowed: [.card], events: cashEvents, capabilities: [.cashflow, .transfers]),
            .creditCard: definition(.creditCard, .debitCard, required: [.card], allowed: [.card], events: cashEvents, capabilities: [.cashflow, .transfers, .creditLimit]),
            .bankAccount: definition(.bankAccount, .bankAccount, allowed: [.card], events: cashEvents, capabilities: [.cashflow, .transfers]),
            .deposit: definition(.deposit, .deposit, required: [.deposit], allowed: [.deposit], opening: .openingBalanceAndDepositSchedule, events: cashEvents + [.interest, .rollover], capabilities: [.depositTerms, .transfers]),
            .loan: definition(.loan, .loan, required: [.loan], allowed: [.loan], events: [.openingBalance, .income, .expense, .extraPayment, .fee, .adjustment, .redenomination], capabilities: [.loanTerms]),
            .receivable: definition(.receivable, .debt, required: [.debt], allowed: [.debt], events: cashEvents + [.extraPayment], capabilities: [.debtDirection]),
            .payable: definition(.payable, .debt, required: [.debt], allowed: [.debt], events: cashEvents + [.extraPayment], capabilities: [.debtDirection]),
            .marketStock: definition(.marketStock, .marketInvestment, required: [.market], allowed: [.market], opening: .openingBalanceAndMarketBuy, events: marketEvents, capabilities: [.marketQuotes]),
            .marketCrypto: definition(.marketCrypto, .marketInvestment, required: [.market], allowed: [.market], opening: .openingBalanceAndMarketBuy, events: marketEvents, capabilities: [.marketQuotes]),
            .marketBond: definition(.marketBond, .marketInvestment, required: [.market], allowed: [.market], opening: .openingBalanceAndMarketBuy, events: marketEvents, capabilities: [.marketQuotes]),
            .marketMetal: definition(.marketMetal, .marketInvestment, required: [.market], allowed: [.market], opening: .openingBalanceAndMarketBuy, events: marketEvents, capabilities: [.marketQuotes]),
            .genericMarketInvestment: definition(.genericMarketInvestment, .marketInvestment, required: [.market], allowed: [.market], opening: .openingBalanceAndMarketBuy, events: marketEvents, capabilities: [.marketQuotes]),
            // All ManualAssetMeta fields are optional. SwiftData canonically round-trips the
            // all-nil value as nil, so product identity (not an empty metadata shell) owns subtype.
            .realEstate: definition(.realEstate, .manualAsset, allowed: [.manualAsset], events: manualEvents, capabilities: [.manualRevaluation]),
            .business: definition(.business, .manualAsset, allowed: [.manualAsset], events: manualEvents, capabilities: [.manualRevaluation]),
            .vehicle: definition(.vehicle, .manualAsset, allowed: [.manualAsset], events: manualEvents, capabilities: [.manualRevaluation]),
            .otherManualAsset: definition(.otherManualAsset, .manualAsset, allowed: [.manualAsset], events: manualEvents, capabilities: [.manualRevaluation]),
            .unknownLegacy: definition(.unknownLegacy, nil, allowed: Set(AccountMetaKind.allCases), events: Array(AccountEventType.allCatalogCases), capabilities: [.archive])
        ]
    }()

    static func definition(for productType: AccountProductType) -> ProductDefinition {
        // The dictionary is constructed from the exhaustive enum above. A missing entry is a
        // programmer error and must fail loudly during tests/development, never become `.cash`.
        guard let definition = definitions[productType] else {
            preconditionFailure("Missing product definition: \(productType.rawValue)")
        }
        return definition
    }

    static func validateNewProduct(
        _ productType: AccountProductType,
        kind: AccountKind,
        metadata: AccountProductMetadata
    ) throws {
        guard productType != .unknownLegacy else {
            throw ProductCatalogValidationError.unknownLegacyCannotBeCreated
        }
        try validateResolved(productType, kind: kind, metadata: metadata)
    }

    static func validateStoredIdentity(
        _ productType: AccountProductType,
        kindRaw: String,
        metadata: AccountProductMetadata,
        migrationReason: String?
    ) throws {
        if productType == .unknownLegacy {
            guard let migrationReason,
                  ProductMigrationReason(rawValue: migrationReason) != nil else {
                throw ProductCatalogValidationError.missingUnknownLegacyReason
            }
            guard let kind = AccountKind(rawValue: kindRaw) else {
                throw ProductCatalogValidationError.invalidKindRaw(kindRaw)
            }
            try validateReplayCompatibleLegacy(kind: kind, metadata: metadata)
            return
        }
        guard migrationReason == nil else {
            throw ProductCatalogValidationError.unexpectedMigrationReason
        }
        guard let kind = AccountKind(rawValue: kindRaw) else {
            throw ProductCatalogValidationError.invalidKindRaw(kindRaw)
        }
        try validateResolved(productType, kind: kind, metadata: metadata, allowLegacyKind: true)
    }

    static func isReplayCompatibleLegacy(kindRaw: String, metadata: AccountProductMetadata) -> Bool {
        guard let kind = AccountKind(rawValue: kindRaw) else { return false }
        return (try? validateReplayCompatibleLegacy(kind: kind, metadata: metadata)) != nil
    }

    static func isEvent(_ eventType: AccountEventType, allowedFor productType: AccountProductType) -> Bool {
        definition(for: productType).allowedEventTypes.contains { $0.rawValue == eventType.rawValue }
    }

    static func hasCapability(_ capability: AccountProductCapability, for productType: AccountProductType) -> Bool {
        definition(for: productType).capabilities.contains(capability)
    }

    static func valuationPolicy(
        for productType: AccountProductType,
        storedKind: AccountKind
    ) -> ProductValuationPolicyIdentifier {
        let policy = definition(for: productType).valuationPolicy
        guard policy == .preserveExistingKind else { return policy }
        return storedKind == .marketInvestment ? .marketQuote : .nativeBalance
    }

    private static func validateResolved(
        _ productType: AccountProductType,
        kind: AccountKind,
        metadata: AccountProductMetadata,
        allowLegacyKind: Bool = false
    ) throws {
        let definition = definition(for: productType)
        if let canonicalKind = definition.canonicalKind,
           canonicalKind != kind,
           !(allowLegacyKind && definition.legacyCompatibleKinds.contains(kind)) {
            throw ProductCatalogValidationError.kindMismatch(expected: canonicalKind, actual: kind)
        }
        try validateMetaShape(metadata, required: definition.requiredMeta, allowed: definition.allowedMeta)

        switch productType {
        case .debitCard:
            guard metadata.card?.creditLimit == nil else {
                throw ProductCatalogValidationError.invalidCreditLimit
            }
        case .creditCard:
            guard let limit = metadata.card?.creditLimit, limit > 0 else {
                throw ProductCatalogValidationError.invalidCreditLimit
            }
        case .deposit:
            guard let deposit = metadata.deposit,
                  deposit.rate >= 0,
                  deposit.earlyClosePenalty.map({ $0 >= 0 && $0 <= 1 }) ?? true else {
                throw ProductCatalogValidationError.invalidDepositMeta
            }
        case .loan:
            guard let loan = metadata.loan,
                  loan.principal > 0,
                  loan.rate >= 0,
                  loan.monthlyPayment.map({ $0 > 0 }) ?? true else {
                throw ProductCatalogValidationError.invalidLoanMeta
            }
        case .receivable:
            guard metadata.debt?.direction == .owedToMe else {
                throw ProductCatalogValidationError.debtDirectionMismatch
            }
        case .payable:
            guard metadata.debt?.direction == .owedByMe else {
                throw ProductCatalogValidationError.debtDirectionMismatch
            }
        case .marketStock:
            try validateMarket(metadata.market, expectedClass: .stock)
        case .marketCrypto:
            try validateMarket(metadata.market, expectedClass: .crypto)
        case .marketBond:
            try validateMarket(metadata.market, expectedClass: .bond)
        case .marketMetal:
            try validateMarket(metadata.market, expectedClass: .metal)
        case .genericMarketInvestment:
            try validateMarket(metadata.market, expectedClass: nil)
        case .cash, .bankAccount, .realEstate, .business, .vehicle, .otherManualAsset:
            break
        case .unknownLegacy:
            throw ProductCatalogValidationError.unknownLegacyCannotBeCreated
        }
    }

    /// `unknownLegacy` keeps the existing replay engine only when kind/meta themselves are safe.
    /// Ambiguous subtype is allowed; contradictory or malformed engine metadata is not.
    private static func validateReplayCompatibleLegacy(
        kind: AccountKind,
        metadata: AccountProductMetadata
    ) throws {
        let allowed: Set<AccountMetaKind>
        switch kind {
        case .cash, .debitCard, .bankAccount: allowed = [.card]
        case .deposit: allowed = [.deposit]
        case .loan: allowed = [.loan]
        case .debt: allowed = [.debt]
        case .marketInvestment: allowed = [.market]
        case .manualAsset: allowed = [.manualAsset]
        }
        try validateMetaShape(metadata, required: [], allowed: allowed)

        switch kind {
        case .deposit:
            guard metadata.deposit != nil else { throw ProductCatalogValidationError.invalidDepositMeta }
        case .loan:
            guard metadata.loan != nil else { throw ProductCatalogValidationError.invalidLoanMeta }
        case .debt:
            guard metadata.debt != nil else { throw ProductCatalogValidationError.debtDirectionMismatch }
        case .marketInvestment:
            guard let market = metadata.market else { throw ProductCatalogValidationError.invalidMarketMeta }
            try validateMarket(market, expectedClass: nil)
        case .cash, .debitCard, .bankAccount, .manualAsset:
            break
        }
    }

    private static func validateMetaShape(
        _ metadata: AccountProductMetadata,
        required: Set<AccountMetaKind>,
        allowed: Set<AccountMetaKind>
    ) throws {
        if let missing = required.subtracting(metadata.presentKinds).first {
            throw ProductCatalogValidationError.missingRequiredMeta(missing)
        }
        if let forbidden = metadata.presentKinds.subtracting(allowed).first {
            throw ProductCatalogValidationError.forbiddenMeta(forbidden)
        }
    }

    private static func validateMarket(
        _ market: MarketMeta?,
        expectedClass: MarketAssetClass?
    ) throws {
        guard let market, !market.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProductCatalogValidationError.invalidMarketMeta
        }
        if let expectedClass, market.assetClass != expectedClass {
            throw ProductCatalogValidationError.marketAssetClassMismatch
        }
    }
}

private extension AccountEventType {
    static let allCatalogCases: [AccountEventType] = [
        .openingBalance, .income, .expense, .transferOut, .transferIn, .buy, .sell, .interest,
        .dividend, .fee, .extraPayment, .rollover, .revaluation, .adjustment, .redenomination
    ]
}
