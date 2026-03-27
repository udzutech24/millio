#if DEBUG
import Combine
import Foundation

@MainActor
final class AdminStatsDebugViewModel: ObservableObject {
    enum ScreenState: Equatable {
        case idle
        case loading
        case success(AdminStatsSnapshot)
        case empty
        case unauthorized(String)
        case forbidden(String)
        case networkError(String)
        case error(String)
    }

    @Published private(set) var screenState: ScreenState = .idle
    @Published private(set) var isRefreshing = false

    private let repository: any AdminStatsRepositoryProtocol
    private let symbolsLimit: Int
    private var hasLoadedOnce = false

    init(
        repository: any AdminStatsRepositoryProtocol,
        symbolsLimit: Int = 25
    ) {
        self.repository = repository
        self.symbolsLimit = symbolsLimit
    }

    func loadIfNeeded() async {
        guard !hasLoadedOnce else { return }
        await load()
    }

    func refresh() async {
        await load(forceRefresh: true)
    }

    private func load(forceRefresh: Bool = false) async {
        AppLogger.log(
            .debug,
            category: "AdminStats",
            "Admin stats load started (forceRefresh: \(forceRefresh), hasLoadedOnce: \(hasLoadedOnce))"
        )

        if hasLoadedOnce || forceRefresh {
            isRefreshing = true
        } else {
            screenState = .loading
        }

        defer { isRefreshing = false }

        do {
            let snapshot = try await repository.loadStats(symbolsLimit: symbolsLimit)
            hasLoadedOnce = true
            screenState = snapshot.isEmpty ? .empty : .success(snapshot)
            AppLogger.log(
                .info,
                category: "AdminStats",
                "Admin stats load finished successfully (empty: \(snapshot.isEmpty), topSymbols: \(snapshot.topSymbols.count))"
            )
        } catch {
            hasLoadedOnce = true
            screenState = mapError(error)
            AppLogger.log(
                .warning,
                category: "AdminStats",
                "Admin stats load failed: \(error.localizedDescription)"
            )
        }
    }

    private func mapError(_ error: Error) -> ScreenState {
        if let authError = error as? AuthServiceError {
            switch authError {
            case .notAuthenticated,
                 .unauthorized:
                return .unauthorized("Session expired. Sign in with an authorized ADMIN account and try again.")
            case .forbidden(_, let message):
                return .forbidden(message)
            case .transport(let transportError):
                return .networkError(transportError.errorDescription ?? "Network error while loading admin statistics.")
            default:
                return .error(authError.errorDescription ?? "Failed to load admin statistics.")
            }
        }

        if let apiError = error as? AdminStatsAPIClientError {
            switch apiError {
            case .unauthorized:
                return .unauthorized("Session expired. Sign in with an authorized ADMIN account and try again.")
            case .forbidden(let message, _):
                return .forbidden(message)
            case .transport(let transportError):
                return .networkError(transportError.errorDescription ?? "Network error while loading admin statistics.")
            default:
                return .error(apiError.errorDescription ?? "Failed to load admin statistics.")
            }
        }

        return .error(error.localizedDescription.isEmpty ? "Failed to load admin statistics." : error.localizedDescription)
    }
}
#endif
