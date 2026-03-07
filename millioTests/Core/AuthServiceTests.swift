import Foundation
import Testing
@testable import millio

struct AuthServiceTests {
    @Test("restoreSession returns nil when refresh token is missing")
    func testRestoreSessionWithoutRefreshToken() async throws {
        let service = AuthService(
            apiClient: FakeAuthAPIClient(),
            tokenStore: AuthTokenStore(refreshTokenStore: InMemoryRefreshTokenStore())
        )

        let restored = try await service.restoreSession()
        #expect(restored == nil)
    }

    @Test("currentUser refreshes tokens when access token is missing")
    func testCurrentUserRefreshesSession() async throws {
        let apiClient = FakeAuthAPIClient()
        let refreshStore = InMemoryRefreshTokenStore(refreshToken: "refresh-1")
        let service = AuthService(
            apiClient: apiClient,
            tokenStore: AuthTokenStore(refreshTokenStore: refreshStore)
        )

        let user = try await service.currentUser()

        #expect(user.id == "user-1")
        let meTokens = await apiClient.meTokens
        #expect(meTokens == ["new-access"])
    }

    @Test("logout clears refresh token even if backend request fails")
    func testLogoutAlwaysClearsRefreshToken() async throws {
        let apiClient = FakeAuthAPIClient(logoutError: AuthServiceError.transport("offline"))
        let refreshStore = InMemoryRefreshTokenStore(refreshToken: "refresh-1")
        let service = AuthService(
            apiClient: apiClient,
            tokenStore: AuthTokenStore(refreshTokenStore: refreshStore)
        )

        await service.logout()

        #expect(try refreshStore.refreshToken() == nil)
    }
}

private actor FakeAuthAPIClient: AuthAPIClientProtocol {
    let logoutError: Error?
    var meTokens: [String] = []

    init(logoutError: Error? = nil) {
        self.logoutError = logoutError
    }

    func signInWithApple(request: AppleAuthRequest) async throws -> AuthResponse {
        AuthResponse(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            accessTokenExpiresInSeconds: 900,
            user: .fixture
        )
    }

    func refresh(refreshToken: String) async throws -> AuthResponse {
        AuthResponse(
            accessToken: "new-access",
            refreshToken: refreshToken,
            accessTokenExpiresInSeconds: 900,
            user: .fixture
        )
    }

    func logout(refreshToken: String) async throws -> LogoutResponse {
        if let logoutError {
            throw logoutError
        }
        return LogoutResponse(success: true)
    }

    func me(accessToken: String) async throws -> AuthUser {
        meTokens.append(accessToken)
        return .fixture
    }
}

private final class InMemoryRefreshTokenStore: RefreshTokenStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRefreshToken: String?

    init(refreshToken: String? = nil) {
        self.storedRefreshToken = refreshToken
    }

    func refreshToken() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storedRefreshToken
    }

    func setRefreshToken(_ value: String) throws {
        lock.lock()
        storedRefreshToken = value
        lock.unlock()
    }

    func clearRefreshToken() throws {
        lock.lock()
        storedRefreshToken = nil
        lock.unlock()
    }
}

private extension AuthUser {
    static let fixture = AuthUser(
        id: "user-1",
        email: "sid@example.com",
        emailVerified: true,
        firstName: "Sid",
        lastName: "Orkin",
        fullName: "Sid Orkin",
        avatarUrl: nil,
        lastLoginAt: nil
    )
}
