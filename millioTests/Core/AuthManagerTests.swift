import AuthenticationServices
import Foundation
import Testing
@testable import millio

@MainActor
@Suite(.serialized)
struct AuthManagerTests {
    @Test("restore session shows user friendly toast for backend 500")
    func testRestoreSessionMapsBackend500ToToast() async {
        let toastCenter = ToastCenter()
        let manager = AuthManager(
            service: FailingAuthService(restoreError: AuthServiceError.server(statusCode: 500, message: "Internal server error")),
            toastCenter: toastCenter
        )

        await manager.restoreSession()

        #expect(toastCenter.isPresented)
        #expect(toastCenter.message == "Server error. Try again later.")
        #expect(manager.errorMessage == "Server error. Try again later.")
    }

    @Test("restore session shows offline toast for transport errors")
    func testRestoreSessionMapsOfflineTransportToToast() async {
        let toastCenter = ToastCenter()
        let manager = AuthManager(
            service: FailingAuthService(restoreError: AuthServiceError.transport(.noInternet)),
            toastCenter: toastCenter
        )

        await manager.restoreSession()

        #expect(toastCenter.isPresented)
        #expect(toastCenter.message == "No internet connection. Check your network and try again.")
    }

    @Test("restore session keeps cached session on offline error")
    func testRestoreSessionKeepsCachedSessionOnOfflineError() async {
        let toastCenter = ToastCenter()
        let manager = AuthManager(
            service: FailingAuthService(
                restoreError: AuthServiceError.transport(.noInternet),
                cachedSession: .fixtureSession
            ),
            toastCenter: toastCenter
        )

        await manager.restoreSession()

        #expect(manager.isAuthenticated)
        #expect(manager.currentUser == .fixture)
        #expect(toastCenter.message == "No internet connection. Check your network and try again.")
    }

    @Test("restore session keeps cached session on backend 500")
    func testRestoreSessionKeepsCachedSessionOnServerError() async {
        let toastCenter = ToastCenter()
        let manager = AuthManager(
            service: FailingAuthService(
                restoreError: AuthServiceError.server(statusCode: 500, message: "Internal server error"),
                cachedSession: .fixtureSession
            ),
            toastCenter: toastCenter
        )

        await manager.restoreSession()

        #expect(manager.isAuthenticated)
        #expect(manager.currentUser == .fixture)
        #expect(toastCenter.message == "Server error. Try again later.")
    }

    @Test("restore session keeps cached session on rate limit")
    func testRestoreSessionKeepsCachedSessionOnRateLimit() async {
        let toastCenter = ToastCenter()
        let manager = AuthManager(
            service: FailingAuthService(
                restoreError: AuthServiceError.rateLimited(requestId: "backend-429", message: "Too many attempts", retryAfter: 5),
                cachedSession: .fixtureSession
            ),
            toastCenter: toastCenter
        )

        await manager.restoreSession()

        #expect(manager.isAuthenticated)
        #expect(manager.currentUser == .fixture)
        #expect(toastCenter.message == "Too many attempts. Please wait a bit and try again.")
    }

    @Test("restore session does not keep cached session on unauthorized")
    func testRestoreSessionUnauthorizedDoesNotKeepCachedSession() async {
        let toastCenter = ToastCenter()
        let manager = AuthManager(
            service: FailingAuthService(
                restoreError: AuthServiceError.unauthorized(requestId: "backend-401"),
                cachedSession: .fixtureSession
            ),
            toastCenter: toastCenter
        )

        await manager.restoreSession()

        #expect(manager.isAuthenticated == false)
        #expect(manager.currentUser == nil)
        #expect(toastCenter.message == "Your session expired. Sign in again.")
    }

    @Test("request cancelled error does not show toast")
    func testRestoreSessionCancelledRequestSuppressesToast() async {
        let toastCenter = ToastCenter()
        let manager = AuthManager(
            service: FailingAuthService(restoreError: AuthServiceError.transport(.cancelled)),
            toastCenter: toastCenter
        )

        await manager.restoreSession()

        #expect(toastCenter.isPresented == false)
        #expect(toastCenter.message == nil)
        #expect(manager.errorMessage == nil)
    }

    @Test("dismiss toast clears auth feedback")
    func testDismissToastClearsFeedback() {
        let toastCenter = ToastCenter()
        let manager = AuthManager(service: FailingAuthService(), toastCenter: toastCenter)
        toastCenter.message = "Server error. Try again later."
        toastCenter.isPresented = true
        manager.errorMessage = "Server error. Try again later."

        manager.dismissToast()

        #expect(toastCenter.isPresented == false)
        #expect(toastCenter.message == nil)
        #expect(manager.errorMessage == nil)
    }

