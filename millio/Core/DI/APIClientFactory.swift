import Foundation

struct APIClientFactory {
    let runtime: BackendSessionRuntime

    func makeAuthService() -> any AuthServiceProtocol {
        AuthService(
            apiClient: AuthAPIClient(configuration: runtime.authConfiguration),
            tokenStore: AuthTokenStore(
                refreshTokenStore: KeychainRefreshTokenStore(account: runtime.refreshTokenAccountKey)
            ),
            sessionSnapshotStore: UserDefaultsAuthSessionSnapshotStore(
                key: runtime.sessionSnapshotStorageKey
            ),
            diagnosticsContext: AuthDiagnosticsContext(configuration: runtime.authConfiguration)
        )
    }

    func makeAdminStatsRepository(
        authService: any AuthServiceProtocol,
        session: URLSession = .shared
    ) -> AdminStatsRepository {
        AdminStatsRepository(
            client: AdminStatsAPIClient(
                authService: authService,
                configurationProvider: authConfigurationProvider(),
                session: session
            )
        )
    }

    func authConfigurationProvider() -> @Sendable () throws -> AuthConfiguration {
        let configuration = runtime.authConfiguration
        return { configuration }
    }
}
