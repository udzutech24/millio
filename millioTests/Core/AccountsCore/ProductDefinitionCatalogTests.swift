import Foundation
import Testing
@testable import millio

@Suite("ProductDefinitionCatalog")
struct ProductDefinitionCatalogTests {
    @Test("Every canonical product has one narrow definition")
    func completeDefinitionMatrix() {
        #expect(ProductDefinitionCatalog.definitions.count == AccountProductType.allCases.count)
        for productType in AccountProductType.allCases {
            let definition = ProductDefinitionCatalog.definition(for: productType)
            #expect(definition.productType == productType)
            #expect(definition.allowedEventTypes.contains { $0 == .openingBalance })
            #expect(definition.totalPolicy == .accountParticipation)
            if productType == .unknownLegacy {
                #expect(definition.canonicalKind == nil)
            } else {
                #expect(definition.canonicalKind != nil)
            }
        }
        #expect(ProductDefinitionCatalog.definition(for: .marketStock).valuationPolicy == .marketQuote)
        #expect(ProductDefinitionCatalog.definition(for: .cash).valuationPolicy == .nativeBalance)
        #expect(ProductDefinitionCatalog.definition(for: .unknownLegacy).valuationPolicy == .preserveExistingKind)
        #expect(ProductDefinitionCatalog.definition(for: .unknownLegacy).capabilities == [.archive])
        #expect(!ProductDefinitionCatalog.definition(for: .unknownLegacy)
            .capabilities.contains(.productSpecificDetails))
    }

    @Test("Canonical product/kind/meta matrix is accepted")
    func validMatrix() throws {
        let manual = AccountProductMetadata(manualAsset: Self.manualMeta())
        let market: [(AccountProductType, MarketAssetClass)] = [
            (.marketStock, .stock), (.marketCrypto, .crypto), (.marketBond, .bond), (.marketMetal, .metal)
        ]

        try ProductDefinitionCatalog.validateNewProduct(.cash, kind: .cash, metadata: .init())
        try ProductDefinitionCatalog.validateNewProduct(.debitCard, kind: .debitCard, metadata: .init(card: Self.cardMeta()))
        try ProductDefinitionCatalog.validateNewProduct(
            .creditCard,
            kind: .debitCard,
            metadata: .init(card: Self.cardMeta(creditLimit: 100))
        )
        try ProductDefinitionCatalog.validateNewProduct(.bankAccount, kind: .bankAccount, metadata: .init())
        try ProductDefinitionCatalog.validateNewProduct(
            .deposit,
            kind: .deposit,
            metadata: .init(deposit: Self.validDeposit())
        )
        try ProductDefinitionCatalog.validateNewProduct(
            .loan,
            kind: .loan,
            metadata: .init(loan: Self.validLoan())
        )
        try ProductDefinitionCatalog.validateNewProduct(
            .receivable,
            kind: .debt,
            metadata: .init(debt: Self.debtMeta(.owedToMe))
        )
        try ProductDefinitionCatalog.validateNewProduct(
            .payable,
            kind: .debt,
            metadata: .init(debt: Self.debtMeta(.owedByMe))
        )
        for (productType, assetClass) in market {
            try ProductDefinitionCatalog.validateNewProduct(
                productType,
                kind: .marketInvestment,
                metadata: .init(market: .init(symbol: "TEST", assetClass: assetClass))
            )
        }
        try ProductDefinitionCatalog.validateNewProduct(
            .genericMarketInvestment,
            kind: .marketInvestment,
            metadata: .init(market: .init(symbol: "ANY", assetClass: .stock))
        )
        for productType in [AccountProductType.realEstate, .business, .vehicle, .otherManualAsset] {
            try ProductDefinitionCatalog.validateNewProduct(productType, kind: .manualAsset, metadata: manual)
        }
    }

    @Test("Contradictory combinations are rejected")
    func rejectsInvalidCombinations() {
        let cases = [
            InvalidCase(.creditCard, .debitCard, .init(card: Self.cardMeta(creditLimit: 0))),
            InvalidCase(.debitCard, .debitCard, .init(card: Self.cardMeta(creditLimit: 100))),
            InvalidCase(.deposit, .deposit, .init()),
            InvalidCase(.loan, .loan, .init(loan: Self.validLoan(), market: .init(symbol: "X", assetClass: .stock))),
            InvalidCase(.receivable, .debt, .init(debt: Self.debtMeta(.owedByMe))),
            InvalidCase(.marketStock, .marketInvestment, .init(market: .init(symbol: "", assetClass: .stock))),
            InvalidCase(.marketCrypto, .marketInvestment, .init(market: .init(symbol: "BTC", assetClass: .stock)))
        ]
        for value in cases {
            #expect(throws: (any Error).self, Comment(rawValue: value.testDescription)) {
                try ProductDefinitionCatalog.validateNewProduct(value.productType, kind: value.kind, metadata: value.metadata)
            }
        }
    }

    @Test("unknownLegacy cannot be a new product but valid ambiguous rows remain replay-compatible")
    func unknownLegacyBoundary() {
        #expect(throws: ProductCatalogValidationError.unknownLegacyCannotBeCreated) {
            try ProductDefinitionCatalog.validateNewProduct(.unknownLegacy, kind: .cash, metadata: .init())
        }
        #expect(ProductDefinitionCatalog.isReplayCompatibleLegacy(kindRaw: AccountKind.cash.rawValue, metadata: .init()))
        #expect(ProductDefinitionCatalog.isReplayCompatibleLegacy(
            kindRaw: AccountKind.manualAsset.rawValue,
            metadata: .init(manualAsset: Self.manualMeta())
        ))
        #expect(!ProductDefinitionCatalog.isReplayCompatibleLegacy(
            kindRaw: AccountKind.deposit.rawValue,
            metadata: .init()
        ))
        let unknownMarket = AccountProductMetadata(
            market: MarketMeta(symbol: "AAPL", assetClass: .stock)
        )
        #expect(ProductDefinitionCatalog.isReplayCompatibleLegacy(
            kindRaw: AccountKind.marketInvestment.rawValue,
            metadata: unknownMarket
        ))
        #expect(ProductDefinitionCatalog.valuationPolicy(
            for: .unknownLegacy,
            storedKind: .marketInvestment
        ) == .marketQuote)
        #expect(ProductDefinitionCatalog.valuationPolicy(
            for: .unknownLegacy,
            storedKind: .cash
        ) == .nativeBalance)
        #expect(throws: (any Error).self) {
            try ProductDefinitionCatalog.validateStoredIdentity(
                .unknownLegacy,
                kindRaw: AccountKind.deposit.rawValue,
                metadata: .init(),
                migrationReason: ProductMigrationReason.invalidDepositMeta.rawValue
            )
        }
    }

    struct InvalidCase: CustomTestStringConvertible {
        let productType: AccountProductType
        let kind: AccountKind
        let metadata: AccountProductMetadata

        init(_ productType: AccountProductType, _ kind: AccountKind, _ metadata: AccountProductMetadata) {
            self.productType = productType
            self.kind = kind
            self.metadata = metadata
        }

        var testDescription: String { productType.rawValue }
    }

    private static func validDeposit() -> DepositMeta {
        DepositMeta(
            rate: 10,
            capitalization: .monthly,
            termEnd: nil,
            payoutDay: nil,
            allowsTopUp: true,
            allowsEarlyClose: true,
            earlyClosePenalty: 0.5,
            remindEnd: false,
            autoRollover: false
        )
    }

    private static func validLoan() -> LoanMeta {
        LoanMeta(
            principal: 100_000,
            rate: 10,
            monthlyPayment: 10_000,
            paymentDay: 1,
            termEnd: nil,
            scheduleType: .annuity,
            insurance: nil
        )
    }

    private static func cardMeta(creditLimit: Decimal? = nil) -> CardMeta {
        CardMeta(
            bank: nil,
            last4: nil,
            creditLimit: creditLimit,
            statementDay: nil,
            dueDay: nil,
            minPayment: nil,
            graceDays: nil,
            overdraftLimit: nil
        )
    }

    private static func debtMeta(_ direction: DebtDirection) -> DebtMeta {
        DebtMeta(direction: direction, counterparty: nil, dueDate: nil, rate: nil)
    }

    private static func manualMeta() -> ManualAssetMeta {
        ManualAssetMeta(revalReminderMonths: nil, depreciationRatePerYear: nil, linkedLoanID: nil)
    }
}
