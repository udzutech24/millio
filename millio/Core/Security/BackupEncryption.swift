//
//  BackupEncryption.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import CryptoKit
import Security

/// Протокол для шифрования backup
protocol BackupEncryptionProtocol {
    func encrypt(_ data: Data) throws -> Data
    func decrypt(_ data: Data) throws -> Data
}

/// Шифрование backup с использованием Keychain для хранения ключа
struct KeychainBackupEncryption: BackupEncryptionProtocol {
    private let keychain = Keychain(service: "com.millio.backup")
    private let keyTag = "backup.encryption.key"
    
    func encrypt(_ data: Data) throws -> Data {
        let key = try getOrCreateKey()
        
        // Используем AES-GCM для шифрования
        let sealedBox = try AES.GCM.seal(data, using: key)
        
        // Объединяем nonce, ciphertext и tag
        var encryptedData = Data()
        encryptedData.append(sealedBox.nonce.withUnsafeBytes { Data($0) })
        encryptedData.append(sealedBox.ciphertext)
        // tag всегда присутствует в AES.GCM.SealedBox
        encryptedData.append(sealedBox.tag)
        
        return encryptedData
    }
    
    func decrypt(_ data: Data) throws -> Data {
        let key = try getKey()
        
        // Извлекаем nonce, ciphertext и tag
        guard data.count > 12 else {
            throw AppError.backupCorrupted
        }
        
        let nonceData = data.prefix(12)
        let ciphertextAndTag = data.dropFirst(12)
        
        guard ciphertextAndTag.count > 16 else {
            throw AppError.backupCorrupted
        }
        
        let ciphertext = ciphertextAndTag.dropLast(16)
        let tag = ciphertextAndTag.suffix(16)
        
        let nonce = try AES.GCM.Nonce(data: nonceData)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        
        return try AES.GCM.open(sealedBox, using: key)
    }
    
    private func getOrCreateKey() throws -> SymmetricKey {
        if let keyData = keychain[data: keyTag] {
            return SymmetricKey(data: keyData)
        } else {
            let key = SymmetricKey(size: .bits256)
            try keychain.setData(key.withUnsafeBytes { Data($0) }, for: keyTag)
            return key
        }
    }
    
    private func getKey() throws -> SymmetricKey {
        guard let keyData = keychain[data: keyTag] else {
            throw RestoreFailureCode.keychainKeyMissingOnDevice.appError
        }
        return SymmetricKey(data: keyData)
    }
}

// MARK: - Keychain Helper

private struct Keychain {
    let service: String
    private let accessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    
    subscript(data key: String) -> Data? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true
            ]
            
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            
            guard status == errSecSuccess,
                  let data = result as? Data else {
                return nil
            }
            
            return data
        }
        nonmutating set {}
    }
    
    func setData(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else {
                throw BackupFailureCode.keychainKeyUpdateFailed.appError
            }
        } else {
            var newQuery = query
            newQuery.merge(attributes) { _, new in new }
            newQuery[kSecAttrAccessible as String] = accessible
            let status = SecItemAdd(newQuery as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw BackupFailureCode.keychainKeySaveFailed.appError
            }
        }
    }
    
    func delete(_ key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BackupFailureCode.keychainKeyDeleteFailed.appError
        }
    }
}
