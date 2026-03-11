import Testing
@testable import millio

struct BackupFailureCodeTests {
    @Test("BackupFailureCode maps to AppError.backupFailed with expected user message")
    func testAppErrorMapping() {
        #expect(BackupFailureCode.compressionInitializationFailed.appError == .backupFailed("Failed to initialize compression"))
        #expect(BackupFailureCode.compressionEncodeFailed.appError == .backupFailed("Failed to compress backup"))
        #expect(BackupFailureCode.envelopeHeaderTooLarge.appError == .backupFailed("Backup header is too large"))
        #expect(BackupFailureCode.metadataSerializationFailed.appError == .backupFailed("Failed to serialize backup metadata"))
        #expect(BackupFailureCode.keychainKeyUpdateFailed.appError == .backupFailed("Failed to update backup encryption key"))
        #expect(BackupFailureCode.keychainKeySaveFailed.appError == .backupFailed("Failed to save backup encryption key"))
        #expect(BackupFailureCode.keychainKeyDeleteFailed.appError == .backupFailed("Failed to delete backup encryption key"))
        #expect(BackupFailureCode.passphraseEmpty.appError == .backupFailed("Passphrase is empty"))
        #expect(
            BackupFailureCode.passphraseKeyDerivationFailed.appError
                == .backupFailed("Failed to derive encryption key from passphrase")
        )
        #expect(
            BackupFailureCode.randomBytesGenerationFailed.appError
                == .backupFailed("Failed to generate random bytes for backup")
        )
        #expect(
            BackupFailureCode.modelExportUnexpectedFormat("BadExportModel").appError
                == .backupFailed("Model export 'BadExportModel' returned an unexpected format")
        )
    }

    @Test("BackupFailureCode cloud mapping keeps stable prefix and trims detail")
    func testCloudMessageMapping() {
        #expect(
            BackupFailureCode.cloudKitOperationFailed("Network timeout").appError
                == .backupFailed("CloudKit backup operation failed: Network timeout")
        )
        #expect(
            BackupFailureCode.cloudKitOperationFailed("   ").appError
                == .backupFailed("CloudKit backup operation failed")
        )
        #expect(
            BackupFailureCode.cloudKitOperationFailed(
                "Error saving record to server: Cannot create new type AppBackup in production schema"
            ).appError
                == .backupFailed(
                    "CloudKit backup operation failed: CloudKit production schema is missing record type 'AppBackup'. Deploy the latest schema to production before using TestFlight or App Store builds."
                )
        )
        #expect(
            BackupFailureCode.cloudKitOperationFailed(
                "CloudKit production schema is missing record type 'AppBackup'. Deploy the latest schema to production before using TestFlight or App Store builds."
            ).appError
                == .backupFailed(
                    "CloudKit backup operation failed: CloudKit production schema is missing record type 'AppBackup'. Deploy the latest schema to production before using TestFlight or App Store builds."
                )
        )
    }
}
