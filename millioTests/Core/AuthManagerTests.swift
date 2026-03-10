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
