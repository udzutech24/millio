import AuthenticationServices
import Foundation
import Testing
@testable import millio

@MainActor
struct AuthManagerTests {
    @Test("restore session shows user friendly toast for backend 500")
    func testRestoreSessionMapsBackend500ToToast() async {
        let toastCenter = ToastCenter()
        let manager = AuthManager(
            service: FailingAuthService(restoreError: AuthServiceError.backend(statusCode: 500, message: "Internal server error")),
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
            service: FailingAuthService(restoreError: AuthServiceError.transport("The Internet connection appears to be offline.")),
            toastCenter: toastCenter
        )

        await manager.restoreSession()

        #expect(toastCenter.isPresented)
        #expect(toastCenter.message == "No internet connection. Check your network and try again.")
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
