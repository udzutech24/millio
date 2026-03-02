import LocalAuthentication
import Testing
@testable import millio

@Suite(.serialized)
struct AppLockBiometricAuthTests {
    @Test("Biometric auth uses biometric policy when available")
    func testAuthenticateUsesBiometricPolicy() async {
        let context = FakeAuthContext(
            biometryType: .faceID,
            canEvaluateResults: [
                .deviceOwnerAuthenticationWithBiometrics: .success,
                .deviceOwnerAuthentication: .success
            ],
            evaluateSuccess: true
        )

        AppLockBiometricAuth.contextFactory = { context }
        defer { AppLockBiometricAuth.contextFactory = { LAContext() } }

        #expect(AppLockBiometricAuth.canUseBiometrics() == true)
        let success = await AppLockBiometricAuth.authenticate(reason: "test")

        #expect(success == true)
        #expect(context.evaluatedPolicies == [.deviceOwnerAuthenticationWithBiometrics])
    }

    @Test("Biometric auth falls back to device auth when biometry is locked out")
    func testAuthenticateFallsBackWhenBiometryLockedOut() async {
        let lockoutError = NSError(domain: LAError.errorDomain, code: LAError.biometryLockout.rawValue)
        let context = FakeAuthContext(
            biometryType: .faceID,
            canEvaluateResults: [
                .deviceOwnerAuthenticationWithBiometrics: .failure(lockoutError),
                .deviceOwnerAuthentication: .success
            ],
            evaluateSuccess: true
        )

        AppLockBiometricAuth.contextFactory = { context }
        defer { AppLockBiometricAuth.contextFactory = { LAContext() } }

        #expect(AppLockBiometricAuth.canUseBiometrics() == true)
        let success = await AppLockBiometricAuth.authenticate(reason: "test")

        #expect(success == true)
        #expect(context.evaluatedPolicies == [.deviceOwnerAuthentication])
    }

    @Test("Biometric auth does not enable unlock when biometry is unavailable")
    func testNoBiometryDoesNotEnableUnlock() async {
        let notEnrolledError = NSError(domain: LAError.errorDomain, code: LAError.biometryNotEnrolled.rawValue)
        let context = FakeAuthContext(
            biometryType: .none,
            canEvaluateResults: [
                .deviceOwnerAuthenticationWithBiometrics: .failure(notEnrolledError),
                .deviceOwnerAuthentication: .success
            ],
            evaluateSuccess: true
        )

        AppLockBiometricAuth.contextFactory = { context }
        defer { AppLockBiometricAuth.contextFactory = { LAContext() } }

        #expect(AppLockBiometricAuth.canUseBiometrics() == false)
        let success = await AppLockBiometricAuth.authenticate(reason: "test")

        #expect(success == false)
        #expect(context.evaluatedPolicies.isEmpty == true)
    }
}

private final class FakeAuthContext: AppLockAuthContext {
    enum PolicyResult {
        case success
        case failure(NSError?)
    }

    var biometryType: LABiometryType
    var localizedCancelTitle: String?
    var evaluatedPolicies: [LAPolicy] = []

    private let canEvaluateResults: [LAPolicy: PolicyResult]
    private let evaluateSuccess: Bool

    init(
        biometryType: LABiometryType,
        canEvaluateResults: [LAPolicy: PolicyResult],
        evaluateSuccess: Bool
    ) {
        self.biometryType = biometryType
        self.canEvaluateResults = canEvaluateResults
        self.evaluateSuccess = evaluateSuccess
    }

    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        let result = canEvaluateResults[policy] ?? .failure(nil)
        switch result {
        case .success:
            return true
        case .failure(let nsError):
            error?.pointee = nsError
            return false
        }
    }

    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, Error?) -> Void) {
        evaluatedPolicies.append(policy)
        reply(evaluateSuccess, nil)
    }
}
