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
            return "Ошибка инициализации сжатия"
        case .compressionEncodeFailed:
            return "Не удалось сжать backup"
        case .envelopeHeaderTooLarge:
            return "Слишком большой заголовок backup"
        case .metadataSerializationFailed:
            return "Не удалось сериализовать metadata для backup"
        case .modelExportUnexpectedFormat(let typeName):
            return "Экспорт модели '\(typeName)' вернул неожиданный формат"
        case .keychainKeyUpdateFailed:
            return "Не удалось обновить ключ шифрования backup"
        case .keychainKeySaveFailed:
            return "Не удалось сохранить ключ шифрования backup"
        case .keychainKeyDeleteFailed:
            return "Не удалось удалить ключ шифрования backup"
        case .passphraseEmpty:
            return "Парольная фраза пустая"
        case .passphraseKeyDerivationFailed:
            return "Не удалось получить ключ шифрования из парольной фразы"
        case .randomBytesGenerationFailed:
            return "Не удалось сгенерировать случайные байты для backup"
        case .cloudKitOperationFailed(let detail):
            let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDetail.isEmpty else {
                return "Ошибка CloudKit при работе с backup"
            }
            return "Ошибка CloudKit при работе с backup: \(trimmedDetail)"
        }
    }

    var appError: AppError {
        .backupFailed(message)
    }
}
