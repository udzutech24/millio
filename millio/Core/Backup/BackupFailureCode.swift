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
        if lowercaseDetail.contains("production schema"),
           let recordType = missingProductionRecordType(in: trimmedDetail) {
            return "CloudKit production schema is missing record type '\(recordType)'. Deploy the latest schema to production before using TestFlight or App Store builds."
        }

        if lowercaseDetail.contains("cannot create new type"),
           lowercaseDetail.contains("production schema") {
            return "CloudKit production schema is missing a required record type. Deploy the latest schema to production before using TestFlight or App Store builds."
        }

        if lowercaseDetail.contains("missing record type"),
           lowercaseDetail.contains("production schema") {
            if let recordType = missingQuotedRecordType(in: trimmedDetail) {
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

        if let markerRange = detail.range(of: marker),
           let suffixRange = detail.range(of: suffix, range: markerRange.upperBound..<detail.endIndex) {
            let recordType = detail[markerRange.upperBound..<suffixRange.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            return recordType.isEmpty ? nil : recordType
        }

        return missingQuotedRecordType(in: detail)
    }

    private static func missingQuotedRecordType(in detail: String) -> String? {
        let marker = "record type"
        guard let markerRange = detail.range(of: marker, options: [.caseInsensitive]) else {
            return nil
        }

        let suffix = detail[markerRange.upperBound...]
        guard let openingQuote = suffix.firstIndex(where: { $0 == "'" || $0 == "\"" }) else {
            return nil
        }
        let searchStart = detail.index(after: openingQuote)
        guard let closingQuote = detail[searchStart...].firstIndex(where: { $0 == detail[openingQuote] }) else {
            return nil
        }

        let recordType = detail[searchStart..<closingQuote].trimmingCharacters(in: .whitespacesAndNewlines)
        return recordType.isEmpty ? nil : recordType
    }
}