    @Test("restore session ignores concurrent invocation while busy")
    func testRestoreSessionIgnoresConcurrentInvocation() async {
        let service = SuspendedRestoreAuthService()
        let manager = AuthManager(service: service, toastCenter: ToastCenter())

        let firstTask = Task { await manager.restoreSession() }
        await service.waitUntilRestoreStarted()
        await manager.restoreSession()
        await service.finishRestore()
        await firstTask.value

        let restoreCalls = await service.restoreCalls
        #expect(restoreCalls == 1)
    }

    @Test("logout triggers session changed callback with nil")
    func testLogoutTriggersSessionChangedCallback() async {
        let service = LogoutTrackingAuthService()
        let manager = AuthManager(service: service, toastCenter: ToastCenter())
        var callbackArgument: AuthUser?
        var callbackCalls = 0

        manager.status = .authenticated
        manager.currentUser = .fixture

        manager.configure(onSessionChanged: { user in
            callbackCalls += 1
            callbackArgument = user
        })

        await manager.logout()

        #expect(await service.logoutCalls == 1)
        #expect(callbackCalls == 1)
        #expect(callbackArgument == nil)
    }

    // A3: явный logout должен забыть кэш user-скоупа, иначе resilience-блок
    // synchronizeDataScope переоткроет user-стор при следующем switch.
    @Test("logout clears cached user scope so app rebinds to guest")
    func testLogoutClearsScopeCache() async {
        let service = LogoutTrackingAuthService()
        let manager = AuthManager(service: service, toastCenter: ToastCenter())
        ScopeCache.save(.user(id: "user-logout"))
        manager.status = .authenticated
        manager.currentUser = .fixture

        var callbackArgument: AuthUser? = .fixture
        manager.configure(onSessionChanged: { user in
            callbackArgument = user
        })

        await manager.logout()

        #expect(callbackArgument == nil)
        #expect(ScopeCache.lastKnownUserID() == nil)

        ScopeCache.clearUserID()
    }

    // A3 (security-баг 2026-06-16): 401 на /me в рантайме = терминальный force-signout.
    // Должен вызвать onSessionChanged(nil) (ребинд на guest) + очистить кэш user-скоупа,
    // иначе данные прежнего пользователя остаются видимы после «continue as guest».
    @Test("unauthorized on reload performs terminal sign-out")
    func testUnauthorizedReloadTriggersTerminalSignOut() async {
        let service = FailingAuthService(restoreError: AuthServiceError.unauthorized(requestId: "backend-401"))
        let manager = AuthManager(service: service, toastCenter: ToastCenter())
        ScopeCache.save(.user(id: "user-401"))
        manager.status = .authenticated
        manager.currentUser = .fixture

        var callbackArgument: AuthUser? = .fixture
        var callbackCalls = 0
        manager.configure(onSessionChanged: { user in
            callbackCalls += 1
            callbackArgument = user
        })

        await manager.reloadCurrentUser()

        #expect(callbackCalls == 1)
        #expect(callbackArgument == nil)
        #expect(manager.status == .signedOut)
        #expect(manager.currentUser == nil)
        #expect(ScopeCache.lastKnownUserID() == nil)

        ScopeCache.clearUserID()
    }

    @Test("logout proceeds while busy if session is authenticated")
    func testLogoutProceedsWhenBusyAuthenticated() async {
        let service = LogoutTrackingAuthService()
        let manager = AuthManager(service: service, toastCenter: ToastCenter())
        manager.status = .authenticated
        manager.currentUser = .fixture
        manager.isBusy = true

        await manager.logout()

        #expect(await service.logoutCalls == 1)
        #expect(manager.status == .signedOut)
        #expect(manager.currentUser == nil)
    }

    @Test("reload current user result is ignored after logout")
    func testReloadCurrentUserResultIgnoredAfterLogout() async {
        let service = SuspendedCurrentUserAuthService()
        let manager = AuthManager(service: service, toastCenter: ToastCenter())
        manager.status = .authenticated
        manager.currentUser = .fixture

        let reloadTask = Task { await manager.reloadCurrentUser() }
        await service.waitUntilCurrentUserRequested()
        await manager.logout()
        await service.resumeCurrentUser(with: .otherFixture)
        await reloadTask.value

        #expect(manager.status == .signedOut)
        #expect(manager.currentUser == nil)
    }

