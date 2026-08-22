import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct FinanceDynamicsSnapshotStoreTests {
    private final class InMemorySnapshotStore: FinanceDynamicsSnapshotStoreProtocol {
        private var snapshots: [String: FinanceDynamicsSnapshot] = [:]

        func load(scopeID: String) -> FinanceDynamicsSnapshot? {
            snapshots[scopeID]
        }

        func save(_ snapshot: FinanceDynamicsSnapshot, scopeID: String) {
            snapshots[scopeID] = snapshot
        }
    }

    private func makeSnapshot(rateSnapshotRevision: String? = nil) -> FinanceDynamicsSnapshot {
        FinanceDynamicsSnapshot(
            displayCurrency: "RUB",
            periodRawValue: DynamicsPeriod.week.rawValue,
            periodStartDate: Date(timeIntervalSince1970: 1_000),
            periodEndDate: Date(timeIntervalSince1970: 2_000),
            chartData: [.init(date: Date(timeIntervalSince1970: 1_000), value: 150, label: "Total")],
            currentBalance: 150,
            periodDeltaAbsolute: 50,
            periodDeltaPercent: 50,
            dynamicsBreakdown: [
                .init(
                    id: "total",
                    name: "Total amount",
                    startValue: 100,
                    endValue: 150,
                    delta: 50,
                    deltaPercent: 50,
                    icon: nil,
                    isCreditCard: false,
                    isArchived: false
                )
            ],
            currencyBreakdown: [.init(currency: "RUB", convertedValue: 150, percentage: 100)],
            rateSnapshotRevision: rateSnapshotRevision,
            savedAt: Date(timeIntervalSince1970: 2_000)
        )
    }

    @Test("Snapshot разделён между data scope")
    func snapshotIsIsolatedByScope() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FinanceDynamicsSnapshotStore(directoryURL: directory)
        let snapshot = makeSnapshot()
        store.save(snapshot, scopeID: "user-a")

        #expect(store.load(scopeID: "user-a") == snapshot)
        #expect(store.load(scopeID: "user-b") == nil)
    }

    @Test("Повреждённый snapshot игнорируется")
    func corruptSnapshotIsIgnored() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let scopeID = "user-a"
        let digest = SHA256.hash(data: Data(scopeID.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined() + ".json"
        try Data("not-json".utf8).write(to: directory.appendingPathComponent(filename))

        let store = FinanceDynamicsSnapshotStore(directoryURL: directory)
        #expect(store.load(scopeID: scopeID) == nil)
    }

    @Test("Analytics не гидратируется из legacy snapshot без FX revision")
    func overviewSkipsLegacySnapshotWithoutRateRevision() throws {
        let schema = Schema([
            Card.self,
            Credit.self,
            Investment.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowTransaction.self,
            HistoricalRate.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let currencyService = MockDynamicsCurrencyRateService()
        let financeViewModel = FinanceViewModel(
            modelContext: context,
            currencyService: currencyService,
            skipInitialLoad: true
        )
        let snapshotStore = InMemorySnapshotStore()
        let snapshot = makeSnapshot()
        snapshotStore.save(snapshot, scopeID: financeViewModel.historicalValuationScopeID)

        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: financeViewModel,
            currencyService: currencyService,
            snapshotStore: snapshotStore
        )

        #expect(viewModel.state.chartData.isEmpty)
        #expect(viewModel.state.currentBalance != snapshot.currentBalance)
        #expect(!viewModel.state.isInitialLocalProjectionResolved)
    }

    @Test("Analytics гидратируется только при совпадении FX revision")
    func overviewHydratesSnapshotWithCurrentRateRevision() throws {
        defer { CurrencyRateSnapshotRevisionStore.clear() }
        let rateSnapshot = RateSnapshot(
            source: .millio,
            rates: ["USD": 1, "RUB": 80],
            updatedAt: 1_000,
            fetchedAt: 2_000
        )
        let revision = CurrencyRateSnapshotRevisionStore.save(rateSnapshot)
        let schema = Schema([
            Card.self,
            Credit.self,
            Investment.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowTransaction.self,
            HistoricalRate.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = container.mainContext
        let currencyService = MockDynamicsCurrencyRateService()
        let financeViewModel = FinanceViewModel(
            modelContext: context,
            currencyService: currencyService,
            skipInitialLoad: true
        )
        let snapshotStore = InMemorySnapshotStore()
        let snapshot = makeSnapshot(rateSnapshotRevision: revision)
        snapshotStore.save(snapshot, scopeID: financeViewModel.historicalValuationScopeID)

        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: financeViewModel,
            currencyService: currencyService,
            snapshotStore: snapshotStore
        )

        #expect(viewModel.state.currentBalance == snapshot.currentBalance)
        #expect(viewModel.state.chartData.map(\.value) == snapshot.chartData.map(\.value))
    }
}
