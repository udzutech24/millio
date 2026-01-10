//
//  SettingsManager.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import OSLog

protocol SettingsManagerProtocol {
    var isBackupEnabled: Bool { get set }
    var isEncryptionEnabled: Bool { get set }
}

nonisolated final class SettingsManager: SettingsManagerProtocol {
    nonisolated static let shared = SettingsManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "SettingsManager")
    private let backupEnabledKey = "isBackupEnabled"
    private let encryptionEnabledKey = "isEncryptionEnabled"
    
    nonisolated var isBackupEnabled: Bool {
        get {
            // По умолчанию backup отключен
            UserDefaults.standard.object(forKey: backupEnabledKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: backupEnabledKey)
            logger.info("Backup enabled: \(newValue)")
        }
    }
    
    nonisolated var isEncryptionEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: encryptionEnabledKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: encryptionEnabledKey)
            logger.info("Backup encryption enabled: \(newValue)")
        }
    }
    
    nonisolated private init() {}
}
