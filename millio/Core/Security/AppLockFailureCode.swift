//
//  AppLockFailureCode.swift
//  millio
//
//  Created by Александр Сидоркин on 04.03.2026.
//

import Foundation

enum AppLockFailureCode {
    case invalidPinFormat
    case keychainPinUpdateFailed
    case keychainPinSaveFailed
    case secureRandomPinGenerationFailed

    var message: String {
        switch self {
        case .invalidPinFormat:
            return "PIN-код должен состоять из 4 цифр"
        case .keychainPinUpdateFailed:
            return "Не удалось обновить PIN-код"
        case .keychainPinSaveFailed:
            return "Не удалось сохранить PIN-код"
        case .secureRandomPinGenerationFailed:
            return "Не удалось сгенерировать безопасный PIN"
        }
    }

    var appError: AppError {
        .securityFailed(message)
    }
}
