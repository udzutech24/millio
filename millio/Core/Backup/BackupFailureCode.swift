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
            let trimmedDetail = Self.normalizedCloudKitDetail(detail)
            guard !trimmedDetail.isEmpty else {
                return "CloudKit backup operation failed"
            }
            return "CloudKit backup operation failed: \(trimmedDetail)"
        }
    }

    var appError: AppError {
        .backupFailed(message)
    }

    private static func normalizedCloudKitDetail(_ detail: String) -> String {
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDetail.isEmpty else {
            return ""
        }

        let lowercaseDetail = trimmedDetail.lowercased()
        if lowercaseDetail.contains("cannot create new type"),
           lowercaseDetail.contains("production schema") {
            if let recordType = missingProductionRecordType(in: trimmedDetail) {
                return "CloudKit production schema is missing record type '\(recordType)'. Deploy the latest schema to production before using TestFlight or App Store builds."
            }
            return "CloudKit production schema is missing a required record type. Deploy the latest schema to production before using TestFlight or App Store builds."
        }

        if lowercaseDetail.contains("not marked queryable") {
            return "CloudKit production schema is missing required queryable indexes for backup records. Deploy the latest schema indexes to production."
        }

        return trimmedDetail
    }

    private static func missingProductionRecordType(in detail: String) -> String? {
        let marker = "Cannot create new type "
        let suffix = " in production schema"

        guard let markerRange = detail.range(of: marker) else {
            return nil
        }

        let typeStart = markerRange.upperBound
        guard let suffixRange = detail.range(of: suffix, range: typeStart..<detail.endIndex) else {
            return nil
        }

        let recordType = detail[typeStart..<suffixRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return recordType.isEmpty ? nil : recordType
    }
}
