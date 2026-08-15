import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Finance Dynamics historical revision commit")
@MainActor
struct FinanceDynamicsRevisionCommitTests {
    private static var retainedContainers: [ModelContainer] = []

    @Test("stale historical completion cannot overwrite the current chart, hero or bundle")
    func staleCompletionCannotOverwriteCurrentProjection() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let context = container.mainContext
        let dates = (
            start: Date(timeIntervalSince1970: 1_754_496_000),
            end: Date(timeIntervalSince1970: 1_755_100_800)
        )
        let stale = makeSeries(start: 10, end: 20, dates: dates, revision: 1)
        let current = makeSeries(start: 100, end: 130, dates: dates, revision: 2)
        let loader = DelayedHistoricalSeriesLoader(stale: stale, current: current)
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
            historicalSeriesLoader: { query in
                await loader.load(query)
            }
        )

        let staleTask = Task { @MainActor in
            await viewModel.updateChartDataAsync()
        }
        await loader.waitUntilStaleRequestIsSuspended()

        await viewModel.updateChartDataAsync()
        #expect(viewModel.state.chartData.map(\.value) == [100, 130])
        #expect(viewModel.state.currentBalance == 130)
        #expect(viewModel.state.periodDelta.absolute == 30)
        #expect(viewModel.historicalPortfolioSeries?.generatedAt == current.generatedAt)

        await loader.resumeStaleRequest()
        await staleTask.value

        #expect(viewModel.state.chartData.map(\.value) == [100, 130])
        #expect(viewModel.state.currentBalance == 130)
        #expect(viewModel.state.periodDelta.absolute == 30)
        #expect(viewModel.historicalPortfolioSeries?.generatedAt == current.generatedAt)
    }

    private func makeSeries(
        start: Decimal,
        end: Decimal,
        dates: (start: Date, end: Date),
        revision: Int
    ) -> HistoricalPortfolioSeriesResult {
        let query = HistoricalPortfolioSeriesQuery(
            period: DateInterval(start: dates.start, end: dates.end),
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB",
            samplingPolicy: .exact([dates.start, dates.end])
        )
        let points = [
            makePoint(value: start, date: dates.start, dayKey: "2026-08-03", revision: revision),
            makePoint(value: end, date: dates.end, dayKey: "2026-08-10", revision: revision)
        ]
        return HistoricalPortfolioSeriesResult(
            query: query,
            points: points,
            generatedAt: Date(timeIntervalSince1970: TimeInterval(revision))
        )
    }

    private func makePoint(
        value: Decimal,
        date: Date,
        dayKey: String,
        revision: Int
    ) -> HistoricalPortfolioSeriesPoint {
        let result = HistoricalValuationResult(
            key: HistoricalValuationKey(
                schemaVersion: 7,
                scopeID: "revision-test",
                dayKey: dayKey,
                timeZoneID: "Europe/Istanbul",
                displayCurrency: "RUB",
                valuationPolicyVersion: 1,
                inputRevision: HistoricalValuationInputRevision(
                    accountSet: UInt64(revision),
                    financial: UInt64(revision),
                    events: UInt64(revision),
                    evidence: UInt64(revision)
                )
            ),
            diagnosticPartialTotal: value,
            finality: .closed,
            quality: .exact,
            expectedContributionCount: 0,
            resolvedContributionCount: 0,
            unresolved: [],
            resolutions: [],
            generatedAt: date
        )
        return HistoricalPortfolioSeriesPoint(
            id: HistoricalPortfolioPointID(result.key),
            date: date,
            valuation: result,
            accountContributions: []
        )
    }
}

private actor DelayedHistoricalSeriesLoader {
    private let stale: HistoricalPortfolioSeriesResult
    private let current: HistoricalPortfolioSeriesResult
    private var requestCount = 0
    private var staleContinuation: CheckedContinuation<HistoricalPortfolioSeriesResult, Never>?

    init(stale: HistoricalPortfolioSeriesResult, current: HistoricalPortfolioSeriesResult) {
        self.stale = stale
        self.current = current
    }

    func load(_ query: HistoricalPortfolioSeriesQuery) async -> HistoricalPortfolioSeriesResult {
        _ = query
        requestCount += 1
        if requestCount == 1 {
            return await withCheckedContinuation { continuation in
                staleContinuation = continuation
            }
        }
        return current
    }

    func waitUntilStaleRequestIsSuspended() async {
        while staleContinuation == nil {
            await Task.yield()
        }
    }

    func resumeStaleRequest() {
        staleContinuation?.resume(returning: stale)
        staleContinuation = nil
    }
}
