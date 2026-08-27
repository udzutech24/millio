import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import millio

/// Сервис курсов с управляемым снимком: ревизия FX считается по значениям (R11),
/// поэтому кэш «Динамики» валиден ровно для того набора курсов, на котором посчитан.
@MainActor
private final class StubRateSnapshotCurrencyService: CurrencyRateServiceProtocol {
    var snapshot: RateSnapshot?

    init(snapshot: RateSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func getRate(from: String, to: String) async -> Double? { 1.0 }
    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? { 1.0 }
    func convert(amount: Double, from: String, to: String) async -> Double? { amount }
    func forceRefreshRates() async {}
    func currentRateSnapshot() -> RateSnapshot? { snapshot }
}

@Suite(.serialized)
@MainActor
struct FinanceDynamicsSnapshotStoreTests {
    private static let schema = Schema([
        Card.self,
        Credit.self,
        Investment.self,
        FinanceGroup.self,
        FinanceAccount.self,
        CashflowTransaction.self,
        HistoricalRate.self
    ])

    private final class InMemorySnapshotStore: FinanceDynamicsSnapshotStoreProtocol {
        private var snapshots: [String: FinanceDynamicsSnapshot] = [:]

        func load(scopeID: String) -> FinanceDynamicsSnapshot? {
            snapshots[scopeID]
        }

        func save(_ snapshot: FinanceDynamicsSnapshot, scopeID: String) {
            snapshots[scopeID] = snapshot
        }
    }

    private func makeSnapshot(
        rateSnapshotRevision: String? = nil,
        displayCurrency: String = "RUB",
        period: DynamicsPeriod = .week,
        balanceFormulaVersion: String? = FinanceDynamicsSnapshot.currentBalanceFormulaVersion
    ) -> FinanceDynamicsSnapshot {
        FinanceDynamicsSnapshot(
            displayCurrency: displayCurrency,
            periodRawValue: period.rawValue,
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
            balanceFormulaVersion: balanceFormulaVersion,
            savedAt: Date(timeIntervalSince1970: 2_000)
        )
    }

    /// Контейнер возвращается наружу и удерживается тестом: если он умрёт,
    /// `mainContext` останется без стора и VM будет читать пустоту (урок R11).
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Self.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeFinanceViewModel(
        context: ModelContext,
        currencyService: CurrencyRateServiceProtocol,
        scopeID: String
    ) -> FinanceViewModel {
        FinanceViewModel(
            modelContext: context,
            currencyService: currencyService,
            historicalValuationScopeID: scopeID,
            skipInitialLoad: true
        )
    }

    // MARK: - Store

    @Test("Снимок «Динамики» переживает перезапуск приложения")
    func snapshotSurvivesProcessRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let snapshot = makeSnapshot()
        FinanceDynamicsSnapshotStore(directoryURL: directory).save(snapshot, scopeID: "user-a")

        // Новый экземпляр = новый запуск процесса: снимок обязан читаться с диска.
        let afterRestart = FinanceDynamicsSnapshotStore(directoryURL: directory)
        #expect(afterRestart.load(scopeID: "user-a") == snapshot)
    }

    @Test("Снимок разделён между data scope")
    func snapshotIsIsolatedByScope() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = FinanceDynamicsSnapshotStore(directoryURL: directory)
        store.save(makeSnapshot(), scopeID: "user-a")

