import Foundation
import Testing
@testable import millio

struct PassphraseBackupEncryptionTests {
    @Test("Passphrase decrypt rejects out-of-range PBKDF2 iterations")
    func testDecryptRejectsIterationsOutOfRange() {
        let salt = Data(repeating: 7, count: 16).base64EncodedString()
        let payload = Data(repeating: 1, count: 64)
        
        let tooSmall = BackupKDFInfo(
            algorithm: "pbkdf2-hmac-sha256",
            iterations: PassphraseBackupEncryption.minIterations - 1,
            saltBase64: salt
        )
        
        let tooLarge = BackupKDFInfo(
            algorithm: "pbkdf2-hmac-sha256",
            iterations: PassphraseBackupEncryption.maxIterations + 1,
            saltBase64: salt
        )
        
        #expect(throws: AppError.backupCorrupted) {
            _ = try PassphraseBackupEncryption.decrypt(payload, passphrase: "pass", kdf: tooSmall)
        }
        
        #expect(throws: AppError.backupCorrupted) {
            _ = try PassphraseBackupEncryption.decrypt(payload, passphrase: "pass", kdf: tooLarge)
        }
    }
}
