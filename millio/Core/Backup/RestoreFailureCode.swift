//
//  RestoreFailureCode.swift
//  millio
//
//  Created by Александр Сидоркин on 04.03.2026.
//

import Foundation

enum RestoreFailureCode {
    case backupNotFound
    case allCandidatesInvalid
    case passphraseRequired
    case passphraseNeededForDecrypt
    case passphraseDecryptFailed
    case keychainUnavailable
    case keychainKeyMissingOnDevice
    case decryptFailed
    case preRestoreSnapshotFailed
    case rollbackFailed

    var message: String {
        switch self {
        case .backupNotFound:
            return "Backup not found in iCloud"
        case .allCandidatesInvalid:
            return "Failed to restore data: available backups are corrupted or incompatible"
        case .passphraseRequired:
            return "Backup is encrypted with a passphrase. Enter the passphrase and try again."
        case .passphraseNeededForDecrypt:
            return "A passphrase is required to decrypt this backup"
        case .passphraseDecryptFailed:
            return "Failed to decrypt backup (wrong passphrase or corrupted data)"
        case .keychainUnavailable:
            return "Backup is encrypted and cannot be decrypted on this device"
        case .keychainKeyMissingOnDevice:
            return "Backup encryption key is missing on this device"
        case .decryptFailed:
            return "Failed to decrypt backup"
        case .preRestoreSnapshotFailed:
            return "Failed to create pre-restore snapshot"
        case .rollbackFailed:
            return "Failed to roll back data after restore error"
        }
    }

    var reason: RestoreCandidateReason {
        switch self {
        case .backupNotFound, .allCandidatesInvalid, .decryptFailed, .passphraseDecryptFailed, .preRestoreSnapshotFailed, .rollbackFailed:
            return .restoreFailed
        case .passphraseRequired, .passphraseNeededForDecrypt:
            return .passphraseRequired
        case .keychainUnavailable, .keychainKeyMissingOnDevice:
            return .keychainUnavailable
        }
    }

    var appError: AppError {
        .restoreFailed(message)
    }
}
