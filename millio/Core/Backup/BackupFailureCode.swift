//
//  BackupFailureCode.swift
//  millio
//
//  Created by Александр Сидоркин on 04.03.2026.
//

import Foundation

enum BackupFailureCode {
    case compressionInitializationFailed
    case compressionEncodeFailed
    case envelopeHeaderTooLarge
    case metadataSerializationFailed
    case modelExportUnexpectedFormat(String)
    case keychainKeyUpdateFailed
    case keychainKeySaveFailed
    case keychainKeyDeleteFailed
    case passphraseEmpty
    case passphraseKeyDerivationFailed
    case randomBytesGenerationFailed
    case cloudKitOperationFailed(String)

    var message: String {
        switch self {
        case .compressionInitializationFailed:
            return "Failed to initialize compression"
        case .compressionEncodeFailed:
            return "Failed to compress backup"
        case .envelopeHeaderTooLarge:
            return "Backup header is too large"
        case .metadataSerializationFailed:
            return "Failed to serialize backup metadata"
        case .modelExportUnexpectedFormat(let typeName):
            return "Model export '\(typeName)' returned an unexpected format"
        case .keychainKeyUpdateFailed:
            return "Failed to update backup encryption key"
        case .keychainKeySaveFailed:
            return "Failed to save backup encryption key"
        case .keychainKeyDeleteFailed:
            return "Failed to delete backup encryption key"
        case .passphraseEmpty:
            return "Passphrase is empty"
        case .passphraseKeyDerivationFailed:
            return "Failed to derive encryption key from passphrase"
        case .randomBytesGenerationFailed:
            return "Failed to generate random bytes for backup"
        case .cloudKitOperationFailed(let detail):
            let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDetail.isEmpty else {
                return "CloudKit backup operation failed"
            }
            return "CloudKit backup operation failed: \(trimmedDetail)"
        }
    }

    var appError: AppError {
        .backupFailed(message)
    }
}
