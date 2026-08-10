import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Finance Dynamics endpoint and group semantics")
@MainActor
struct FinanceDynamicsEndpointSemanticsTests {
    private static var retainedContainers: [ModelContainer] = []

    @Test("core-only and ungrouped rows preserve endpoint totals")
    func coreOnlyAndUngroupedRowsReconstructBothEndpoints() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let context = container.mainContext
        let group = AccountGroup(name: "Core only")
        let createdMidPeriod = Account(name: "Created later", kind: .cash)
        createdMidPeriod.group = group
        let ungrouped = Account(name: "Ungrouped", kind: .cash)
        context.insert(group)
        context.insert(createdMidPeriod)
        context.insert(ungrouped)
        try context.save()

        let dates = (
            start: Date(timeIntervalSince1970: 1_754_496_000),
            end: Date(timeIntervalSince1970: 1_755_100_800)
        )
        let series = makeSeries(
            dates: dates,
            start: [(ungrouped.id.uuidString, 10)],
            end: [(createdMidPeriod.id.uuidString, 100), (ungrouped.id.uuidString, 60)]
        )
        let financeViewModel = FinanceViewModel(
            modelContext: context,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: financeViewModel,
            currencyService: MockCurrencyRateService(),
            historicalReaderMode: .structured,
            historicalSeriesLoader: { _ in series }
        )

        await viewModel.updateChartDataAsync()
        viewModel.handle(.setViewMode(.accounts))
        await viewModel.updateDynamicsBreakdown()
        let accountRows = viewModel.state.dynamicsBreakdown
        let createdRow = try #require(accountRows.first { $0.id == createdMidPeriod.id.uuidString })
        #expect(createdRow.startValue == 0)
        #expect(createdRow.endValue == 100)
        #expect(createdRow.deltaPercent == nil)
        #expect(accountRows.reduce(0) { $0 + $1.startValue } == 10)
        #expect(accountRows.reduce(0) { $0 + $1.endValue } == 160)

