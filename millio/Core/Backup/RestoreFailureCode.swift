//
//  RestoreFailureCode.swift
//  millio
//
//  Created by Александр Сидоркин on 04.03.2026.
//

import Foundation

/// Тяжесть исхода восстановления. `.critical` — пользователь остался без обоих состояний данных
/// (и старого, и нового); такие исходы нельзя глушить skip-логикой перебора кандидатов.
enum RestoreFailureSeverity {
    case recoverable
    case critical
}

/// Провал отката к до-restore снимку. Отдельный тип, а не `AppError`, намеренно: перебор кандидатов
/// в `BackupManager` ловит `AppError`/`TaggedRestoreFailure` и может «пропустить» ошибку, взяв снимок
/// постарше. Провал отката пропускать нельзя — он обязан дойти до пользователя как есть.
struct RestoreRollbackFailure: Error, LocalizedError {
    let underlyingDescription: String
    var severity: RestoreFailureSeverity { .critical }

    var errorDescription: String? {
        // Через BackupL10n, а не AppLocalization: каталог гарантирует RU/zh-Hans даже если ключ
        // ещё не доехал до Localizable.xcstrings — сообщение критического исхода не имеет права
        // выпадать в английский на русском устройстве.
        BackupL10n.tr(
            "backup.restore.failure.rollback_failed",
            fallback: "Failed to roll back data after a restore error. Do not delete the app: open Profile → Backup and restore from a version manually."
        )
    }

    var appError: AppError {
        .restoreFailed(errorDescription ?? underlyingDescription)
    }
}

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

    var severity: RestoreFailureSeverity {
        switch self {
        case .rollbackFailed:
            return .critical
        default:
            // Провал снимка происходит ДО деструктивной фазы — локальные данные целы.
            return .recoverable
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
