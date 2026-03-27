import Foundation
import Testing
@testable import millio

@MainActor
@Suite(.serialized)
struct PortfolioSymbolsSyncServiceTests {
    @Test("Login sync sends current snapshot once and skips identical snapshots")
    func testHandleAuthenticationStateChangedSyncsAndDeduplicates() async {
        let provider = StubPortfolioHeldSymbolsProvider(symbols: ["SPY", "BTC/USD"])
        let apiClient = RecordingPortfolioSymbolsAPIClient()
        let eventBus = StubEventBus()
        let isAuthenticated = true
        let service = PortfolioSymbolsSyncService(
            snapshotProvider: provider,
            apiClient: apiClient,
            eventBus: eventBus,
            isAuthenticated: { isAuthenticated },
            debounceNanoseconds: 0
        )

        service.start()
        service.handleAuthenticationStateChanged(isAuthenticated: true)
        await settleAsyncWork()

        #expect(await apiClient.snapshot() == [["SPY", "BTC/USD"]])

        eventBus.publish(FinanceEvent.investmentsUpdated)
        await settleAsyncWork()

        #expect(await apiClient.snapshot() == [["SPY", "BTC/USD"]])
    }

    @Test("Investment updates trigger a new sync when snapshot changes")
    func testInvestmentUpdatesSyncChangedSnapshot() async {
        let provider = StubPortfolioHeldSymbolsProvider(symbols: ["SPY"])
        let apiClient = RecordingPortfolioSymbolsAPIClient()
        let eventBus = StubEventBus()
        let service = PortfolioSymbolsSyncService(
            snapshotProvider: provider,
            apiClient: apiClient,
            eventBus: eventBus,
            isAuthenticated: { true },
            debounceNanoseconds: 0
        )

        service.start()
        await service.syncCurrentSnapshot(reason: "initial")
        provider.setSymbols(["SPY", "QQQ"])

        eventBus.publish(FinanceEvent.investmentsUpdated)
        await settleAsyncWork()

        #expect(await apiClient.snapshot() == [["SPY"], ["SPY", "QQQ"]])
    }

    @Test("Failed sync does not break the flow and can be retried later")
    func testFailedSyncCanRetry() async {
        let provider = StubPortfolioHeldSymbolsProvider(symbols: ["SPY"])
        let apiClient = RecordingPortfolioSymbolsAPIClient()
        let eventBus = StubEventBus()
        await apiClient.setError(PortfolioSymbolsAPIClientError.transport(.noInternet))

        let service = PortfolioSymbolsSyncService(
            snapshotProvider: provider,
            apiClient: apiClient,
            eventBus: eventBus,
            isAuthenticated: { true },
            debounceNanoseconds: 0
        )

        service.start()
        await service.syncCurrentSnapshot(reason: "initial")
        #expect(await apiClient.snapshot() == [["SPY"]])

        await apiClient.setError(nil)
        eventBus.publish(BackupEvent.restoreCompleted)
        await settleAsyncWork()

        #expect(await apiClient.snapshot() == [["SPY"], ["SPY"]])
    }

    @Test("Logout clears cached snapshot so next login syncs again")
    func testLogoutClearsLastSyncedSnapshot() async {
        let provider = StubPortfolioHeldSymbolsProvider(symbols: ["SPY"])
        let apiClient = RecordingPortfolioSymbolsAPIClient()
        let service = PortfolioSymbolsSyncService(
            snapshotProvider: provider,
            apiClient: apiClient,
            eventBus: StubEventBus(),
            isAuthenticated: { true },
            debounceNanoseconds: 0
        )

        await service.syncCurrentSnapshot(reason: "initial")
        service.handleAuthenticationStateChanged(isAuthenticated: false)
        service.handleAuthenticationStateChanged(isAuthenticated: true)
        await settleAsyncWork()

        #expect(await apiClient.snapshot() == [["SPY"], ["SPY"]])
    }
}

@MainActor
private final class StubEventBus: AppEventBusProtocol {
    private var handlers: [UUID: (AppEvent) -> Void] = [:]

    func subscribe(_ handler: @escaping (AppEvent) -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        return id
    }

    func unsubscribe(_ id: UUID) {
        handlers.removeValue(forKey: id)
    }

    func publish(_ event: AppEvent) {
        for handler in handlers.values {
            handler(event)
        }
    }
}

@MainActor
private final class StubPortfolioHeldSymbolsProvider: PortfolioHeldSymbolsProviding {
    private var symbols: [String]

    init(symbols: [String]) {
        self.symbols = symbols
    }

    @MainActor
    func heldSymbolsSnapshot() -> [String] {
        symbols
    }

    func setSymbols(_ symbols: [String]) {
        self.symbols = symbols
    }
}

private actor RecordingPortfolioSymbolsAPIClient: PortfolioSymbolsAPIClientProtocol {
    private var syncedSnapshots: [[String]] = []
    var error: Error?

    func syncSymbols(_ symbols: [String]) async throws {
        syncedSnapshots.append(symbols)
        if let error {
            throw error
        }
    }

    func snapshot() -> [[String]] {
        return syncedSnapshots
    }

    func setError(_ error: Error?) {
        self.error = error
    }
}

@MainActor
private func settleAsyncWork() async {
    try? await Task.sleep(nanoseconds: 20_000_000)
}
