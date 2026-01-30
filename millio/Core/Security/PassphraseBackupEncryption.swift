//
//  PassphraseBackupEncryption.swift
//  millio
//
//  Created by Александр Сидоркин on 30.01.2026.
//

import Foundation
import CryptoKit
import CommonCrypto

/// Шифрование backup с использованием парольной фразы (чтобы restore работал после переустановки/на новом устройстве).
/// Ключ derive'ится через PBKDF2(HMAC-SHA256) + random salt, далее шифруем AES-GCM.
struct PassphraseBackupEncryption {
    static let defaultIterations = 120_000
    
    static func encrypt(_ data: Data, passphrase: String, iterations: Int = defaultIterations) throws -> (encrypted: Data, kdf: BackupKDFInfo) {
        let normalizedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPassphrase.isEmpty else {
            throw AppError.backupFailed("Парольная фраза пустая")
        }
        
        let salt = try Data.randomBytes(count: 16)
        let key = try deriveKey(passphrase: normalizedPassphrase, salt: salt, iterations: iterations)
        
        let sealedBox = try AES.GCM.seal(data, using: key)
        
        var encryptedData = Data()
        encryptedData.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
        encryptedData.append(sealedBox.ciphertext)
        encryptedData.append(sealedBox.tag)
        
        let kdf = BackupKDFInfo(
            algorithm: "pbkdf2-hmac-sha256",
            iterations: iterations,
            saltBase64: salt.base64EncodedString()
        )
        
        return (encryptedData, kdf)
    }
    
    static func decrypt(_ data: Data, passphrase: String, kdf: BackupKDFInfo) throws -> Data {
        let normalizedPassphrase = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPassphrase.isEmpty else {
            throw AppError.restoreFailed("Нужна парольная фраза для расшифровки backup")
        }
        
        guard kdf.algorithm == "pbkdf2-hmac-sha256",
              let salt = Data(base64Encoded: kdf.saltBase64),
              kdf.iterations > 0 else {
            throw AppError.backupCorrupted
        }
        
        let key = try deriveKey(passphrase: normalizedPassphrase, salt: salt, iterations: kdf.iterations)
        
        guard data.count > 12 else { throw AppError.backupCorrupted }
        let nonceData = data.prefix(12)
        let ciphertextAndTag = data.dropFirst(12)
        guard ciphertextAndTag.count > 16 else { throw AppError.backupCorrupted }
        
        let ciphertext = ciphertextAndTag.dropLast(16)
        let tag = ciphertextAndTag.suffix(16)
        
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        
        do {
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw AppError.restoreFailed("Не удалось расшифровать backup (неверная парольная фраза или поврежденные данные)")
        }
    }
    
    private static func deriveKey(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passwordData = Data(passphrase.utf8)
        var derivedKey = Data(count: 32)
        let derivedKeyCount = derivedKey.count
        
        let status = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: Int8.self).baseAddress,
                        passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.bindMemory(to: UInt8.self).baseAddress,
                        derivedKeyCount
                    )
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw AppError.backupFailed("Не удалось получить ключ шифрования из парольной фразы")
        }
        
        return SymmetricKey(data: derivedKey)
    }
}

private extension Data {
    static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw AppError.backupFailed("Не удалось сгенерировать случайные байты для backup")
        }
        return data
    }
}
