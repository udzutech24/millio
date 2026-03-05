import Testing
@testable import millio

struct AppLockFailureCodeTests {
    @Test("AppLockFailureCode maps to AppError.securityFailed with expected user message")
    func testAppErrorMapping() {
        #expect(AppLockFailureCode.invalidPinFormat.appError == .securityFailed("PIN must contain exactly 4 digits"))
        #expect(AppLockFailureCode.keychainPinUpdateFailed.appError == .securityFailed("Failed to update PIN"))
        #expect(AppLockFailureCode.keychainPinSaveFailed.appError == .securityFailed("Failed to save PIN"))
        #expect(
            AppLockFailureCode.secureRandomPinGenerationFailed.appError
                == .securityFailed("Failed to generate secure PIN")
        )
    }
}
