import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct AuthServiceTests {
    @Test("restoreSession returns nil when refresh token is missing")
    func testRestoreSessionWithoutRefreshToken() async throws {
        let snapshotStore = InMemoryAuthSessionSnapshotStore(session: .fixtureSession)
        let service = AuthService(
            apiClient: FakeAuthAPIClient(),
            tokenStore: AuthTokenStore(refreshTokenStore: InMemoryRefreshTokenStore()),
            sessionSnapshotStore: snapshotStore
        )

        let restored = try await service.restoreSession()
        #expect(restored == nil)
        #expect(await service.lastKnownSession() == nil)
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

    @Test("restoreSession clears refresh token after 401 on refresh")
    func testRestoreSessionClearsTokenOnUnauthorizedRefresh() async throws {
        let refreshStore = InMemoryRefreshTokenStore(refreshToken: "refresh-1")
        let snapshotStore = InMemoryAuthSessionSnapshotStore(session: .fixtureSession)
        let apiClient = FakeAuthAPIClient(refreshError: AuthServiceError.unauthorized())
        let service = AuthService(
            apiClient: apiClient,
            tokenStore: AuthTokenStore(refreshTokenStore: refreshStore),
            sessionSnapshotStore: snapshotStore
        )

        let restored = try await service.restoreSession()

        #expect(restored == nil)
        #expect(try refreshStore.refreshToken() == nil)
        #expect(await service.lastKnownSession() == nil)
        let refreshCalls = await apiClient.refreshCallCount
        #expect(refreshCalls == 1)
    }

    @Test("currentUser stops after single unauthorized refresh and clears session")
    func testCurrentUserDoesNotLoopWhenRefreshUnauthorized() async throws {
        let refreshStore = InMemoryRefreshTokenStore(refreshToken: "refresh-1")
        let apiClient = FakeAuthAPIClient(refreshError: AuthServiceError.unauthorized())
        let service = AuthService(
            apiClient: apiClient,
            tokenStore: AuthTokenStore(refreshTokenStore: refreshStore)
        )

        await #expect(throws: AuthServiceError.unauthorized()) {
            _ = try await service.currentUser()
        }

        #expect(try refreshStore.refreshToken() == nil)
        let refreshCalls = await apiClient.refreshCallCount
        let meTokens = await apiClient.meTokens
        #expect(refreshCalls == 1)
        #expect(meTokens.isEmpty)
    }

    @Test("logout clears refresh token even if backend request fails")
    func testLogoutAlwaysClearsRefreshToken() async throws {
        let apiClient = FakeAuthAPIClient(logoutError: AuthServiceError.transport(.noInternet))
        let refreshStore = InMemoryRefreshTokenStore(refreshToken: "refresh-1")
        let service = AuthService(
            apiClient: apiClient,
            tokenStore: AuthTokenStore(refreshTokenStore: refreshStore)
        )

        await service.logout()

        #expect(try refreshStore.refreshToken() == nil)
    }

    @Test("signInWithApple keeps backend request id in session")
    func testSignInKeepsBackendRequestId() async throws {
        let service = AuthService(
            apiClient: FakeAuthAPIClient(signInRequestId: "backend-auth-1"),
            tokenStore: AuthTokenStore(refreshTokenStore: InMemoryRefreshTokenStore())
        )

        let session = try await service.signInWithApple(
            identityToken: "identity-token",
            email: "sid@example.com",
            firstName: "Sid",
            lastName: "Orkin"
        )

        #expect(session.requestId == "backend-auth-1")
        #expect(session.source == .appleSignIn)
    }

    @Test("signInWithApple surfaces token persistence failure")
    func testSignInSurfacesTokenPersistenceFailure() async {
        let refreshStore = InMemoryRefreshTokenStore(writeError: AuthServiceError.tokenPersistenceFailed("Keychain save failed."))
        let service = AuthService(
            apiClient: FakeAuthAPIClient(),
            tokenStore: AuthTokenStore(refreshTokenStore: refreshStore)
        )

        await #expect(throws: AuthServiceError.tokenPersistenceFailed("Keychain save failed.")) {
            _ = try await service.signInWithApple(
                identityToken: "identity-token",
                email: nil,
                firstName: nil,
                lastName: nil
            )
        }
    }

    @Test("refresh applies cooldown after 429 and does not hammer backend")
    func testRefreshRateLimitBackoffPreventsFlood() async {
        let refreshStore = InMemoryRefreshTokenStore(refreshToken: "refresh-1")
        let apiClient = FakeAuthAPIClient(
            refreshResults: [
                .failure(AuthServiceError.rateLimited(requestId: "backend-429", message: "Too many attempts", retryAfter: 5))
            ]
        )
        let service = AuthService(
            apiClient: apiClient,
            tokenStore: AuthTokenStore(refreshTokenStore: refreshStore)
        )

        await #expect(throws: AuthServiceError.rateLimited(requestId: "backend-429", message: "Too many attempts", retryAfter: 5)) {
            _ = try await service.accessToken(forceRefresh: true)
        }

        do {
            _ = try await service.accessToken(forceRefresh: true)
            #expect(Bool(false))
        } catch let AuthServiceError.rateLimited(requestId, message, retryAfter) {
            #expect(requestId == "backend-429")
            #expect(message == "Too many attempts")
            #expect((retryAfter ?? 0) > 0)
            #expect((retryAfter ?? 0) <= 5)
        } catch {
            #expect(Bool(false))
        }

        let refreshCalls = await apiClient.refreshCallCount
        #expect(refreshCalls == 1)
    }

    @Test("signIn applies cooldown after 429 and fails fast on repeated attempts")
    func testSignInRateLimitBackoffPreventsFlood() async {
        let apiClient = FakeAuthAPIClient(
            signInResults: [
                .failure(AuthServiceError.rateLimited(requestId: "backend-signin-429", message: "Too many attempts", retryAfter: 4))
            ]
        )
        let service = AuthService(
            apiClient: apiClient,
            tokenStore: AuthTokenStore(refreshTokenStore: InMemoryRefreshTokenStore())
        )

        await #expect(throws: AuthServiceError.rateLimited(requestId: "backend-signin-429", message: "Too many attempts", retryAfter: 4)) {
            _ = try await service.signInWithApple(
                identityToken: "identity-token",
                email: nil,
                firstName: nil,
                lastName: nil
            )
        }

        do {
            _ = try await service.signInWithApple(
                identityToken: "identity-token",
                email: nil,
                firstName: nil,
                lastName: nil
            )
            #expect(Bool(false))
        } catch let AuthServiceError.rateLimited(requestId, message, retryAfter) {
            #expect(requestId == "backend-signin-429")
            #expect(message == "Too many attempts")
            #expect((retryAfter ?? 0) > 0)
            #expect((retryAfter ?? 0) <= 4)
        } catch {
            #expect(Bool(false))
        }

        let signInCalls = await apiClient.signInCallCount
        #expect(signInCalls == 1)
    }

    @Test("access token expiry uses backend ttl")
    func testAccessTokenExpiryUsesBackendTTL() async throws {
        let snapshotStore = InMemoryAuthSessionSnapshotStore()
        let service = AuthService(
            apiClient: FakeAuthAPIClient(),
            tokenStore: AuthTokenStore(refreshTokenStore: InMemoryRefreshTokenStore()),
            sessionSnapshotStore: snapshotStore
        )

        let session = try await service.signInWithApple(
            identityToken: "identity-token",
            email: "sid@example.com",
            firstName: "Sid",
            lastName: "Orkin"
        )

        let storedExpiry = await service.accessTokenExpiryDate()

        #expect(storedExpiry != nil)
        #expect(abs((storedExpiry ?? .distantPast).timeIntervalSince(session.accessTokenExpiresAt)) < 1)
        #expect(session.accessTokenExpiresAt.timeIntervalSinceNow > 850)
        #expect(session.accessTokenExpiresAt.timeIntervalSinceNow < 950)
        #expect(await service.lastKnownSession()?.user == .fixture)
    }
}

