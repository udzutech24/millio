import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct CashflowHistoricalPortfolioCutoverTests {
    @Test("structured Cashflow snapshot uses the portfolio producer directly")
    func structuredSnapshotUsesProducer() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        _ = try AccountsCoreService(modelContext: context).createAccount(
            name: "Core cash",
            kind: .bankAccount,
            currency: "RUB",
            openingBalance: 100_000,
            date: createdAt
        )
        let viewModel = CashflowViewModel(
            modelContext: context,
            historicalReaderMode: .structured
        )
        viewModel.state.displayCurrency = "RUB"

        let snapshot = await viewModel.resolveAssetsSnapshotFromFinance(
            startDate: createdAt.addingTimeInterval(-86_400),
            endDate: createdAt.addingTimeInterval(86_400)
        )

        #expect(snapshot?.start == 0)
        #expect(snapshot?.end == 100_000)
        #expect(viewModel.historicalAssetsSeries?.points.count == 2)
        #expect(viewModel.historicalAssetsShadowDeltaBucket == nil)
    }

    @Test("unresolved legacy coverage fails closed in structured mode")
    func unresolvedLegacyFailsClosed() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let group = FinanceGroup(name: "Legacy", colorHex: "#FFFFFF")
        let legacy = FinanceAccount(accountType: .card, accountID: "unmigrated-card")
        legacy.group = group
        group.accounts = [legacy]
        context.insert(group)
        context.insert(legacy)
        try context.save()
        let viewModel = CashflowViewModel(
            modelContext: context,
            historicalReaderMode: .structured
        )
        viewModel.state.displayCurrency = "RUB"

        let snapshot = await viewModel.resolveAssetsSnapshotFromFinance(
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_086_400)
        )

        #expect(snapshot == nil)
        #expect(viewModel.historicalAssetsSeries?.points.allSatisfy { $0.valuation.total == nil } == true)
    }

    @Test("legacy Finance calculation remains isolated to shadow mode")
    func sourceBoundaryIsExplicit() throws {
        let source = try sourceFile("millio/UI/Services/Cashflow/CashflowViewModel+Categories.swift")
        let directStart = try #require(source.range(of: "func resolveAssetsSnapshotFromFinance"))
        let compatibilityStart = try #require(source.range(of: "private func resolveCompatibilityAssetsSnapshot"))
        let direct = String(source[directStart.lowerBound..<compatibilityStart.lowerBound])
        let compatibility = String(source[compatibilityStart.lowerBound...])

        #expect(direct.contains("HistoricalPortfolioSeriesProducer("))
        #expect(direct.contains("externalCoverage: legacyValuator"))
        #expect(direct.contains("guard historicalReaderMode == .shadow"))
        #expect(!direct.contains("FinanceViewModel("))
        #expect(!direct.contains("FinanceDynamicsViewModel("))
        #expect(compatibility.contains("LegacyHistoricalValuator"))
        #expect(compatibility.contains("totalAt("), "Bare core total is allowed only in explicit shadow")
        #expect(!compatibility.contains("FinanceDynamicsViewModel("))
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
}
