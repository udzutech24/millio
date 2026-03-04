import Testing
@testable import millio

struct AppLockFailureCodeTests {
    @Test("AppLockFailureCode maps to AppError.securityFailed with expected user message")
    func testAppErrorMapping() {
        #expect(AppLockFailureCode.invalidPinFormat.appError == .securityFailed("PIN-код должен состоять из 4 цифр"))
        #expect(AppLockFailureCode.keychainPinUpdateFailed.appError == .securityFailed("Не удалось обновить PIN-код"))
        #expect(AppLockFailureCode.keychainPinSaveFailed.appError == .securityFailed("Не удалось сохранить PIN-код"))
        #expect(
            AppLockFailureCode.secureRandomPinGenerationFailed.appError
                == .securityFailed("Не удалось сгенерировать безопасный PIN")
        )
    }
}
