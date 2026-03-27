import Foundation

protocol AppEventBusProtocol: AnyObject {
    @MainActor
    func subscribe(_ handler: @escaping (AppEvent) -> Void) -> UUID

    @MainActor
    func unsubscribe(_ id: UUID)
}

extension EventBus: AppEventBusProtocol {}

@MainActor
final class PortfolioSymbolsSyncService {
    private let snapshotProvider: any PortfolioHeldSymbolsProviding
    private let apiClient: any PortfolioSymbolsAPIClientProtocol
    private let eventBus: any AppEventBusProtocol
    private let isAuthenticated: @MainActor @Sendable () -> Bool
    private let debounceNanoseconds: UInt64

    private var eventSubscriptionID: UUID?
    private var scheduledSyncTask: Task<Void, Never>?
    private var lastSyncedSymbols: [String]?

    init(
        snapshotProvider: any PortfolioHeldSymbolsProviding,
        apiClient: any PortfolioSymbolsAPIClientProtocol,
        eventBus: any AppEventBusProtocol,
        isAuthenticated: @escaping @MainActor @Sendable () -> Bool,
        debounceNanoseconds: UInt64 = 300_000_000
    ) {
        self.snapshotProvider = snapshotProvider
        self.apiClient = apiClient
        self.eventBus = eventBus
        self.isAuthenticated = isAuthenticated
        self.debounceNanoseconds = debounceNanoseconds
    }

    func start() {
        guard eventSubscriptionID == nil else { return }

        eventSubscriptionID = eventBus.subscribe { [weak self] event in
            guard let self else { return }
            if case FinanceEvent.investmentsUpdated = event {
                self.scheduleSync(reason: "portfolio_changed")
                return
            }

            if case BackupEvent.restoreCompleted = event {
                self.scheduleSync(reason: "portfolio_restored")
            }
        }
    }

    func stop() {
        scheduledSyncTask?.cancel()
        scheduledSyncTask = nil

        if let eventSubscriptionID {
            eventBus.unsubscribe(eventSubscriptionID)
            self.eventSubscriptionID = nil
        }
    }

    func handleAuthenticationStateChanged(isAuthenticated: Bool) {
        if isAuthenticated {
            scheduleSync(reason: "login")
        } else {
            scheduledSyncTask?.cancel()
            scheduledSyncTask = nil
            lastSyncedSymbols = nil
        }
    }

    func syncCurrentSnapshot(reason: String) async {
        guard isAuthenticated() else { return }

        let symbols = snapshotProvider.heldSymbolsSnapshot()
        guard symbols != lastSyncedSymbols else { return }

        do {
            try await apiClient.syncSymbols(symbols)
            lastSyncedSymbols = symbols
        } catch {
            AppLogger.log(
                .warning,
                category: "PortfolioSymbolsSync",
                "Portfolio symbols sync skipped after \(reason): \(error.localizedDescription)"
            )
        }
    }

    private func scheduleSync(reason: String) {
        scheduledSyncTask?.cancel()
        scheduledSyncTask = Task { [weak self] in
            guard let self else { return }
            if debounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self.syncCurrentSnapshot(reason: reason)
        }
    }
}
