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

    // Прежний тест сравнивал `appError` с английскими литералами. Ожидание было неверным:
    // это сообщение уходит прямо в UI, поэтому оно обязано быть локализованным, а тест на
    // английский литерал фиксировал баг D9. Проверяем стабильные ключи и непустой текст.
    @Test("RestoreFailureCode maps to AppError.restoreFailed with a localized, non-empty message")
    func testAppErrorMapping() {
        #expect(RestoreFailureCode.backupNotFound.localizationKey == "backup.restore.failure.not_found")
        #expect(RestoreFailureCode.passphraseRequired.localizationKey == "backup.restore.failure.passphrase_required")
        #expect(RestoreFailureCode.keychainUnavailable.localizationKey == "backup.restore.failure.keychain_unavailable")
        #expect(RestoreFailureCode.keychainKeyMissingOnDevice.localizationKey == "backup.restore.failure.keychain_key_missing")
        #expect(RestoreFailureCode.passphraseDecryptFailed.localizationKey == "backup.restore.failure.passphrase_wrong")

        for code in [RestoreFailureCode.backupNotFound, .passphraseRequired, .keychainUnavailable, .keychainKeyMissingOnDevice, .passphraseDecryptFailed] {
            #expect(code.appError == .restoreFailed(code.message))
            #expect(code.message.isEmpty == false)
        }
    }

    @Test("Разные причины отказа не схлопываются в один текст")
    func testFailureMessagesAreDistinct() {
        let messages = [
            RestoreFailureCode.passphraseDecryptFailed.message,
            RestoreFailureCode.keychainKeyMissingOnDevice.message,
            RestoreFailureCode.preRestoreSnapshotFailed.message,
            RestoreFailureCode.rollbackFailed.message
        ]

        #expect(Set(messages).count == messages.count)
    }
}
