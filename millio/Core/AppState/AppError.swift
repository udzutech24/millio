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
            return "iCloud is unavailable"
        case .networkUnavailable:
            return "Network is unavailable"
        case .backupCorrupted:
            return "Backup is corrupted"
        case .incompatibleSchemaVersion:
            return "Incompatible data version"
        case .restoreFailed(let message):
            return "Restore failed: \(message)"
        case .backupFailed(let message):
            return "Backup failed: \(message)"
        case .securityFailed(let message):
            return "Security error: \(message)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
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
