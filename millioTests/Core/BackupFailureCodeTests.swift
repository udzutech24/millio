import Testing
@testable import millio

struct BackupFailureCodeTests {
    @Test("BackupFailureCode maps to AppError.backupFailed with expected user message")
    func testAppErrorMapping() {
        #expect(BackupFailureCode.compressionInitializationFailed.appError == .backupFailed("Ошибка инициализации сжатия"))
        #expect(BackupFailureCode.compressionEncodeFailed.appError == .backupFailed("Не удалось сжать backup"))
        #expect(BackupFailureCode.envelopeHeaderTooLarge.appError == .backupFailed("Слишком большой заголовок backup"))
        #expect(BackupFailureCode.keychainKeyUpdateFailed.appError == .backupFailed("Не удалось обновить ключ шифрования backup"))
        #expect(BackupFailureCode.keychainKeySaveFailed.appError == .backupFailed("Не удалось сохранить ключ шифрования backup"))
        #expect(BackupFailureCode.keychainKeyDeleteFailed.appError == .backupFailed("Не удалось удалить ключ шифрования backup"))
        #expect(BackupFailureCode.passphraseEmpty.appError == .backupFailed("Парольная фраза пустая"))
        #expect(
            BackupFailureCode.passphraseKeyDerivationFailed.appError
                == .backupFailed("Не удалось получить ключ шифрования из парольной фразы")
        )
        #expect(
            BackupFailureCode.randomBytesGenerationFailed.appError
                == .backupFailed("Не удалось сгенерировать случайные байты для backup")
        )
    }

    @Test("BackupFailureCode cloud mapping keeps stable prefix and trims detail")
    func testCloudMessageMapping() {
        #expect(
            BackupFailureCode.cloudKitOperationFailed("Network timeout").appError
                == .backupFailed("Ошибка CloudKit при работе с backup: Network timeout")
        )
        #expect(
            BackupFailureCode.cloudKitOperationFailed("   ").appError
                == .backupFailed("Ошибка CloudKit при работе с backup")
        )
    }
}