private actor FakeAuthAPIClient: AuthAPIClientProtocol {
    let logoutError: Error?
    let refreshError: Error?
    let signInRequestId: String?
    private var queuedSignInResults: [Result<AuthNetworkResult<AuthResponse>, Error>]
    private var queuedRefreshResults: [Result<AuthNetworkResult<AuthResponse>, Error>]
    var meTokens: [String] = []
    var refreshCallCount: Int = 0
    var signInCallCount: Int = 0

    init(
        logoutError: Error? = nil,
        refreshError: Error? = nil,
        signInRequestId: String? = "backend-auth-1",
        signInResults: [Result<AuthNetworkResult<AuthResponse>, Error>] = [],
        refreshResults: [Result<AuthNetworkResult<AuthResponse>, Error>] = []
    ) {
        self.logoutError = logoutError
        self.refreshError = refreshError
        self.signInRequestId = signInRequestId
        self.queuedSignInResults = signInResults
        self.queuedRefreshResults = refreshResults
    }

    func signInWithApple(request: AppleAuthRequest) async throws -> AuthNetworkResult<AuthResponse> {
        signInCallCount += 1
        if !queuedSignInResults.isEmpty {
            let result = queuedSignInResults.removeFirst()
            switch result {
            case .success(let response):
                return response
            case .failure(let error):
                throw error
            }
        }

        return AuthNetworkResult(
            value: AuthResponse(
                accessToken: "access-1",
                refreshToken: "refresh-1",
                accessTokenExpiresInSeconds: 900,
                user: .fixture
            )
            ,
            metadata: AuthResponseMetadata(
                statusCode: 200,
                requestId: signInRequestId,
                clientRequestId: "client-auth-1",
                durationMilliseconds: 42
            )
        )
    }

    func refresh(refreshToken: String) async throws -> AuthNetworkResult<AuthResponse> {
        refreshCallCount += 1
        if !queuedRefreshResults.isEmpty {
            let result = queuedRefreshResults.removeFirst()
            switch result {
            case .success(let response):
                return response
            case .failure(let error):
                throw error
            }
        }
        if let refreshError {
            throw refreshError
        }
        return AuthNetworkResult(
            value: AuthResponse(
                accessToken: "new-access",
                refreshToken: refreshToken,
                accessTokenExpiresInSeconds: 900,
                user: .fixture
            ),
            metadata: AuthResponseMetadata(
                statusCode: 200,
                requestId: "backend-refresh-1",
                clientRequestId: "client-refresh-1",
                durationMilliseconds: 18
            )
        )
    }

    func logout(refreshToken: String) async throws -> AuthNetworkResult<LogoutResponse> {
        if let logoutError {
            throw logoutError
        }
        return AuthNetworkResult(
            value: LogoutResponse(success: true),
            metadata: AuthResponseMetadata(
                statusCode: 200,
                requestId: "backend-logout-1",
                clientRequestId: "client-logout-1",
                durationMilliseconds: 11
            )
        )
    }

    func me(accessToken: String) async throws -> AuthNetworkResult<AuthUser> {
        meTokens.append(accessToken)
        return AuthNetworkResult(
            value: .fixture,
            metadata: AuthResponseMetadata(
                statusCode: 200,
                requestId: "backend-me-1",
                clientRequestId: "client-me-1",
                durationMilliseconds: 9
            )
        )
    }
}

