//
//  AppError.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

enum AppError: Error, Equatable, Hashable {
    case iCloudUnavailable
    case networkUnavailable
    case backupCorrupted
    case incompatibleSchemaVersion
    case restoreFailed(String)
    case backupFailed(String)
    case securityFailed(String)
    case unknown(Error)
    
    var localizedDescription: String {
        switch self {
        case .iCloudUnavailable:
            return "iCloud недоступен"
        case .networkUnavailable:
            return "Сеть недоступна"
        case .backupCorrupted:
            return "Резервная копия повреждена"
        case .incompatibleSchemaVersion:
            return "Несовместимая версия данных"
        case .restoreFailed(let message):
            return "Ошибка восстановления: \(message)"
        case .backupFailed(let message):
            return "Ошибка резервного копирования: \(message)"
        case .securityFailed(let message):
            return "Ошибка безопасности: \(message)"
        case .unknown(let error):
            return "Неизвестная ошибка: \(error.localizedDescription)"
        }
    }
    
    static func == (lhs: AppError, rhs: AppError) -> Bool {
        switch (lhs, rhs) {
        case (.iCloudUnavailable, .iCloudUnavailable),
             (.networkUnavailable, .networkUnavailable),
             (.backupCorrupted, .backupCorrupted),
             (.incompatibleSchemaVersion, .incompatibleSchemaVersion):
            return true
        case (.restoreFailed(let lhsMsg), .restoreFailed(let rhsMsg)),
             (.backupFailed(let lhsMsg), .backupFailed(let rhsMsg)),
             (.securityFailed(let lhsMsg), .securityFailed(let rhsMsg)):
            return lhsMsg == rhsMsg
        case (.unknown(let lhsError), .unknown(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .iCloudUnavailable:
            hasher.combine(0)
        case .networkUnavailable:
            hasher.combine(1)
        case .backupCorrupted:
            hasher.combine(2)
        case .incompatibleSchemaVersion:
            hasher.combine(3)
        case .restoreFailed(let message):
            hasher.combine(4)
            hasher.combine(message)
        case .backupFailed(let message):
            hasher.combine(5)
            hasher.combine(message)
        case .securityFailed(let message):
            hasher.combine(6)
            hasher.combine(message)
        case .unknown(let error):
            hasher.combine(7)
            hasher.combine(error.localizedDescription)
        }
    }
}
