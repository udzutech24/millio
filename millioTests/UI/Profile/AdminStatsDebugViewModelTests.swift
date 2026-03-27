import Foundation
import Testing
@testable import millio

@Suite("Admin stats debug view model")
struct AdminStatsDebugViewModelTests {
    @Test("Successful load exposes success state")
    @MainActor
    func testLoadSuccess() async {
        let snapshot = AdminStatsSnapshot(
            totalUsers: 124,
            usersLoggedInLast7Days: 43,
            usersLoggedInLast30Days: 81,
            usersWithWatchlist: 57,
            totalWatchlistItems: 312,
            topSymbols: [AdminStatsSymbolCount(symbol: "AAPL", usersCount: 18)],
            generatedAt: Date(timeIntervalSince1970: 100),
            requestedSymbolsLimit: 25
        )
        let viewModel = AdminStatsDebugViewModel(
            repository: StubAdminStatsRepository(result: .success(snapshot))
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.screenState == .success(snapshot))
        #expect(viewModel.isRefreshing == false)
    }

    @Test("Empty snapshot maps to empty state")
    @MainActor
    func testLoadEmpty() async {
        let snapshot = AdminStatsSnapshot(
            totalUsers: 0,
            usersLoggedInLast7Days: 0,
            usersLoggedInLast30Days: 0,
            usersWithWatchlist: 0,
            totalWatchlistItems: 0,
            topSymbols: [],
            generatedAt: Date(timeIntervalSince1970: 100),
            requestedSymbolsLimit: 25
        )
        let viewModel = AdminStatsDebugViewModel(
            repository: StubAdminStatsRepository(result: .success(snapshot))
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.screenState == .empty)
    }

    @Test("Forbidden backend response maps to admin access state")
    @MainActor
    func testLoadForbidden() async {
        let viewModel = AdminStatsDebugViewModel(
            repository: StubAdminStatsRepository(
                result: .failure(AdminStatsAPIClientError.forbidden(message: "ADMIN access required", requestId: "req-1"))
            )
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.screenState == .forbidden("ADMIN access required"))
    }

    @Test("Transport failure maps to network error state")
    @MainActor
    func testLoadNetworkError() async {
        let viewModel = AdminStatsDebugViewModel(
            repository: StubAdminStatsRepository(
                result: .failure(AdminStatsAPIClientError.transport(.noInternet))
            )
        )

        await viewModel.loadIfNeeded()

        #expect(viewModel.screenState == .networkError("The Internet connection appears to be offline."))
    }
}

private struct StubAdminStatsRepository: AdminStatsRepositoryProtocol {
    let result: Result<AdminStatsSnapshot, Error>

    func loadStats(symbolsLimit: Int) async throws -> AdminStatsSnapshot {
        try result.get()
    }
}
