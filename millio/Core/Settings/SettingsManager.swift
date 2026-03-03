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
    private static let legacyDefaultProfileDisplayNames: Set<String> = ["Гость", "Guest"]
    private let defaults: UserDefaults

    static var defaultProfileDisplayName: String {
        String(
            localized: "profile.default_guest",
            locale: LanguageManager.shared.currentLanguage.locale ?? Locale.current
        )
    }

    static func isDefaultProfileDisplayName(_ value: String) -> Bool {
        legacyDefaultProfileDisplayNames.contains(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    
    var isBackupEnabled: Bool {
        get {
            // По умолчанию backup отключен
            defaults.object(forKey: backupEnabledKey) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: backupEnabledKey)
            logger.info("Backup enabled: \(newValue)")
        }
    }
    
    var isEncryptionEnabled: Bool {
        get {
            defaults.object(forKey: encryptionEnabledKey) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: encryptionEnabledKey)
            logger.info("Backup encryption enabled: \(newValue)")
        }
    }
    
    var isDailyReminderEnabled: Bool {
        get {
            defaults.object(forKey: dailyReminderEnabledKey) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: dailyReminderEnabledKey)
            logger.info("Daily reminder enabled: \(newValue)")
        }
    }

    var isAppLockEnabled: Bool {
        get {
            defaults.object(forKey: appLockEnabledKey) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: appLockEnabledKey)
            logger.info("App lock enabled: \(newValue)")
        }
    }

    var isBiometricUnlockEnabled: Bool {
        get {
            defaults.object(forKey: biometricUnlockEnabledKey) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: biometricUnlockEnabledKey)
            logger.info("Biometric unlock enabled: \(newValue)")
        }
    }
    
    var profileDisplayName: String {
        get {
            guard let stored = defaults.string(forKey: profileDisplayNameKey) else {
                return Self.defaultProfileDisplayName
            }

            let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return Self.defaultProfileDisplayName
            }

            if Self.isDefaultProfileDisplayName(trimmed) {
                return Self.defaultProfileDisplayName
            }

            return stored
        }
        set {
            defaults.set(newValue, forKey: profileDisplayNameKey)
            logger.info("Profile display name updated")
        }
    }
    
    var profileAvatarFilePath: String? {
        get {
            defaults.string(forKey: profileAvatarFilePathKey)
        }
        set {
            defaults.set(newValue, forKey: profileAvatarFilePathKey)
            logger.info("Profile avatar path updated")
        }
    }

    /// Основная валюта приложения (используется как дефолт во всех денежных сервисах).
    /// Хранится в UserDefaults, чтобы быть доступной на уровне Core.
    var primaryCurrencyCode: String {
        get {
            defaults.string(forKey: primaryCurrencyCodeKey) ?? Self.defaultPrimaryCurrencyCode
        }
        set {
            let normalized = newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty else { return }
            let previousPrimary = defaults.string(forKey: primaryCurrencyCodeKey) ?? Self.defaultPrimaryCurrencyCode
            let normalizedPrevious = previousPrimary.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            defaults.set(normalized, forKey: primaryCurrencyCodeKey)
            var rawFavorites = defaults.array(forKey: favoriteCurrencyCodesKey) as? [String] ?? Self.defaultFavoriteCurrencyCodes
            if !normalizedPrevious.isEmpty, normalizedPrevious != normalized {
                // При смене основной валюты старая остается доступной в "Избранных".
                rawFavorites.insert(normalizedPrevious, at: 0)
            }
            let sanitizedFavorites = Self.normalizeFavoriteCurrencyCodes(rawFavorites, primaryCode: normalized)
            defaults.set(sanitizedFavorites, forKey: favoriteCurrencyCodesKey)
            logger.info("Primary currency code updated: \(normalized)")
        }
    }

    /// Избранные валюты для быстрых выборов в UI.
    /// Хранятся в UserDefaults (строки ISO-кодов в верхнем регистре).
    var favoriteCurrencyCodes: [String] {
        get {
            let raw = defaults.array(forKey: favoriteCurrencyCodesKey) as? [String] ?? Self.defaultFavoriteCurrencyCodes
            return Self.normalizeFavoriteCurrencyCodes(raw, primaryCode: primaryCurrencyCode)
        }
        set {
            let normalized = Self.normalizeFavoriteCurrencyCodes(newValue, primaryCode: primaryCurrencyCode)
            defaults.set(normalized, forKey: favoriteCurrencyCodesKey)
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
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
}
