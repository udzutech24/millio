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
    private let primaryCurrencyCodeKey = "primaryCurrencyCode"
    private let favoriteCurrencyCodesKey = "favoriteCurrencyCodes"
    
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

    /// Основная валюта приложения (используется как дефолт во всех денежных сервисах).
    /// Хранится в UserDefaults, чтобы быть доступной на уровне Core.
    var primaryCurrencyCode: String {
        get {
            UserDefaults.standard.string(forKey: primaryCurrencyCodeKey) ?? "RUB"
        }
        set {
            let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty else { return }
            UserDefaults.standard.set(normalized, forKey: primaryCurrencyCodeKey)
            logger.info("Primary currency code updated: \(normalized)")
        }
    }

    /// Избранные валюты для быстрых выборов в UI.
    /// Хранятся в UserDefaults (строки ISO-кодов в верхнем регистре).
    var favoriteCurrencyCodes: [String] {
        get {
            if UserDefaults.standard.object(forKey: favoriteCurrencyCodesKey) == nil {
                return ["RUB", "USD", "EUR"]
            }
            let raw = UserDefaults.standard.array(forKey: favoriteCurrencyCodesKey) as? [String] ?? []
            return Self.normalizeCurrencyCodes(raw)
        }
        set {
            let normalized = Self.normalizeCurrencyCodes(newValue)
            UserDefaults.standard.set(normalized, forKey: favoriteCurrencyCodesKey)
            logger.info("Favorite currency codes updated: \(normalized.count)")
        }
    }
    
    static func normalizeCurrencyCodes(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        
        for raw in codes {
            let c = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !c.isEmpty else { continue }
            if seen.contains(c) { continue }
            seen.insert(c)
            result.append(c)
        }
        
        return result
    }
    
    private init() {}
}