        viewModel.handle(.setViewMode(.groups))
        await viewModel.updateDynamicsBreakdown()
        let groupRows = viewModel.state.dynamicsBreakdown
        let coreGroupRow = try #require(groupRows.first { $0.id == group.id.uuidString })
        #expect(coreGroupRow.name == "Core only")
        #expect(coreGroupRow.startValue == 0)
        #expect(coreGroupRow.endValue == 100)
        #expect(groupRows.filter { $0.id == "ungrouped" }.count == 1)
        #expect(groupRows.reduce(0) { $0 + $1.startValue } == 10)
        #expect(groupRows.reduce(0) { $0 + $1.endValue } == 160)
    }

    @Test("hero and breakdown follow renderable chart endpoints")
    func incompleteRequestedBoundariesDoNotZeroVisibleData() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let context = container.mainContext
        let group = AccountGroup(name: "Visible group")
        let account = Account(name: "Visible account", kind: .cash)
        account.group = group
        context.insert(group)
        context.insert(account)
        try context.save()

        let dates = [0, 1, 2, 3].map {
            Date(timeIntervalSince1970: 1_754_496_000 + Double($0 * 86_400))
        }
        let query = HistoricalPortfolioSeriesQuery(
            period: DateInterval(start: dates[0], end: dates[3]),
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB",
            samplingPolicy: .exact(dates)
        )
        let series = HistoricalPortfolioSeriesResult(
            query: query,
            points: [
                makeIncompletePoint(date: dates[0], dayKey: "2026-08-03"),
                makePoint(
                    date: dates[1],
                    dayKey: "2026-08-04",
                    contributions: [(account.id.uuidString, 100)]
                ),
                makePoint(
                    date: dates[2],
                    dayKey: "2026-08-05",
                    contributions: [(account.id.uuidString, 160)]
                ),
                makeIncompletePoint(date: dates[3], dayKey: "2026-08-06")
            ],
            generatedAt: dates[3]
        )
        let financeViewModel = FinanceViewModel(
            modelContext: context,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: financeViewModel,
            currencyService: MockCurrencyRateService(),
            historicalReaderMode: .structured,
            historicalSeriesLoader: { _ in series }
        )

        await viewModel.updateChartDataAsync()
        #expect(viewModel.state.chartData.map(\.value) == [100, 160])
        #expect(viewModel.state.currentBalance == 160)
        #expect(viewModel.state.periodDelta.absolute == 60)
        #expect(viewModel.state.periodDelta.percent == 60)
        #expect(viewModel.state.currencyConversionWarning == nil)

        viewModel.handle(.setViewMode(.accounts))
        await viewModel.updateDynamicsBreakdown()
        let row = try #require(viewModel.state.dynamicsBreakdown.first)
        #expect(row.id == account.id.uuidString)
        #expect(row.startValue == 100)
        #expect(row.endValue == 160)

        viewModel.handle(.setViewMode(.groups))
        await viewModel.updateDynamicsBreakdown()
        let groupRow = try #require(viewModel.state.dynamicsBreakdown.first)
        #expect(groupRow.id == group.id.uuidString)
        #expect(groupRow.startValue == 100)
        #expect(groupRow.endValue == 160)
    }

    private func makeSeries(
        dates: (start: Date, end: Date),
        start: [(String, Decimal)],
        end: [(String, Decimal)]
    ) -> HistoricalPortfolioSeriesResult {
        let query = HistoricalPortfolioSeriesQuery(
            period: DateInterval(start: dates.start, end: dates.end),
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB",
            samplingPolicy: .exact([dates.start, dates.end])
        )
        return HistoricalPortfolioSeriesResult(
            query: query,
            points: [
                makePoint(date: dates.start, dayKey: "2026-08-03", contributions: start),
                makePoint(date: dates.end, dayKey: "2026-08-10", contributions: end)
            ],
            generatedAt: dates.end
        )
    }

    private func makePoint(
        date: Date,
        dayKey: String,
        contributions: [(String, Decimal)]
    ) -> HistoricalPortfolioSeriesPoint {
        let total = contributions.reduce(Decimal.zero) { $0 + $1.1 }
        let key = HistoricalValuationKey(
            schemaVersion: 7,
            scopeID: "endpoint-semantics",
            dayKey: dayKey,
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB",
            valuationPolicyVersion: 1,
            inputRevision: .init(accountSet: 1, financial: 1, events: 1, evidence: 1)
        )
        let valuation = HistoricalValuationResult(
            key: key,
            diagnosticPartialTotal: total,
            finality: .closed,
            quality: .exact,
            expectedContributionCount: contributions.count,
            resolvedContributionCount: contributions.count,
            unresolved: [],
            resolutions: [],
            generatedAt: date
        )
        return HistoricalPortfolioSeriesPoint(
            id: HistoricalPortfolioPointID(key),
            date: date,
            valuation: valuation,
            accountContributions: contributions.map {
                HistoricalPortfolioAccountContribution(
                    opaqueAccountID: $0.0,
                    value: $0.1,
                    state: .complete,
                    quality: .exact,
                    unresolved: []
                )
            }
        )
    }

    private func makeIncompletePoint(
        date: Date,
        dayKey: String
    ) -> HistoricalPortfolioSeriesPoint {
        let key = HistoricalValuationKey(
            schemaVersion: 7,
            scopeID: "endpoint-semantics",
            dayKey: dayKey,
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB",
            valuationPolicyVersion: 1,
            inputRevision: .init(accountSet: 1, financial: 1, events: 1, evidence: 1)
        )
        let valuation = HistoricalValuationResult(
            key: key,
            diagnosticPartialTotal: 0,
            finality: .closed,
            quality: .unavailable,
            expectedContributionCount: 1,
            resolvedContributionCount: 0,
            unresolved: [
                .init(
                    opaqueAccountID: "missing",
                    dimension: .marketPrice,
                    reasonCode: "previous_close_ineligible"
                )
            ],
            resolutions: [],
            generatedAt: date
        )
        return HistoricalPortfolioSeriesPoint(
            id: HistoricalPortfolioPointID(key),
            date: date,
            valuation: valuation,
            accountContributions: []
        )
    }
}