private final class InMemoryRefreshTokenStore: RefreshTokenStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storedRefreshToken: String?
    private let writeError: Error?

    init(refreshToken: String? = nil, writeError: Error? = nil) {
        self.storedRefreshToken = refreshToken
        self.writeError = writeError
    }

    func refreshToken() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storedRefreshToken
    }

    func setRefreshToken(_ value: String) throws {
        if let writeError {
            throw writeError
        }

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

private final class InMemoryAuthSessionSnapshotStore: AuthSessionSnapshotStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var storedSession: AuthSession?

    init(session: AuthSession? = nil) {
        self.storedSession = session
    }

    func session() throws -> AuthSession? {
        lock.lock()
        defer { lock.unlock() }
        return storedSession
    }

    func setSession(_ session: AuthSession) throws {
        lock.lock()
        storedSession = session
        lock.unlock()
    }

    func clearSession() throws {
        lock.lock()
        storedSession = nil
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

private extension AuthSession {
    static let fixtureSession = AuthSession(
        user: .fixture,
        accessTokenExpiresAt: Date().addingTimeInterval(900),
        metadata: AuthResponseMetadata(
            statusCode: 200,
            requestId: "backend-auth-1",
            clientRequestId: "client-auth-1",
            durationMilliseconds: 42
        ),
        source: .appleSignIn
    )
}