    @Test("200 OK from auth apple switches app into authenticated state")
    func testSignInSuccessAuthenticatesUser() async {
        let service = SignInAuthService(result: .success(.fixtureSession))
        let manager = AuthManager(
            service: service,
            toastCenter: ToastCenter(),
            authorizationExtractor: StubAppleAuthorizationExtractor()
        )
        manager.configure(authConfiguration: AuthConfiguration(baseURL: URL(string: "https://api.example.com/api/v1")!, region: .de))

        manager.markAppleSignInStarted()
        await manager.signIn(with: .failure(AuthServiceError.unconfigured))

        #expect(manager.isAuthenticated)
        #expect(manager.currentUser == .fixture)
        #expect(manager.errorMessage == nil)
        #expect(await service.signInCalls == 1)
    }

    @Test("parse failure after 200 is not mapped as no internet")
    func testSignInDecodingFailureIsNotOffline() async {
        let toastCenter = ToastCenter()
        let manager = AuthManager(
            service: SignInAuthService(result: .failure(AuthServiceError.decodingFailed(requestId: "backend-auth-1"))),
            toastCenter: toastCenter,
            authorizationExtractor: StubAppleAuthorizationExtractor()
        )

        manager.markAppleSignInStarted()
        await manager.signIn(with: .failure(AuthServiceError.unconfigured))

        #expect(toastCenter.message == "Auth response parse failed. Try again.")
        #expect(manager.errorMessage == "Auth response parse failed. Try again.")
    }

    @Test("401 on auth apple shows Apple verification failure instead of session expired")
    func testSignInUnauthorizedShowsAppleVerificationMessage() async {
        let toastCenter = ToastCenter()
        let manager = AuthManager(
            service: SignInAuthService(result: .failure(AuthServiceError.unauthorized(requestId: "backend-auth-401"))),
            toastCenter: toastCenter,
            authorizationExtractor: StubAppleAuthorizationExtractor()
        )

        manager.markAppleSignInStarted()
        await manager.signIn(with: .failure(AuthServiceError.unconfigured))

        #expect(toastCenter.message == "Could not verify your Apple account. Try again.")
        #expect(manager.errorMessage == "Could not verify your Apple account. Try again.")
    }

    @Test("503 on auth apple shows Apple service unavailable message")
    func testSignInServiceUnavailableShowsAppleServiceMessage() async {
        let toastCenter = ToastCenter()
        let manager = AuthManager(
            service: SignInAuthService(result: .failure(AuthServiceError.server(statusCode: 503, message: "JWKS unavailable", requestId: "backend-auth-503"))),
            toastCenter: toastCenter,
            authorizationExtractor: StubAppleAuthorizationExtractor()
        )

        manager.markAppleSignInStarted()
        await manager.signIn(with: .failure(AuthServiceError.unconfigured))

        let expected = String(
            localized: "auth.error.apple_service_unavailable",
            defaultValue: "Apple sign-in service is temporarily unavailable. Try again later.",
            comment: "Apple auth service unavailable toast"
        )
        #expect(toastCenter.message == expected)
        #expect(manager.errorMessage == expected)
    }

    @Test("token persistence failure after 200 is not mapped as no internet")
    func testSignInTokenPersistenceFailureIsNotOffline() async {
        let toastCenter = ToastCenter()
        let manager = AuthManager(
            service: SignInAuthService(result: .failure(AuthServiceError.tokenPersistenceFailed("Keychain save failed."))),
            toastCenter: toastCenter,
            authorizationExtractor: StubAppleAuthorizationExtractor()
        )

        manager.markAppleSignInStarted()
        await manager.signIn(with: .failure(AuthServiceError.unconfigured))

        #expect(toastCenter.message == "Token persistence failed. Signed in, but failed to save your session.")
        #expect(manager.errorMessage == "Token persistence failed. Signed in, but failed to save your session.")
    }

    @Test("post login bootstrap failure does not clear successful session")
    func testPostLoginBootstrapFailureKeepsAuthenticatedState() async {
        let toastCenter = ToastCenter()
        let service = SignInAuthService(result: .success(.fixtureSession))
        let manager = AuthManager(
            service: service,
            toastCenter: toastCenter,
            authorizationExtractor: StubAppleAuthorizationExtractor()
        )
        manager.configure(onPostLoginBootstrap: { _ in
            throw AuthServiceError.transport(.noInternet)
        })

        manager.markAppleSignInStarted()
        await manager.signIn(with: .failure(AuthServiceError.unconfigured))

        #expect(manager.isAuthenticated)
        #expect(manager.currentUser == .fixture)
        #expect(toastCenter.message == "Post-login bootstrap failed. Your session is active.")
    }

