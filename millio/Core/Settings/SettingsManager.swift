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
}

final class SettingsManager: SettingsManagerProtocol {
    static let shared = SettingsManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "SettingsManager")
    private let backupEnabledKey = "isBackupEnabled"
    
    var isBackupEnabled: Bool {
        get {
            // По умолчанию backup отключен
            UserDefaults.standard.object(forKey: backupEnabledKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: backupEnabledKey)
            logger.info("Backup enabled: \(newValue)")
        }
    }
    
    private init() {}
}
