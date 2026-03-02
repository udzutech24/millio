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
    var isAppLockEnabled: Bool { get set }
    var isBiometricUnlockEnabled: Bool { get set }
}

final class SettingsManager: SettingsManagerProtocol {
    static let shared = SettingsManager()
    static let defaultPrimaryCurrencyCode = "RUB"
    static let maxFavoriteCurrencyCodes = 5
    static let defaultFavoriteCurrencyCodes = ["USD", "EUR"]
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "SettingsManager")
    private let backupEnabledKey = "isBackupEnabled"
    private let encryptionEnabledKey = "isEncryptionEnabled"
    private let dailyReminderEnabledKey = "isDailyReminderEnabled"
    private let appLockEnabledKey = "isAppLockEnabled"
    private let biometricUnlockEnabledKey = "isBiometricUnlockEnabled"
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

    var isAppLockEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: appLockEnabledKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: appLockEnabledKey)
            logger.info("App lock enabled: \(newValue)")
        }
    }

    var isBiometricUnlockEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: biometricUnlockEnabledKey) as? Bool ?? false
        }
        set {
            UserDefaults.standard.set(newValue, forKey: biometricUnlockEnabledKey)
            logger.info("Biometric unlock enabled: \(newValue)")
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
            UserDefaults.standard.string(forKey: primaryCurrencyCodeKey) ?? Self.defaultPrimaryCurrencyCode
        }
        set {
            let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty else { return }
            let previousPrimary = UserDefaults.standard.string(forKey: primaryCurrencyCodeKey) ?? Self.defaultPrimaryCurrencyCode
            let normalizedPrevious = previousPrimary.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            UserDefaults.standard.set(normalized, forKey: primaryCurrencyCodeKey)
            var rawFavorites = UserDefaults.standard.array(forKey: favoriteCurrencyCodesKey) as? [String] ?? Self.defaultFavoriteCurrencyCodes
            if !normalizedPrevious.isEmpty, normalizedPrevious != normalized {
                // При смене основной валюты старая остается доступной в "Избранных".
                rawFavorites.insert(normalizedPrevious, at: 0)
            }
            let sanitizedFavorites = Self.normalizeFavoriteCurrencyCodes(rawFavorites, primaryCode: normalized)
            UserDefaults.standard.set(sanitizedFavorites, forKey: favoriteCurrencyCodesKey)
            logger.info("Primary currency code updated: \(normalized)")
        }
    }

    /// Избранные валюты для быстрых выборов в UI.
    /// Хранятся в UserDefaults (строки ISO-кодов в верхнем регистре).
    var favoriteCurrencyCodes: [String] {
        get {
            let raw = UserDefaults.standard.array(forKey: favoriteCurrencyCodesKey) as? [String] ?? Self.defaultFavoriteCurrencyCodes
            return Self.normalizeFavoriteCurrencyCodes(raw, primaryCode: primaryCurrencyCode)
        }
        set {
            let normalized = Self.normalizeFavoriteCurrencyCodes(newValue, primaryCode: primaryCurrencyCode)
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

    /// Нормализует избранные коды валют:
    /// - удаляет дубликаты и пустые значения,
    /// - исключает текущую основную валюту,
    /// - ограничивает список до `maxFavoriteCurrencyCodes`.
    static func normalizeFavoriteCurrencyCodes(_ codes: [String], primaryCode: String) -> [String] {
        let normalizedPrimary = primaryCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalized = normalizeCurrencyCodes(codes)
            .filter { $0 != normalizedPrimary }
        return Array(normalized.prefix(maxFavoriteCurrencyCodes))
    }
    
    private init() {}
}