    @Test("bootstrap unauthorized maps to wrong backend namespace and keeps session")
    func testPostLoginBootstrapUnauthorizedMapsToNamespaceError() async {
        let toastCenter = ToastCenter()
        let service = SignInAuthService(result: .success(.fixtureSession))
        let manager = AuthManager(
            service: service,
            toastCenter: toastCenter,
            authorizationExtractor: StubAppleAuthorizationExtractor()
        )
        manager.configure(onPostLoginBootstrap: { _ in
            throw AuthServiceError.unauthorized(requestId: "backend-me-1")
        })

        manager.markAppleSignInStarted()
        await manager.signIn(with: .failure(AuthServiceError.unconfigured))

        #expect(manager.isAuthenticated)
        #expect(toastCenter.message == "Signed in, but the session belongs to a different backend or region.")
    }

    @Test("double tap does not start two login flows")
    func testDoubleTapDoesNotStartTwoLoginFlows() async {
        let service = DelayedSignInAuthService()
        let manager = AuthManager(
            service: service,
            toastCenter: ToastCenter(),
            authorizationExtractor: StubAppleAuthorizationExtractor()
        )

        manager.markAppleSignInStarted()
        manager.markAppleSignInStarted()

        let first = Task { await manager.signIn(with: .failure(AuthServiceError.unconfigured)) }
        let second = Task { await manager.signIn(with: .failure(AuthServiceError.unconfigured)) }

        await service.waitUntilStarted()
        await service.finish(with: .fixtureSession)
        await first.value
        await second.value

        #expect(await service.signInCalls == 1)
        #expect(manager.isAuthenticated)
    }
}

private struct FailingAuthService: AuthServiceProtocol {
    let restoreError: Error?
    let cachedSession: AuthSession?

    init(restoreError: Error? = nil, cachedSession: AuthSession? = nil) {
        self.restoreError = restoreError
        self.cachedSession = cachedSession
    }

    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession {
        throw restoreError ?? AuthServiceError.unconfigured
    }

    func restoreSession() async throws -> AuthSession? {
        if let restoreError {
            throw restoreError
        }
        return nil
    }

    func lastKnownSession() async -> AuthSession? {
        cachedSession
    }

    func currentUser() async throws -> AuthUser {
        throw restoreError ?? AuthServiceError.unconfigured
    }

    func logout() async {}

    func accessTokenExpiryDate() async -> Date? {
        nil
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        throw restoreError ?? AuthServiceError.unconfigured
    }
}

private actor SignInAuthService: AuthServiceProtocol {
    private let result: Result<AuthSession, Error>
    private(set) var signInCalls = 0

    init(result: Result<AuthSession, Error>) {
        self.result = result
    }

    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession {
        signInCalls += 1
        switch result {
        case .success(let session):
            return session
        case .failure(let error):
            throw error
        }
    }

    func restoreSession() async throws -> AuthSession? { nil }
    func lastKnownSession() async -> AuthSession? { nil }
    func currentUser() async throws -> AuthUser { throw AuthServiceError.unconfigured }
    func logout() async {}
    func accessTokenExpiryDate() async -> Date? { .now.addingTimeInterval(600) }
    func accessToken(forceRefresh: Bool) async throws -> String { throw AuthServiceError.unconfigured }
}

