import Testing
@testable import millio

struct RestoreFailureCodeTests {
    @Test("RestoreFailureCode maps to stable telemetry reasons")
    func testReasonMapping() {
        #expect(RestoreFailureCode.passphraseRequired.reason == .passphraseRequired)
        #expect(RestoreFailureCode.passphraseNeededForDecrypt.reason == .passphraseRequired)
        #expect(RestoreFailureCode.passphraseDecryptFailed.reason == .restoreFailed)
        #expect(RestoreFailureCode.keychainUnavailable.reason == .keychainUnavailable)
        #expect(RestoreFailureCode.keychainKeyMissingOnDevice.reason == .keychainUnavailable)
        #expect(RestoreFailureCode.backupNotFound.reason == .restoreFailed)
        #expect(RestoreFailureCode.rollbackFailed.reason == .restoreFailed)
    }

    @Test("RestoreFailureCode maps to AppError.restoreFailed with expected user message")
    func testAppErrorMapping() {
        #expect(RestoreFailureCode.backupNotFound.appError == .restoreFailed("Backup не найден в iCloud"))
        #expect(
            RestoreFailureCode.passphraseRequired.appError
                == .restoreFailed("Backup зашифрован парольной фразой. Введите парольную фразу и повторите.")
        )
        #expect(
            RestoreFailureCode.keychainUnavailable.appError
                == .restoreFailed("Backup зашифрован и не может быть расшифрован на этом устройстве")
        )
        #expect(
            RestoreFailureCode.keychainKeyMissingOnDevice.appError
                == .restoreFailed("Ключ шифрования backup не найден на этом устройстве")
        )
        #expect(
            RestoreFailureCode.passphraseDecryptFailed.appError
                == .restoreFailed("Не удалось расшифровать backup (неверная парольная фраза или поврежденные данные)")
        )
    }
}
