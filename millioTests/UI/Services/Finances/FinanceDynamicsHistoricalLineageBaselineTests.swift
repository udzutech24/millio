import Foundation
import Testing
@testable import millio

/// Phase 0 executable source-contract baseline for AC-B5. These tests intentionally describe the
/// current divergent call graph and wrap the desired single-producer assertions in `withKnownIssue`.
/// This prevents today's broken lineage from becoming a green acceptance contract while still making
/// every missing cutover explicit and executable. Remove each known issue when Phase 4 owns the path.
@Suite("Phase 0: historical consumer lineage baseline")
struct FinanceDynamicsHistoricalLineageBaselineTests {

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

    private func section(in source: String, from startMarker: String, to endMarker: String) throws -> String {
        let start = try #require(source.range(of: startMarker))
        let tail = source[start.lowerBound...]
        let end = try #require(tail.range(of: endMarker))
        return String(tail[..<end.lowerBound])
    }

    @Test("aggregated vs by-account/single-account use different historical series paths")
    func lineModesHaveDivergentSeriesProducers() throws {
        let source = try sourceFile("millio/UI/Services/Finances/FinanceDynamicsViewModel.swift")
        let dispatch = try section(
            in: source,
            from: "func updateChartDataAsync(expectedRevision:",
            to: "func buildTimeSeriesData("
        )
        let diverges = dispatch.contains("aggregatedDynamicsSeries(")
            && dispatch.contains("case .byAccounts:")
            && dispatch.contains("case .singleAccount")
            && dispatch.contains("buildTimeSeriesData(")

        #expect(diverges)
        withKnownIssue("AC-B5: all line modes must project one HistoricalPortfolioSeriesResult.") {
            #expect(!diverges)
        }
    }

    @Test("scrub/header recompute balances outside the chart series")
    func scrubAndHeaderRecomputeHistoricalValues() throws {
        let source = try sourceFile("millio/UI/Services/Finances/FinanceDynamicsViewModel.swift")
        let header = try section(
            in: source,
            from: "private func updateCurrentBalanceAndDelta(for selectedDate:",
            to: "/// Получить счета для расчета"
        )
        let actionDispatch = try section(
            in: source,
            from: "case .selectDateOnChart(let date):",
            to: "case .setDynamicsMode(let mode):"
        )
        let recomputes = actionDispatch.contains("updateCurrentBalanceAndDelta")
            && header.contains("calculateBalanceAtDate(")
            && header.contains("accountsTotalsService.totalAt(")

        #expect(recomputes)
        withKnownIssue("AC-B5: scrub/header must select the existing point, not replay totals.") {
            #expect(!recomputes)
        }
    }

    @Test("account/group breakdown is rebuilt independently from chart points")
    func breakdownHasIndependentReplayPath() throws {
        let source = try sourceFile("millio/UI/Services/Finances/FinanceDynamicsViewModel.swift")
        let breakdown = try section(
            in: source,
            from: "func updateDynamicsBreakdown() async",
            to: "func updateChartDataAsync(expectedRevision:"
        )
        let recomputes = breakdown.contains("legacyAccountDynamicsRows(")
            && breakdown.contains("coreAccountDynamicsItems(")

        #expect(recomputes)
        withKnownIssue("AC-B5: breakdown must aggregate per-account contributions from the series bundle.") {
            #expect(!recomputes)
        }
    }

    @Test("currency breakdown evaluates core accounts at Date(), not selected endpoint")
    func currencyBreakdownUsesLiveCoreDate() throws {
        let source = try sourceFile("millio/UI/Services/Finances/FinanceDynamicsViewModel.swift")
        let currency = try section(
            in: source,
            from: "func updateCurrencyBreakdown() async",
            to: "private func legacyAccountsByUniqueID()"
        )
        let mixesEndpoints = currency.contains("let endDate = getPeriodDates().end")
            && currency.contains("on: Date(), in: coreAccount.currency")

        #expect(mixesEndpoints)
        withKnownIssue("AC-B5: currency distribution must group the selected historical point's contributions.") {
            #expect(!mixesEndpoints)
        }
    }

    @Test("distribution cards consume independently assembled breakdown arrays")
    func distributionCardsDoNotShareHistoricalPointContributions() throws {
        let source = try sourceFile("millio/UI/Services/Finances/FinanceDynamicsView.swift")
        let separateModels = source.contains("items: viewModel.state.dynamicsBreakdown")
            && source.contains("items: viewModel.state.currencyBreakdown")
            && source.contains("from: viewModel.state.dynamicsBreakdown")

        #expect(separateModels)
        withKnownIssue("AC-B5: distributions and total card must project one selected series point.") {
            #expect(!separateModels)
        }
    }

    @Test("Cashflow snapshot calls the structured producer without temporary view models")
    func cashflowSnapshotUsesPortfolioProducerDirectly() throws {
        let source = try sourceFile("millio/UI/Services/Cashflow/CashflowViewModel+Categories.swift")
        let method = try section(
            in: source,
            from: "func resolveAssetsSnapshotFromFinance(startDate:",
            to: "func cardBalanceSnapshot(for cardID:"
        )
        #expect(method.contains("HistoricalPortfolioSeriesProducer("))
        #expect(method.contains("externalCoverage: legacyValuator"))
        #expect(!method.contains("FinanceViewModel("))
        #expect(!method.contains("FinanceDynamicsViewModel("))
    }
}
