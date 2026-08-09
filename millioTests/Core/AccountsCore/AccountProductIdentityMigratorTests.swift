import Foundation
import Testing
@testable import millio

@Suite("AccountProductIdentityMigrator")
struct AccountProductIdentityMigratorTests {
    @Test("Deterministic existing-account matrix") @MainActor
    func migrationMatrix() {
        for value in Self.migrationCases {
            let account = value.makeAccount()
            let assignment = AccountProductIdentityMigrator.classify(account)
            #expect(assignment == value.expected, Comment(rawValue: value.testDescription))
        }
    }

    @Test("Migration is idempotent and mutates only product columns")
    @MainActor func migrationIsIdempotentAndNonFinancial() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let archivedAt = createdAt.addingTimeInterval(100)
        let account = Account(
            id: UUID(),
            name: "Ambiguous cash",
            kind: .cash,
            currency: "USD",
            createdAt: createdAt,
            includeInTotal: false,
            order: 9
        )
        account.archivedAt = archivedAt
        account.deletedAt = archivedAt.addingTimeInterval(50)
        account.note = "keep"

        #expect(AccountProductIdentityMigrator.migrate(account))
        #expect(account.productType == .unknownLegacy)
        #expect(account.productMigrationReason == ProductMigrationReason.ambiguousCashKind.rawValue)
        #expect(!AccountProductIdentityMigrator.migrate(account))
        #expect(account.kindRaw == AccountKind.cash.rawValue)
        #expect(account.currency == "USD")
        #expect(account.createdAt == createdAt)
        #expect(account.archivedAt == archivedAt)
        #expect(account.includeInTotal == false)
        #expect(account.note == "keep")
        #expect(account.order == 9)
    }

    @Test("Legacy subtype is accepted only for exact verified core UUID")
    @MainActor func verifiedLegacyMappingRule() {
        let account = Account(name: "House", kind: .manualAsset)
        account.manualAssetMeta = Self.manualMeta()
        let suiteName = "product-evidence-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let registry = LegacyConversionRegistry(defaults: defaults)
        let row = LegacyRow(id: "legacy-row")

        registry.record(legacyUniqueID: row.id, coreAccountID: UUID())
        let stale = VerifiedLegacyProductEvidence.verify(
            row: row,
            identifier: \.id,
            productType: .realEstate,
            coreAccount: account,
            registry: registry
        )
        #expect(stale == nil)

        registry.record(legacyUniqueID: row.id, coreAccountID: account.id)
        let verified = VerifiedLegacyProductEvidence.verify(
            row: row,
            identifier: \.id,
            productType: .realEstate,
            coreAccount: account,
            registry: registry
        )
        #expect(verified != nil)
        #expect(AccountProductIdentityMigrator.classify(account, verifiedLegacyEvidence: verified)
            == .init(productType: .realEstate, reason: nil))
    }

    @Test("Batch migration reports changes once")
    @MainActor func batchMigrationIsIdempotent() {
        let accounts = [
            Account(name: "Cash", kind: .cash),
            Account(name: "Bank", kind: .bankAccount)
        ]
        #expect(AccountProductIdentityMigrator.migrate(accounts) == 2)
        #expect(AccountProductIdentityMigrator.migrate(accounts) == 0)
    }

    @Test("Invalid persisted identity is quarantined deterministically")
    @MainActor func invalidPersistedIdentityIsQuarantined() {
        let account = Account(name: "Bad", kind: .deposit, productType: .cash)
        account.depositMeta = Self.validDeposit()
        #expect(AccountProductIdentityMigrator.migrate(account))
        #expect(account.productType == .unknownLegacy)
        #expect(account.productMigrationReason == ProductMigrationReason.persistedProductContradiction.rawValue)
        #expect(!AccountProductIdentityMigrator.migrate(account))
    }

    @Test("unknownLegacy classification does not change replay")
    @MainActor func unknownLegacyRemainsReplayCompatible() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let account = Account(name: "Legacy", kind: .cash, createdAt: date)
        let opening = AccountEvent(account: account, date: date, type: .openingBalance, amount: 100)
        let expense = AccountEvent(
            account: account,
            date: date.addingTimeInterval(60),
            type: .expense,
            amount: 25
        )
        let events = [opening, expense]
        let before = AccountBalanceEngine.balanceAt(
            events: events,
            kind: account.kind,
            on: date.addingTimeInterval(120)
        )

        #expect(AccountProductIdentityMigrator.migrate(account))
        let after = AccountBalanceEngine.balanceAt(
            events: events,
            kind: account.kind,
            on: date.addingTimeInterval(120)
        )

        #expect(account.productType == .unknownLegacy)
        #expect(ProductDefinitionCatalog.isReplayCompatibleLegacy(
            kindRaw: account.kindRaw,
            metadata: AccountProductMetadata(account: account)
        ))
        #expect(before == 75)
        #expect(after == before)
    }

    struct MigrationCase: CustomTestStringConvertible {
        let name: String
        let makeAccount: @MainActor () -> Account
        let expected: ProductIdentityMigrationAssignment
        var testDescription: String { name }
    }

    private struct LegacyRow {
        let id: String
    }

    private static let migrationCases: [MigrationCase] = [
        .init(name: "cash ambiguous", makeAccount: { Account(name: "a", kind: .cash) }, expected: Self.unknown(.ambiguousCashKind)),
        .init(name: "cash credit", makeAccount: {
            let account = Account(name: "a", kind: .cash)
            account.cardMeta = Self.cardMeta(creditLimit: 10)
            return account
        }, expected: Self.resolved(.creditCard)),
        .init(name: "cash invalid limit", makeAccount: {
            let account = Account(name: "a", kind: .cash)
            account.cardMeta = Self.cardMeta(creditLimit: 0)
            return account
        }, expected: Self.unknown(.nonPositiveCreditLimit)),
        .init(name: "debit", makeAccount: { Account(name: "a", kind: .debitCard) }, expected: Self.resolved(.debitCard)),
        .init(name: "debit with credit limit", makeAccount: {
            let account = Account(name: "a", kind: .debitCard)
            account.cardMeta = Self.cardMeta(creditLimit: 10)
            return account
        }, expected: Self.resolved(.creditCard)),
        .init(name: "bank", makeAccount: { Account(name: "a", kind: .bankAccount) }, expected: Self.resolved(.bankAccount)),
        .init(name: "deposit", makeAccount: {
            let account = Account(name: "a", kind: .deposit)
            account.depositMeta = Self.validDeposit()
            return account
        }, expected: Self.resolved(.deposit)),
        .init(name: "deposit missing meta", makeAccount: { Account(name: "a", kind: .deposit) }, expected: Self.unknown(.invalidDepositMeta)),
        .init(name: "loan", makeAccount: {
            let account = Account(name: "a", kind: .loan)
            account.loanMeta = Self.validLoan()
            return account
        }, expected: Self.resolved(.loan)),
        .init(name: "receivable", makeAccount: {
            let account = Account(name: "a", kind: .debt)
            account.debtMeta = Self.debtMeta(.owedToMe)
            return account
        }, expected: Self.resolved(.receivable)),
        .init(name: "payable", makeAccount: {
            let account = Account(name: "a", kind: .debt)
            account.debtMeta = Self.debtMeta(.owedByMe)
            return account
        }, expected: Self.resolved(.payable)),
        .init(name: "market stock", makeAccount: { Self.market(.stock, symbol: "AAPL") }, expected: Self.resolved(.marketStock)),
        .init(name: "market crypto", makeAccount: { Self.market(.crypto, symbol: "BTC") }, expected: Self.resolved(.marketCrypto)),
        .init(name: "market bond", makeAccount: { Self.market(.bond, symbol: "BOND") }, expected: Self.resolved(.marketBond)),
        .init(name: "market metal", makeAccount: { Self.market(.metal, symbol: "XAU") }, expected: Self.resolved(.marketMetal)),
        .init(name: "market invalid", makeAccount: { Self.market(.stock, symbol: " ") }, expected: Self.unknown(.invalidMarketMeta)),
        .init(name: "manual ambiguous", makeAccount: {
            let account = Account(name: "a", kind: .manualAsset)
            account.manualAssetMeta = Self.manualMeta()
            return account
        }, expected: Self.unknown(.ambiguousManualAsset)),
        .init(name: "multiple meta", makeAccount: {
            let account = Account(name: "a", kind: .deposit)
            account.depositMeta = Self.validDeposit()
            account.cardMeta = Self.cardMeta()
            return account
        }, expected: Self.unknown(.multipleMetaObjects)),
        .init(name: "kind/meta contradiction", makeAccount: {
            let account = Account(name: "a", kind: .cash)
            account.loanMeta = Self.validLoan()
            return account
        }, expected: Self.unknown(.kindMetaContradiction))
    ]

    private static func resolved(_ productType: AccountProductType) -> ProductIdentityMigrationAssignment {
        .init(productType: productType, reason: nil)
    }

    private static func unknown(_ reason: ProductMigrationReason) -> ProductIdentityMigrationAssignment {
        .init(productType: .unknownLegacy, reason: reason)
    }

    private static func market(_ assetClass: MarketAssetClass, symbol: String) -> Account {
        let account = Account(name: "market", kind: .marketInvestment)
        account.marketMeta = .init(symbol: symbol, assetClass: assetClass)
        return account
    }

    private static func validDeposit() -> DepositMeta {
        DepositMeta(
            rate: 10,
            capitalization: .monthly,
            termEnd: nil,
            payoutDay: nil,
            allowsTopUp: true,
            allowsEarlyClose: true,
            earlyClosePenalty: nil,
            remindEnd: false,
            autoRollover: false
        )
    }

    private static func validLoan() -> LoanMeta {
        LoanMeta(
            principal: 100,
            rate: 5,
            monthlyPayment: nil,
            paymentDay: nil,
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
