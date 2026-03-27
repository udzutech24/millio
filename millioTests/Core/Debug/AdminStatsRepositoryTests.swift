import Foundation
import Testing
@testable import millio

@Suite("Admin stats repository")
struct AdminStatsRepositoryTests {
    @Test("Repository prefers dedicated symbols endpoint and keeps generated timestamp")
    func testRepositoryMergesOverviewAndSymbols() async throws {
        let repository = AdminStatsRepository(
            client: StubAdminStatsAPIClient(
                overview: AdminStatsOverviewResponse(
                    totalUsers: 124,
                    usersLoggedInLast7Days: 43,
                    usersLoggedInLast30Days: 81,
                    usersWithWatchlist: 57,
                    totalWatchlistItems: 312,
                    topSymbols: [AdminStatsSymbolCount(symbol: "OLD", usersCount: 1)],
                    generatedAt: Date(timeIntervalSince1970: 100)
                ),
                symbols: AdminStatsSymbolsResponse(
                    limit: 25,
                    items: [
                        AdminStatsSymbolCount(symbol: "AAPL", usersCount: 18),
                        AdminStatsSymbolCount(symbol: "TSLA", usersCount: 12)
                    ],
                    generatedAt: Date(timeIntervalSince1970: 120)
                )
            )
        )

        let snapshot = try await repository.loadStats(symbolsLimit: 25)

        #expect(snapshot.totalUsers == 124)
        #expect(snapshot.topSymbols == [
            AdminStatsSymbolCount(symbol: "AAPL", usersCount: 18),
            AdminStatsSymbolCount(symbol: "TSLA", usersCount: 12)
        ])
        #expect(snapshot.generatedAt == Date(timeIntervalSince1970: 120))
        #expect(snapshot.requestedSymbolsLimit == 25)
    }

    @Test("Repository falls back to overview symbols when symbols endpoint is empty")
    func testRepositoryFallsBackToOverviewTopSymbols() async throws {
        let overviewSymbols = [AdminStatsSymbolCount(symbol: "AAPL", usersCount: 18)]
        let repository = AdminStatsRepository(
            client: StubAdminStatsAPIClient(
                overview: AdminStatsOverviewResponse(
                    totalUsers: 10,
                    usersLoggedInLast7Days: 5,
                    usersLoggedInLast30Days: 8,
                    usersWithWatchlist: 3,
                    totalWatchlistItems: 6,
                    topSymbols: overviewSymbols,
                    generatedAt: Date(timeIntervalSince1970: 200)
                ),
                symbols: AdminStatsSymbolsResponse(
                    limit: 25,
                    items: [],
                    generatedAt: Date(timeIntervalSince1970: 150)
                )
            )
        )

        let snapshot = try await repository.loadStats(symbolsLimit: 25)

        #expect(snapshot.topSymbols == overviewSymbols)
        #expect(snapshot.generatedAt == Date(timeIntervalSince1970: 200))
    }
}

private struct StubAdminStatsAPIClient: AdminStatsAPIClientProtocol {
    let overview: AdminStatsOverviewResponse
    let symbols: AdminStatsSymbolsResponse

    func fetchOverview() async throws -> AdminStatsOverviewResponse {
        overview
    }

    func fetchSymbols(limit: Int) async throws -> AdminStatsSymbolsResponse {
        symbols
    }
}
