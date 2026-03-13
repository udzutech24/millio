import Foundation

struct APIClientFactory {
    let runtime: BackendSessionRuntime

    func makeAuthService() -> any AuthServiceProtocol {
        AuthService(
            apiClient: AuthAPIClient(configuration: runtime.authConfiguration),
            tokenStore: AuthTokenStore(
                refreshTokenStore: KeychainRefreshTokenStore(account: runtime.refreshTokenAccountKey)
            )
        )
    }

    func authConfigurationProvider() -> @Sendable () throws -> AuthConfiguration {
        let configuration = runtime.authConfiguration
        return { configuration }
    }
}