private actor DelayedSignInAuthService: AuthServiceProtocol {
    private(set) var signInCalls = 0
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var resultContinuation: CheckedContinuation<AuthSession, Error>?

    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession {
        signInCalls += 1
        startedContinuation?.resume()
        return try await withCheckedThrowingContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func restoreSession() async throws -> AuthSession? { nil }
    func lastKnownSession() async -> AuthSession? { nil }
    func currentUser() async throws -> AuthUser { throw AuthServiceError.unconfigured }
    func logout() async {}
    func accessTokenExpiryDate() async -> Date? { .now.addingTimeInterval(600) }
    func accessToken(forceRefresh: Bool) async throws -> String { throw AuthServiceError.unconfigured }

    func waitUntilStarted() async {
        if signInCalls > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func finish(with session: AuthSession) {
        resultContinuation?.resume(returning: session)
        resultContinuation = nil
    }
}

private struct StubAppleAuthorizationExtractor: AppleAuthorizationExtracting {
    func extract(from authorization: Result<ASAuthorization, Error>) throws -> AppleAuthorizationPayload {
        AppleAuthorizationPayload(
            identityToken: "identity-token",
            email: "sid@example.com",
            firstName: "Sid",
            lastName: "Orkin"
        )
    }
}

private actor SuspendedRestoreAuthService: AuthServiceProtocol {
    private(set) var restoreCalls = 0
    private var restoreStartedContinuation: CheckedContinuation<Void, Never>?
    private var restoreFinishContinuation: CheckedContinuation<Void, Never>?

    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession {
        throw AuthServiceError.unconfigured
    }

    func restoreSession() async throws -> AuthSession? {
        restoreCalls += 1
        restoreStartedContinuation?.resume()
        await withCheckedContinuation { continuation in
            restoreFinishContinuation = continuation
        }
        return nil
    }

    func currentUser() async throws -> AuthUser {
        throw AuthServiceError.unconfigured
    }

    func lastKnownSession() async -> AuthSession? {
        nil
    }

    func logout() async {}

    func accessTokenExpiryDate() async -> Date? {
        nil
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        throw AuthServiceError.unconfigured
    }

    func waitUntilRestoreStarted() async {
        if restoreCalls > 0 {
            return
        }

        await withCheckedContinuation { continuation in
            restoreStartedContinuation = continuation
        }
    }

    func finishRestore() {
        restoreFinishContinuation?.resume()
        restoreFinishContinuation = nil
    }
}

private actor LogoutTrackingAuthService: AuthServiceProtocol {
    private(set) var logoutCalls = 0

    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession {
        throw AuthServiceError.unconfigured
    }

    func restoreSession() async throws -> AuthSession? {
        nil
    }

    func lastKnownSession() async -> AuthSession? {
        nil
    }

    func currentUser() async throws -> AuthUser {
        throw AuthServiceError.unconfigured
    }

    func logout() async {
        logoutCalls += 1
    }

    func accessTokenExpiryDate() async -> Date? {
        nil
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        throw AuthServiceError.unconfigured
    }
}

private actor SuspendedCurrentUserAuthService: AuthServiceProtocol {
    private var didRequestCurrentUser = false
    private var currentUserStartedContinuation: CheckedContinuation<Void, Never>?
    private var currentUserResultContinuation: CheckedContinuation<AuthUser, Never>?
    private(set) var logoutCalls = 0

    func signInWithApple(identityToken: String, email: String?, firstName: String?, lastName: String?) async throws -> AuthSession {
        throw AuthServiceError.unconfigured
    }

    func restoreSession() async throws -> AuthSession? {
        nil
    }

    func lastKnownSession() async -> AuthSession? {
        nil
    }

    func currentUser() async throws -> AuthUser {
        didRequestCurrentUser = true
        currentUserStartedContinuation?.resume()
        return await withCheckedContinuation { continuation in
            currentUserResultContinuation = continuation
        }
    }

    func logout() async {
        logoutCalls += 1
    }

    func accessTokenExpiryDate() async -> Date? {
        Date().addingTimeInterval(600)
    }

    func accessToken(forceRefresh: Bool) async throws -> String {
        throw AuthServiceError.unconfigured
    }

    func waitUntilCurrentUserRequested() async {
        if didRequestCurrentUser {
            return
        }
        await withCheckedContinuation { continuation in
            currentUserStartedContinuation = continuation
        }
    }

    func resumeCurrentUser(with user: AuthUser) {
        currentUserResultContinuation?.resume(returning: user)
        currentUserResultContinuation = nil
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

    static let otherFixture = AuthUser(
        id: "user-2",
        email: "other@example.com",
        emailVerified: true,
        firstName: "Other",
        lastName: "User",
        fullName: "Other User",
        avatarUrl: nil,
        lastLoginAt: nil
    )
}

private extension AuthSession {
    static let fixtureSession = AuthSession(
        user: .fixture,
        accessTokenExpiresAt: .now.addingTimeInterval(900),
        metadata: AuthResponseMetadata(
            statusCode: 200,
            requestId: "backend-auth-1",
            clientRequestId: "client-auth-1",
            durationMilliseconds: 20
        ),
        source: .appleSignIn
    )
}
