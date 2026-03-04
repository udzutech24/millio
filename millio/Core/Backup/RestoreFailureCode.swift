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
            return "Backup не найден в iCloud"
        case .allCandidatesInvalid:
            return "Не удалось восстановить данные: доступные backup повреждены или несовместимы"
        case .passphraseRequired:
            return "Backup зашифрован парольной фразой. Введите парольную фразу и повторите."
        case .passphraseNeededForDecrypt:
            return "Нужна парольная фраза для расшифровки backup"
        case .passphraseDecryptFailed:
            return "Не удалось расшифровать backup (неверная парольная фраза или поврежденные данные)"
        case .keychainUnavailable:
            return "Backup зашифрован и не может быть расшифрован на этом устройстве"
        case .keychainKeyMissingOnDevice:
            return "Ключ шифрования backup не найден на этом устройстве"
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
