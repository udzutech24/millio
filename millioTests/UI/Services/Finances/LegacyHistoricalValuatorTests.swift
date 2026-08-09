import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct LegacyHistoricalValuatorTests {
    @Test("standalone replay preserves the Dynamics compatibility result")
    func dynamicsDelegationParity() async throws {
        let fixture = try makeCardFixture(currency: "RUB")
        let rates = NilLegacyRateService()
        let finance = FinanceViewModel(
            modelContext: fixture.context,
            currencyService: rates,
            skipInitialLoad: true
        )
        let dynamics = FinanceDynamicsViewModel(
            modelContext: fixture.context,
            financeViewModel: finance,
            currencyService: rates
        )
        dynamics.state.displayCurrency = "RUB"
        dynamics.loadData()
        let standalone = LegacyHistoricalValuator(
            modelContext: fixture.context,
            currencyService: rates
        )

        let delegated = await dynamics.calculateBalanceAtDate(
            accounts: [fixture.account],
            date: fixture.targetDate,
            accountCardIDs: [fixture.card.cardUniqueID],
            debtAsNegative: true
        )
        let direct = await standalone.balance(
            accounts: [fixture.account],
            at: fixture.targetDate,
            displayCurrency: "RUB",
            debtAsNegative: true
        )

        #expect(delegated == direct)
        #expect(direct == 75)
    }

    @Test("structured external coverage resolves same-currency legacy replay")
    func structuredCoverageReturnsExplicitContribution() async throws {
        let fixture = try makeCardFixture(currency: "RUB")
        let valuator = LegacyHistoricalValuator(
            modelContext: fixture.context,
            currencyService: NilLegacyRateService()
        )
        let query = query(
            at: fixture.targetDate,
            displayCurrency: "RUB",
            opaqueID: fixture.account.accountUniqueID
        )
        let context = try #require(HistoricalValuationTimeContext(ianaTimeZoneID: "Europe/Istanbul"))

        let contribution = try #require(
            await valuator.contributions(at: fixture.targetDate, query: query, timeContext: context)?.first
        )

        #expect(contribution.opaqueAccountID == fixture.account.accountUniqueID)
        #expect(contribution.value == 75)
        #expect(contribution.state == .complete)
        #expect(contribution.unresolved.isEmpty)
    }

    @Test("structured coverage fails closed when closed-day FX evidence is missing")
    func structuredCoverageDoesNotPublishNativeAmountAsDisplayCurrency() async throws {
        let fixture = try makeCardFixture(currency: "USD")
        let valuator = LegacyHistoricalValuator(
            modelContext: fixture.context,
            currencyService: NilLegacyRateService()
        )
        let query = query(
            at: fixture.targetDate,
            displayCurrency: "RUB",
            opaqueID: fixture.account.accountUniqueID
        )
        let context = try #require(HistoricalValuationTimeContext(ianaTimeZoneID: "Europe/Istanbul"))

        let contribution = try #require(
            await valuator.contributions(at: fixture.targetDate, query: query, timeContext: context)?.first
        )
        let compatibility = await valuator.balance(
            accounts: [fixture.account],
            at: fixture.targetDate,
            displayCurrency: "RUB",
            debtAsNegative: true
        )

        #expect(contribution.value == nil)
        #expect(contribution.state == .incomplete)
        #expect(contribution.unresolved.contains { $0.dimension == .fxRate })
        #expect(compatibility == 75, "Native fallback remains quarantined to compatibility/shadow")
    }

    @Test("verified predecessor and core successor never participate on the same boundary side")
    func mappedBoundarySplitsLogicalParticipation() async throws {
        let fixture = try makeCardFixture(currency: "RUB")
        let boundary = fixture.targetDate.addingTimeInterval(86_400)
        fixture.card.archivedAt = boundary
        let core = try AccountsCoreService(modelContext: fixture.context).createAccount(
            name: "Core successor",
            kind: .bankAccount,
            currency: "RUB",
            openingBalance: 75,
            date: boundary
        )
        LegacyConversionRegistry.shared.record(
            legacyUniqueID: fixture.account.accountID,
            coreAccountID: core.id
        )
        defer { LegacyConversionRegistry.shared.remove(legacyUniqueID: fixture.account.accountID) }
        try fixture.context.save()
        let valuator = LegacyHistoricalValuator(
            modelContext: fixture.context,
            currencyService: NilLegacyRateService()
        )
        let context = try #require(HistoricalValuationTimeContext(ianaTimeZoneID: "Europe/Istanbul"))
        let beforeQuery = scopedQuery(
            at: fixture.targetDate,
            displayCurrency: "RUB",
            opaqueID: fixture.account.accountUniqueID,
            coreID: core.id
        )
        let afterDate = boundary.addingTimeInterval(3_600)
        let afterQuery = scopedQuery(
            at: afterDate,
            displayCurrency: "RUB",
            opaqueID: fixture.account.accountUniqueID,
            coreID: core.id
        )

        let replacedBefore = await valuator.replacedCoreAccountIDs(
            at: fixture.targetDate, query: beforeQuery, timeContext: context
        )
        let excludedBefore = await valuator.nonParticipatingAccountIDs(
            at: fixture.targetDate, query: beforeQuery, timeContext: context
        )
        let replacedAfter = await valuator.replacedCoreAccountIDs(
            at: afterDate, query: afterQuery, timeContext: context
        )
        let excludedAfter = await valuator.nonParticipatingAccountIDs(
            at: afterDate, query: afterQuery, timeContext: context
        )

        #expect(replacedBefore == [core.id])
        #expect(excludedBefore.isEmpty)
        #expect(replacedAfter.isEmpty)
        #expect(excludedAfter == [fixture.account.accountUniqueID])
    }

    private func makeCardFixture(
        currency: String
    ) throws -> (container: ModelContainer, context: ModelContext, card: Card, account: FinanceAccount, targetDate: Date) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let transactionDate = createdAt.addingTimeInterval(3_600)
        let targetDate = transactionDate.addingTimeInterval(3_600)
        let card = Card(
            name: "Legacy card",
            cardNumber: "4242",
            cardType: .debit,
            currency: currency,
            balance: 75
        )
        card.initialBalance = 100
        card.hasInitialBalance = true
        card.createdAt = createdAt
        card.updatedAt = targetDate.addingTimeInterval(86_400)
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.createdAt = createdAt
        let transaction = CashflowTransaction(
            transactionType: .expense,
            amount: 25,
            currency: currency,
            transactionDate: transactionDate,
            cardID: card.cardUniqueID
        )
        context.insert(card)
        context.insert(account)
        context.insert(transaction)
        try context.save()
        return (container, context, card, account, targetDate)
    }

    private func query(
        at date: Date,
        displayCurrency: String,
        opaqueID: String
    ) -> HistoricalPortfolioSeriesQuery {
        HistoricalPortfolioSeriesQuery(
            period: DateInterval(start: date, end: date),
            timeZoneID: "Europe/Istanbul",
            displayCurrency: displayCurrency,
            samplingPolicy: .exact([date]),
            unresolvedExternalAccountIDs: [opaqueID]
        )
    }

    private func scopedQuery(
        at date: Date,
        displayCurrency: String,
        opaqueID: String,
        coreID: UUID
    ) -> HistoricalPortfolioSeriesQuery {
        HistoricalPortfolioSeriesQuery(
            period: DateInterval(start: date, end: date),
            timeZoneID: "Europe/Istanbul",
            displayCurrency: displayCurrency,
            accountScope: .accountIDs([coreID]),
            samplingPolicy: .exact([date]),
            unresolvedExternalAccountIDs: [opaqueID]
        )
    }
}

@MainActor
private final class NilLegacyRateService: CurrencyRateServiceProtocol {
    func getRate(from: String, to: String) async -> Double? { nil }
    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? { nil }
    func convert(amount: Double, from: String, to: String) async -> Double? { nil }
    func forceRefreshRates() async {}
}
