import Foundation
import Testing
@testable import millio

@Suite("Historical portfolio reader cutover")
struct HistoricalPortfolioReaderCutoverTests {
    @Test("emergency default and rollback cannot select the bare numeric historical reader")
    func emergencyDefaultAndRollbackRemainStructured() {
        let defaults = isolatedDefaults()
        #expect(Set([
            HistoricalPortfolioReaderMode.compatibility,
            .shadow,
            .structured
        ]).count == 3)
        #expect(HistoricalPortfolioReaderMode(rawValue: "bareTotalAt") == nil)
        #expect(HistoricalPortfolioReaderConfiguration.current(defaults: defaults).mode == .structured)

        defaults.set(
            HistoricalPortfolioReaderMode.compatibility.rawValue,
            forKey: HistoricalPortfolioReaderConfiguration.userDefaultsKey
        )
        #expect(HistoricalPortfolioReaderConfiguration.current(defaults: defaults).mode == .compatibility)
    }

    @Test("aggregated reader invokes one series producer and never publishes diagnostic subtotal")
    func aggregatedReaderUsesStructuredBundle() throws {
        let source = try sourceFile("millio/UI/Services/Finances/FinanceDynamicsViewModel.swift")
        let start = try #require(source.range(of: "private func historicalAggregatedSeries("))
        let tail = source[start.lowerBound...]
        let end = try #require(tail.range(of: "func buildTimeSeriesData("))
        let section = String(tail[..<end.lowerBound])

        #expect(section.contains("HistoricalPortfolioSeriesProducer("))
        #expect(section.contains("historicalPortfolioSeries = result"))
        #expect(section.contains("guard point.valuation.total != nil else { return [] }"))
        #expect(section.contains("guard let total = point.valuation.total else { return [] }"))
        #expect(!section.contains("diagnosticPartialTotal"))
        #expect(!section.contains("accountsTotalsService.totalAt("))
        #expect(section.contains("point.accountContributions"))
        #expect(section.contains("singleAccountID"))
        #expect(section.contains("unresolvedExternalAccountIDs"))
    }

    @Test("breakdown and currency distribution short-circuit to the same bundle")
    func secondaryProjectionsUseSeriesBundle() throws {
        let source = try sourceFile("millio/UI/Services/Finances/FinanceDynamicsViewModel.swift")
        let currency = try section(
            source,
            from: "func updateCurrencyBreakdown() async",
            to: "private func structuredCurrencyBreakdown("
        )
        let breakdown = try section(
            source,
            from: "func updateDynamicsBreakdown() async",
            to: "private func structuredDynamicsBreakdown("
        )
        #expect(currency.contains("structuredCurrencyBreakdown(from: series)"))
        #expect(currency.contains("return"))
        #expect(breakdown.contains("structuredDynamicsBreakdown(from: series)"))
        #expect(breakdown.contains("return"))
    }

    @Test("dashboard sparkline and delta project the same complete bundle")
    func dashboardUsesSeriesProducerDirectly() throws {
        let source = try sourceFile("millio/UI/Services/Finances/FinanceViewModel.swift")
        let method = try section(
            source,
            from: "func computeDashboardSparkline() async",
            to: "/// Подсчитать сумму группы"
        )

        #expect(method.contains("HistoricalPortfolioSeriesProducer("))
        #expect(method.contains("externalCoverage: legacyHistoricalValuator"))
        #expect(method.contains("valuation.total"))
        #expect(method.contains("values.count == series.points.count"))
        #expect(method.contains("let delta = last - first"))
        #expect(!method.contains("FinanceDynamicsViewModel("))
        #expect(!method.contains("DashboardBalanceHistoryStore"))
        #expect(!method.contains("diagnosticPartialTotal"))
    }

    @Test("overview and secondary projections preserve external contributions")
    func externalContributionsAreNotDroppedByConsumers() throws {
        let source = try sourceFile("millio/UI/Services/Finances/FinanceDynamicsViewModel.swift")
        let overview = try section(
            source,
            from: "func buildOverviewEntries(",
            to: "/// Compatibility API retained"
        )
        let projections = try section(
            source,
            from: "private func structuredCurrencyBreakdown(",
            to: "func updateChartDataAsync(expectedRevision:"
        )

        #expect(overview.contains("HistoricalPortfolioSeriesProducer("))
        #expect(overview.contains("point(nearestTo:"))
        #expect(overview.contains("accountContributions"))
        #expect(!overview.contains("calculateBalanceAtDate("))
        #expect(projections.contains("account.accountUniqueID"))
        #expect(projections.contains("contributionIDs"))
        #expect(projections.contains("structuredAccountDescriptors()"))
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "HistoricalPortfolioReaderCutoverTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }


    private func section(_ source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try #require(source.range(of: startMarker))
        let tail = source[start.lowerBound...]
        let end = try #require(tail.range(of: endMarker))
        return String(tail[..<end.lowerBound])
    }
}
