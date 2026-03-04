//
//  RestoreCandidateTelemetry.swift
//  millio
//
//  Created by Александр Сидоркин on 04.03.2026.
//

import Foundation

enum RestoreCandidateStage: String {
    case download
    case preflight
    case restore
}

enum RestoreCandidateOutcome: String {
    case ready
    case skip
    case block
    case success
}

enum RestoreCandidateReason: String {
    case missingRecordOrAsset = "missing_record_or_asset"
    case legacyPayload = "legacy_payload"
    case envelopeValid = "envelope_valid"
    case corruptedEnvelope = "corrupted_envelope"
    case incompatibleEnvelopeVersion = "incompatible_envelope_version"
    case passphraseRequired = "passphrase_required"
    case missingKDF = "missing_kdf"
    case unsupportedEncryption = "unsupported_encryption"
    case unsupportedCompression = "unsupported_compression"
    case restored = "restored"
    case backupCorrupted = "backup_corrupted"
    case incompatibleSchema = "incompatible_schema"
    case runtimeSkip = "runtime_skip"
    case iCloudUnavailable = "icloud_unavailable"
    case keychainUnavailable = "keychain_unavailable"
    case restoreFailed = "restore_failed"
    case backupTransportFailed = "backup_transport_failed"
    case unknownError = "unknown_error"
    case networkUnavailable = "network_unavailable"

    static func skipReason(for error: AppError) -> RestoreCandidateReason {
        switch error {
        case .backupCorrupted:
            return .backupCorrupted
        case .incompatibleSchemaVersion:
            return .incompatibleSchema
        default:
            return .runtimeSkip
        }
    }

    static func blockReason(for error: AppError) -> RestoreCandidateReason {
        switch error {
        case .iCloudUnavailable:
            return .iCloudUnavailable
        case .restoreFailed(let message):
            if message.contains("парольной фразой") {
                return .passphraseRequired
            }
            if message.contains("не может быть расшифрован") {
                return .keychainUnavailable
            }
            return .restoreFailed
        case .backupFailed:
            return .backupTransportFailed
        case .unknown:
            return .unknownError
        case .backupCorrupted:
            return .backupCorrupted
        case .incompatibleSchemaVersion:
            return .incompatibleSchema
        case .networkUnavailable:
            return .networkUnavailable
        }
    }
}
