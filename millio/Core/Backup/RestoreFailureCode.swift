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
    case keychainUnavailable
    case decryptFailed
    case preRestoreSnapshotFailed
    case rollbackFailed

    var message: String {
        switch self {
        case .backupNotFound:
            return "Backup не найден в iCloud"
        case .allCandidatesInvalid:
            return "Не удалось восстановить данные: доступные backup повреждены или несовместимы"
        case .passphraseRequired:
            return "Backup зашифрован парольной фразой. Введите парольную фразу и повторите."
        case .keychainUnavailable:
            return "Backup зашифрован и не может быть расшифрован на этом устройстве"
        case .decryptFailed:
            return "Не удалось расшифровать backup"
        case .preRestoreSnapshotFailed:
            return "Не удалось создать снимок данных перед восстановлением"
        case .rollbackFailed:
            return "Не удалось восстановить данные после ошибки восстановления"
        }
    }

    var reason: RestoreCandidateReason {
        switch self {
        case .backupNotFound, .allCandidatesInvalid, .decryptFailed, .preRestoreSnapshotFailed, .rollbackFailed:
            return .restoreFailed
        case .passphraseRequired:
            return .passphraseRequired
        case .keychainUnavailable:
            return .keychainUnavailable
        }
    }

    var appError: AppError {
        .restoreFailed(message)
    }
}
