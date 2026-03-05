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
        #expect(RestoreFailureCode.backupNotFound.appError == .restoreFailed("Backup not found in iCloud"))
        #expect(
            RestoreFailureCode.passphraseRequired.appError
                == .restoreFailed("Backup is encrypted with a passphrase. Enter the passphrase and try again.")
        )
        #expect(
            RestoreFailureCode.keychainUnavailable.appError
                == .restoreFailed("Backup is encrypted and cannot be decrypted on this device")
        )
        #expect(
            RestoreFailureCode.keychainKeyMissingOnDevice.appError
                == .restoreFailed("Backup encryption key is missing on this device")
        )
        #expect(
            RestoreFailureCode.passphraseDecryptFailed.appError
                == .restoreFailed("Failed to decrypt backup (wrong passphrase or corrupted data)")
        )
    }
}
