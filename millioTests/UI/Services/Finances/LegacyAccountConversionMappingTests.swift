import Foundation
import SwiftData
import Testing
@testable import millio

/// Маппинг легаси-счёта в план создания core-двойника (Track C). Знаковый вклад ДОЛЖЕН совпадать
/// с `FinanceTotalsService.getAccountAmount`, иначе «Общий баланс» после конвертации разойдётся.
@Suite("LegacyAccountConversion mapping (Track C)")
@MainActor
struct LegacyAccountConversionMappingTests {

    private func makeStore() throws -> (ModelContainer, ModelContext, LegacyConversionRegistry) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let defaults = UserDefaults(suiteName: "legacy-product-evidence-\(UUID().uuidString)")!
        return (container, container.mainContext, LegacyConversionRegistry(defaults: defaults))
    }

    private func insertAmbiguousHouseTwin(in context: ModelContext) -> (Account, Investment) {
        let account = Account(name: "Legacy house", kind: .manualAsset, currency: "RUB")
        account.manualAssetMeta = AccountsCoreAdditionBridge.manualAssetMeta()
        let legacy = Investment(
            name: "Legacy house",
            investmentType: .positive,
            category: .house,
            amount: 10_000_000
        )
        context.insert(account)
        context.insert(legacy)
        return (account, legacy)
    }

    // MARK: - Card

    @Test
    func debitCardMapsToDebitCardWithNetWorth() {
        let card = Card(name: "ОГ", cardNumber: "1234", cardType: .debit, balance: 150_000)
        let plan = LegacyAccountConversion.plan(for: card)
        #expect(plan.productType == .debitCard)
        #expect(plan.openingBalance == Decimal(150_000))
        #expect(plan.currency == "RUB")
    }

    @Test
    func creditCardPreservesAvailableBalanceAndLimit() {
        // Кредитная карта: netWorth = −(лимит − доступно) = −(100000 − 30000) = −70000.
        let card = Card(name: "CC", cardNumber: "1", cardType: .credit, balance: 30_000, creditLimit: 100_000)
        let plan = LegacyAccountConversion.plan(for: card)
        #expect(plan.productType == .creditCard)
        #expect(plan.openingBalance == Decimal(30_000))
        #expect(plan.metadata.card?.creditLimit == 100_000)
        #expect(AccountTotalsContribution.signedValue(
            rawBalance: plan.openingBalance,
            kind: .debitCard,
            creditLimit: plan.metadata.card?.creditLimit
        ) == -70_000)
    }

    @Test
    func excludedCardContributesZero() {
        let card = Card(name: "X", cardNumber: "1", cardType: .debit, balance: 150_000, includeInTotal: false)
        let plan = LegacyAccountConversion.plan(for: card)
        #expect(plan.openingBalance == 0) // netWorthAmount == 0 при includeInTotal == false
    }

    // MARK: - Credit

    @Test
    func creditMapsToLoanMagnitude() {
        let credit = Credit(
            name: "Ипотека", amount: 500_000, interestRate: 9.5, monthlyPayment: 5_000,
            startDate: Date(), termMonths: 12, currency: "RUB"
        )
        let plan = LegacyAccountConversion.plan(for: credit)
        #expect(plan.productType == .loan)
        // opening = магнитуда remainingAmount (движок C инвертирует → баланс −500000 = −remainingAmount).
        #expect(plan.openingBalance == Decimal(500_000))
    }

    // MARK: - Investment

    @Test
    func positiveInvestmentMapsToManualAsset() {
        let inv = Investment(name: "Квартира", investmentType: .positive, category: .house, amount: 20_000_000)
        let plan = LegacyAccountConversion.plan(for: inv, currency: "RUB")
        #expect(plan.productType == .realEstate)
        #expect(plan.openingBalance == Decimal(20_000_000))
    }

    @Test
    func negativeInvestmentIsNegative() {
        let inv = Investment(name: "Минус", investmentType: .negative, category: .other, amount: 5_000)
        let plan = LegacyAccountConversion.plan(for: inv, currency: "RUB")
        #expect(plan.openingBalance == Decimal(-5_000))
    }

    @Test
    func excludedInvestmentContributesZero() {
        let inv = Investment(name: "Excl", investmentType: .positive, category: .other, amount: 5_000, includeInTotal: false)
        let plan = LegacyAccountConversion.plan(for: inv, currency: "RUB")
        #expect(plan.openingBalance == 0)
    }

    @Test
    func invalidMarketEvidenceKeepsMarketIntentForFactoryRejection() {
        let inv = Investment(name: "AAPL", investmentType: .positive, category: .stocks, amount: 45_000)
        let plan = LegacyAccountConversion.plan(for: inv, currency: "USD")
        #expect(plan.productType == .marketStock)
        #expect(plan.initialMarketPurchase == nil)
        #expect(plan.currency == "USD")
    }

    @Test
    func validMarketSyntheticBuyPreservesLegacyAmount() {
        let inv = Investment(name: "AAPL", investmentType: .positive, category: .stocks, amount: 45_000)
        inv.marketSymbol = "AAPL"
        inv.marketQuantity = 100
        let plan = LegacyAccountConversion.plan(for: inv, currency: "USD")
        #expect(plan.productType == .marketStock)
        #expect(plan.initialMarketPurchase?.quantity == 100)
        #expect(plan.initialMarketPurchase?.unitPrice == 450)
        #expect((plan.initialMarketPurchase?.quantity ?? 0) * (plan.initialMarketPurchase?.unitPrice ?? 0) == 45_000)
    }

    // MARK: - Persisted legacy evidence

    @Test
    func exactRegistryMappingClassifiesAmbiguousTwinAndRetryIsIdempotent() throws {
        let (container, context, registry) = try makeStore()
        let (account, legacy) = insertAmbiguousHouseTwin(in: context)
        registry.record(legacyUniqueID: legacy.investmentUniqueID, coreAccountID: account.id)
        try context.save()

        let evidence = LegacyProductEvidenceCollector.collect(in: context, registry: registry)
        #expect(evidence[account.id]?.productType == .realEstate)
        #expect(try AccountProductIdentityMigrator.migratePersistedAccounts(
            in: container,
            verifiedEvidenceByCoreAccountID: evidence
        ) == 1)

        let retryEvidence = LegacyProductEvidenceCollector.collect(in: context, registry: registry)
        #expect(try AccountProductIdentityMigrator.migratePersistedAccounts(
            in: container,
            verifiedEvidenceByCoreAccountID: retryEvidence
        ) == 0)
        let stored = try ModelContext(container).fetch(FetchDescriptor<Account>()).first
        #expect(stored?.productType == .realEstate)
        #expect(stored?.productMigrationReason == nil)
    }

    @Test(arguments: [false, true])
    func missingOrStaleRegistryMappingFallsBackToUnknown(stale: Bool) throws {
        let (container, context, registry) = try makeStore()
        let (account, legacy) = insertAmbiguousHouseTwin(in: context)
        if stale {
            registry.record(legacyUniqueID: legacy.investmentUniqueID, coreAccountID: UUID())
        }
        try context.save()

        let evidence = LegacyProductEvidenceCollector.collect(in: context, registry: registry)
        #expect(evidence[account.id] == nil)
        #expect(try AccountProductIdentityMigrator.migratePersistedAccounts(
            in: container,
            verifiedEvidenceByCoreAccountID: evidence
        ) == 1)
        let stored = try ModelContext(container).fetch(FetchDescriptor<Account>()).first
        #expect(stored?.productType == .unknownLegacy)
        #expect(stored?.productMigrationReason == ProductMigrationReason.ambiguousManualAsset.rawValue)
    }

    @Test
    func multipleLegacyRowsForOneCoreUUIDAreRejectedAsAmbiguous() throws {
        let (container, context, registry) = try makeStore()
        let (account, first) = insertAmbiguousHouseTwin(in: context)
        let second = Investment(
            name: "Second house",
            investmentType: .positive,
            category: .house,
            amount: 2_000_000
        )
        context.insert(second)
        registry.record(legacyUniqueID: first.investmentUniqueID, coreAccountID: account.id)
        registry.record(legacyUniqueID: second.investmentUniqueID, coreAccountID: account.id)
        try context.save()

        let evidence = LegacyProductEvidenceCollector.collect(in: context, registry: registry)
        #expect(evidence[account.id] == nil)
        _ = try AccountProductIdentityMigrator.migratePersistedAccounts(
            in: container,
            verifiedEvidenceByCoreAccountID: evidence
        )
        let stored = try ModelContext(container).fetch(FetchDescriptor<Account>()).first
        #expect(stored?.productType == .unknownLegacy)
    }
}
