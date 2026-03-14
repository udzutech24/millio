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
}

private struct FailingAuthService: AuthServiceProtocol {
    let restoreError: Error?

    init(restoreError: Error? = nil) {
        self.restoreError = restoreError
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