        #expect(store.load(scopeID: "user-b") == nil)
    }

    @Test("Повреждённый снимок игнорируется")
    func corruptSnapshotIsIgnored() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let scopeID = "user-a"
        let digest = SHA256.hash(data: Data(scopeID.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined() + ".json"
        try Data("not-json".utf8).write(to: directory.appendingPathComponent(filename))

        #expect(FinanceDynamicsSnapshotStore(directoryURL: directory).load(scopeID: scopeID) == nil)
    }

    // MARK: - Cold start

    @Test("Холодный старт с кэшем не показывает пустое состояние")
    func coldStartWithCacheSkipsEmptyState() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let currencyService = StubRateSnapshotCurrencyService()
        let financeViewModel = makeFinanceViewModel(
            context: context,
            currencyService: currencyService,
            scopeID: "scope-user"
        )
        let store = InMemorySnapshotStore()
        let snapshot = makeSnapshot()
        store.save(snapshot, scopeID: "scope-user")

        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: financeViewModel,
            currencyService: currencyService,
            snapshotStore: store
        )

        // Ровно те условия, по которым экран решает показывать «Нет данных» / «Нет групп».
        #expect(!viewModel.state.chartData.isEmpty)
        #expect(!viewModel.state.dynamicsBreakdown.isEmpty)
        #expect(viewModel.state.currentBalance == snapshot.currentBalance)
    }

    @Test("Холодный старт без кэша показывает загрузку, а не «нет данных»")
    func coldStartWithoutCacheShowsLoadingNotEmptyState() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let currencyService = StubRateSnapshotCurrencyService()
        let financeViewModel = makeFinanceViewModel(
            context: context,
            currencyService: currencyService,
            scopeID: "scope-user"
        )

        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: financeViewModel,
            currencyService: currencyService,
            snapshotStore: InMemorySnapshotStore()
        )
        viewModel.loadData()

        #expect(viewModel.state.chartData.isEmpty)
        #expect(viewModel.state.isLoading)
        #expect(!viewModel.state.isInitialLocalProjectionResolved)
    }

    @Test("Кэш чужого scope не подставляется в гостевой режим")
    func snapshotOfAnotherScopeIsNotShown() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let currencyService = StubRateSnapshotCurrencyService()
        let store = InMemorySnapshotStore()
        store.save(makeSnapshot(), scopeID: "scope-user")

        let guestFinanceViewModel = makeFinanceViewModel(
            context: context,
            currencyService: currencyService,
            scopeID: "scope-guest"
        )
        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: guestFinanceViewModel,
            currencyService: currencyService,
            snapshotStore: store
        )

        #expect(viewModel.state.chartData.isEmpty)
        #expect(viewModel.state.currentBalance == 0)
    }

    // MARK: - FX revision

    @Test("Кэш другого набора курсов не гидратируется")
    func snapshotWithForeignRateRevisionIsIgnored() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let currencyService = StubRateSnapshotCurrencyService(
            snapshot: RateSnapshot(source: .millio, rates: ["USD": 1, "RUB": 80], updatedAt: 1_000, fetchedAt: 2_000)
        )
        let financeViewModel = makeFinanceViewModel(
            context: context,
            currencyService: currencyService,
            scopeID: "scope-user"
        )
        let store = InMemorySnapshotStore()
        store.save(makeSnapshot(rateSnapshotRevision: "stale-revision"), scopeID: "scope-user")

        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: financeViewModel,
            currencyService: currencyService,
            snapshotStore: store
        )

        #expect(viewModel.state.chartData.isEmpty)
    }

    @Test("Кэш того же набора курсов гидратируется")
    func snapshotWithMatchingRateRevisionHydrates() throws {
        let rateSnapshot = RateSnapshot(
            source: .millio,
            rates: ["USD": 1, "RUB": 80],
            updatedAt: 1_000,
            fetchedAt: 2_000
        )
        let container = try makeContainer()
        let context = container.mainContext
        let currencyService = StubRateSnapshotCurrencyService(snapshot: rateSnapshot)
        let financeViewModel = makeFinanceViewModel(
            context: context,
            currencyService: currencyService,
            scopeID: "scope-user"
        )
        let store = InMemorySnapshotStore()
        let revision = CurrencyRateSnapshotRevisionStore.revision(for: rateSnapshot)
        let snapshot = makeSnapshot(rateSnapshotRevision: revision)
        store.save(snapshot, scopeID: "scope-user")

        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: financeViewModel,
            currencyService: currencyService,
            snapshotStore: store
        )

        #expect(viewModel.state.chartData.map(\.value) == snapshot.chartData.map(\.value))
    }

    /// Ф1 плана `2026-08-26__deposit-confirmed-balance-unification.md`: курсы и период кэш
    /// валидирует, но смена самой формулы баланса их не меняет — без версии-ключа первый вход
    /// после обновления показал бы старую, завышенную сумму вклада.
    @Test("Кэш, посчитанный предыдущей формулой баланса, не гидратируется")
    func snapshotWithOutdatedBalanceFormulaIsIgnored() throws {
        let rateSnapshot = RateSnapshot(
            source: .millio,
            rates: ["USD": 1, "RUB": 80],
            updatedAt: 1_000,
            fetchedAt: 2_000
        )
        let container = try makeContainer()
        let context = container.mainContext
        let currencyService = StubRateSnapshotCurrencyService(snapshot: rateSnapshot)
        let financeViewModel = makeFinanceViewModel(
            context: context,
            currencyService: currencyService,
            scopeID: "scope-user"
        )
        let store = InMemorySnapshotStore()
        store.save(
            makeSnapshot(
                rateSnapshotRevision: CurrencyRateSnapshotRevisionStore.revision(for: rateSnapshot),
                balanceFormulaVersion: nil // снимок, записанный до Ф1
            ),
            scopeID: "scope-user"
        )

        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: financeViewModel,
            currencyService: currencyService,
            snapshotStore: store
        )

        #expect(viewModel.state.chartData.isEmpty)
    }

    @Test("Фоновое обновление курсов не мигает пустым экраном")
    func rateRefreshRecalculatesWithoutBlinking() throws {
        let rateSnapshot = RateSnapshot(
            source: .millio,
            rates: ["USD": 1, "RUB": 80],
            updatedAt: 1_000,
            fetchedAt: 2_000
        )
        let container = try makeContainer()
        let context = container.mainContext
        let currencyService = StubRateSnapshotCurrencyService(snapshot: rateSnapshot)
        let financeViewModel = makeFinanceViewModel(
            context: context,
            currencyService: currencyService,
            scopeID: "scope-user"
        )
        let store = InMemorySnapshotStore()
        store.save(
            makeSnapshot(rateSnapshotRevision: CurrencyRateSnapshotRevisionStore.revision(for: rateSnapshot)),
            scopeID: "scope-user"
        )

        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: financeViewModel,
            currencyService: currencyService,
            snapshotStore: store
        )

        // Новый набор курсов → пересчёт. Пока он идёт, прежние цифры остаются на экране.
        currencyService.snapshot = RateSnapshot(
            source: .millio,
            rates: ["USD": 1, "RUB": 90],
            updatedAt: 3_000,
            fetchedAt: 4_000
        )
        viewModel.loadData()

        #expect(!viewModel.state.isLoading)
        #expect(!viewModel.state.chartData.isEmpty)
    }
}
