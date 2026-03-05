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
            return "PIN must contain exactly 4 digits"
        case .keychainPinUpdateFailed:
            return "Failed to update PIN"
        case .keychainPinSaveFailed:
            return "Failed to save PIN"
        case .secureRandomPinGenerationFailed:
            return "Failed to generate secure PIN"
        }
    }

    var appError: AppError {
        .securityFailed(message)
    }
}
