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

    /// Ключ каталога: сообщение уходит прямо в UI, поэтому английский литерал здесь — только fallback.
    var localizationKey: String {
        switch self {
        case .backupNotFound:
            return "backup.restore.failure.not_found"
        case .allCandidatesInvalid:
            return "backup.restore.failure.all_candidates_invalid"
        case .passphraseRequired:
            return "backup.restore.failure.passphrase_required"
        case .passphraseNeededForDecrypt:
            return "backup.restore.failure.passphrase_needed"
        case .passphraseDecryptFailed:
            return "backup.restore.failure.passphrase_wrong"
        case .keychainUnavailable:
            return "backup.restore.failure.keychain_unavailable"
        case .keychainKeyMissingOnDevice:
            return "backup.restore.failure.keychain_key_missing"
        case .decryptFailed:
            return "backup.restore.failure.decrypt_failed"
        case .preRestoreSnapshotFailed:
            return "backup.restore.failure.snapshot_failed"
        case .rollbackFailed:
            return "backup.restore.failure.rollback_failed"
        }
    }

    private var englishFallback: String {
        switch self {
        case .backupNotFound:
            return "No backup found in iCloud for this account"
        case .allCandidatesInvalid:
            return "None of the available backups could be read: they are damaged or incompatible"
        case .passphraseRequired:
            return "This backup is protected with a passphrase. Enter it and try again."
        case .passphraseNeededForDecrypt:
            return "A passphrase is required to decrypt this backup"
        case .passphraseDecryptFailed:
            return "Wrong passphrase, or the backup is damaged. Your data has not been changed."
        case .keychainUnavailable:
            return "This backup is tied to another device and cannot be decrypted here. Use a backup with a passphrase."
        case .keychainKeyMissingOnDevice:
            return "The encryption key for this backup is missing on this device. Restore is only possible with a passphrase backup."
        case .decryptFailed:
            return "Failed to decrypt the backup"
        case .preRestoreSnapshotFailed:
            return "Could not save a safety copy before restoring, so restore was cancelled. Your data has not been changed."
        case .rollbackFailed:
            return "Failed to roll back data after a restore error"
        }
    }

    /// Текст для пользователя. Раньше был английским литералом и уходил в UI как есть (D9).
    var message: String {
        BackupL10n.tr(localizationKey, fallback: englishFallback)
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
