import Foundation

struct AdminStatsSymbolCount: Codable, Equatable, Identifiable, Sendable {
    let symbol: String
    let usersCount: Int

    var id: String { symbol }
}

struct AdminStatsOverviewResponse: Codable, Equatable, Sendable {
    let totalUsers: Int
    let usersLoggedInLast7Days: Int
    let usersLoggedInLast30Days: Int
    let usersWithWatchlist: Int
    let totalWatchlistItems: Int
    let topSymbols: [AdminStatsSymbolCount]
    let generatedAt: Date
}

struct AdminStatsSymbolsResponse: Codable, Equatable, Sendable {
    let limit: Int
    let items: [AdminStatsSymbolCount]
    let generatedAt: Date
}

struct AdminStatsSnapshot: Equatable, Sendable {
    let totalUsers: Int
    let usersLoggedInLast7Days: Int
    let usersLoggedInLast30Days: Int
    let usersWithWatchlist: Int
    let totalWatchlistItems: Int
    let topSymbols: [AdminStatsSymbolCount]
    let generatedAt: Date
    let requestedSymbolsLimit: Int

    var isEmpty: Bool {
        totalUsers == 0 &&
        usersLoggedInLast7Days == 0 &&
        usersLoggedInLast30Days == 0 &&
        usersWithWatchlist == 0 &&
        totalWatchlistItems == 0 &&
        topSymbols.isEmpty
    }
}
