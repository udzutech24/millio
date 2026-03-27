import Foundation

protocol AdminStatsRepositoryProtocol: Sendable {
    func loadStats(symbolsLimit: Int) async throws -> AdminStatsSnapshot
}

struct AdminStatsRepository: AdminStatsRepositoryProtocol {
    private let client: any AdminStatsAPIClientProtocol

    init(client: any AdminStatsAPIClientProtocol) {
        self.client = client
    }

    func loadStats(symbolsLimit: Int) async throws -> AdminStatsSnapshot {
        async let overviewTask = client.fetchOverview()
        async let symbolsTask = client.fetchSymbols(limit: symbolsLimit)

        let overview = try await overviewTask
        let symbols = try await symbolsTask
        let resolvedSymbols = symbols.items.isEmpty ? overview.topSymbols : symbols.items

        return AdminStatsSnapshot(
            totalUsers: overview.totalUsers,
            usersLoggedInLast7Days: overview.usersLoggedInLast7Days,
            usersLoggedInLast30Days: overview.usersLoggedInLast30Days,
            usersWithWatchlist: overview.usersWithWatchlist,
            totalWatchlistItems: overview.totalWatchlistItems,
            topSymbols: resolvedSymbols,
            generatedAt: max(overview.generatedAt, symbols.generatedAt),
            requestedSymbolsLimit: symbols.limit
        )
    }
}
