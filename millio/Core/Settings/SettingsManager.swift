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
    var isDailyReminderEnabled: Bool { get set }
}

final class SettingsManager: SettingsManagerProtocol {
    static let shared = SettingsManager()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "SettingsManager")
    private let backupEnabledKey = "isBackupEnabled"
    private let encryptionEnabledKey = "isEncryptionEnabled"
    private let dailyReminderEnabledKey = "isDailyReminderEnabled"
    private let profileDisplayNameKey = "profileDisplayName"
    private let profileAvatarFilePathKey = "profileAvatarFilePath"
    
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
    
    var isEncryptionEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: encryptionEnabledKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: encryptionEnabledKey)
            logger.info("Backup encryption enabled: \(newValue)")
        }
    }
    
    var isDailyReminderEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: dailyReminderEnabledKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: dailyReminderEnabledKey)
            logger.info("Daily reminder enabled: \(newValue)")
        }
    }
    
    var profileDisplayName: String {
        get {
            UserDefaults.standard.string(forKey: profileDisplayNameKey) ?? "Гость"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: profileDisplayNameKey)
            logger.info("Profile display name updated")
        }
    }
    
    var profileAvatarFilePath: String? {
        get {
            UserDefaults.standard.string(forKey: profileAvatarFilePathKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: profileAvatarFilePathKey)
            logger.info("Profile avatar path updated")
        }
    }
    
    private init() {}
}
