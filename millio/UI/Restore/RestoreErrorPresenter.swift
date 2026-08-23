//
//  RestoreErrorPresenter.swift
//  millio
//
//  Created by Александр Сидоркин on 23.08.2026.
//

import Foundation

/// Единственный источник пользовательского текста ошибки восстановления.
/// `AppError.localizedDescription` — техническая английская строка («Restore failed: …»),
/// показывать её пользователю нельзя ни на одном языке (D9).
enum RestoreErrorPresenter {
    static func userMessage(for error: AppError) -> String {
        switch error {
        case .restoreFailed(let message), .backupFailed(let message):
            // Сообщение уже пришло локализованным из RestoreFailureCode / RestoreVerificationFailure /
            // RestoreRollbackFailure — второй раз переводить нечего.
            return message
        case .iCloudUnavailable:
            return BackupL10n.tr(
                "backup.restore.failure.icloud_unavailable",
                fallback: "iCloud is unavailable, so the backup cannot be read"
            )
        case .networkUnavailable:
            return BackupL10n.tr(
                "backup.restore.failure.network",
                fallback: "No connection to iCloud. Check the network and try again."
            )
        case .backupCorrupted:
            return BackupL10n.tr(
                "backup.restore.failure.corrupted",
                fallback: "This backup file is damaged and cannot be read. Try another version."
            )
        case .incompatibleSchemaVersion:
            return BackupL10n.tr(
                "backup.restore.failure.incompatible_schema",
                fallback: "The backup was created by a newer version of Millio. Update the app and try again."
            )
        case .backupRequiresSignIn:
            return BackupL10n.tr(
                "backup.access.requires_sign_in.message",
                fallback: "Sign in to your Millio account to work with cloud backups. In guest mode backups stay unavailable."
            )
        case .securityFailed, .unknown:
            return genericMessage
        }
    }

    static func userMessage(for error: Error) -> String {
        if let appError = error as? AppError {
            return userMessage(for: appError)
        }
        if let rollbackFailure = error as? RestoreRollbackFailure {
            return rollbackFailure.errorDescription ?? genericMessage
        }
        if let verificationFailure = error as? RestoreVerificationFailure {
            return verificationFailure.userMessage
        }
        return genericMessage
    }

    private static var genericMessage: String {
        BackupL10n.tr(
            "backup.restore.failure.generic",
            fallback: "Restore failed. Your data has not been changed."
        )
    }
}
