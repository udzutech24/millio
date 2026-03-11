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
    var dailyReminderSettings: DailyReminderSettings { get set }
    var isAppLockEnabled: Bool { get set }
    var isBiometricUnlockEnabled: Bool { get set }
    func resetToDefaults()
}

final class SettingsManager: SettingsManagerProtocol, LaunchSplashPreferences {
    static let shared = SettingsManager()
    static let defaultPrimaryCurrencyCode = "RUB"
    static let maxFavoriteCurrencyCodes = 5
    static let defaultFavoriteCurrencyCodes = ["USD", "EUR"]
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "SettingsManager")
    private let backupEnabledKey = "isBackupEnabled"
    private let encryptionEnabledKey = "isEncryptionEnabled"
    private let dailyReminderEnabledKey = "isDailyReminderEnabled"
    private let dailyReminderSettingsKey = "dailyReminderSettings"
    private let appLockEnabledKey = "isAppLockEnabled"
    private let biometricUnlockEnabledKey = "isBiometricUnlockEnabled"
    private let profileDisplayNameKey = "profileDisplayName"
    private let profileAvatarFilePathKey = "profileAvatarFilePath"
    private let primaryCurrencyCodeKey = "primaryCurrencyCode"
    private let favoriteCurrencyCodesKey = "favoriteCurrencyCodes"
    private let quickSetupCompletedKey = "quickSetupCompleted"
    private let quickSetupBannerHiddenKey = "quickSetupBannerHidden"
    private let quickSetupExpenseCategoryIDsKey = "quickSetupExpenseCategoryIDs"
    private let launchSplashDisplayModeKey = "launchSplashDisplayMode"
    private let lastLaunchSplashShownAtKey = "lastLaunchSplashShownAt"
    private let guestModeEnabledKey = "guestModeEnabled"
    private let debugMenuUnlockedKey = "debugMenuUnlocked"
    private static let legacyDefaultProfileDisplayNames: Set<String> = ["Гость", "Guest"]
    private let defaults: UserDefaults

    static var defaultProfileDisplayName: String {
        AppLocalization.string(
            "profile.default_guest",
            locale: LanguageManager.shared.currentLanguage.locale ?? Locale.current,
            fallback: "Guest"
        )
    }

    static func isDefaultProfileDisplayName(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        if legacyDefaultProfileDisplayNames.contains(normalized) {
            return true
        }

        let localizedDefaults = Set(
            Language.allCases.map { language in
                AppLocalization.string(
                    "profile.default_guest",
                    locale: language.locale ?? Locale.current,
                    fallback: "Guest"
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        return localizedDefaults.contains(normalized)
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
            let storedEnabled = defaults.object(forKey: dailyReminderEnabledKey) as? Bool
            if let storedEnabled {
                return storedEnabled
            }
            return dailyReminderSettings.isEnabled
        }
        set {
            defaults.set(newValue, forKey: dailyReminderEnabledKey)
            var settings = dailyReminderSettings
            settings.isEnabled = newValue
            storeDailyReminderSettings(settings)
            logger.info("Daily reminder enabled: \(newValue)")
        }
    }

    var dailyReminderSettings: DailyReminderSettings {
        get {
            guard
                let data = defaults.data(forKey: dailyReminderSettingsKey),
                let decoded = try? JSONDecoder().decode(DailyReminderSettings.self, from: data)
            else {
                var legacy = DailyReminderSettings.default
                legacy.isEnabled = defaults.object(forKey: dailyReminderEnabledKey) as? Bool ?? false
                return legacy
            }
            return decoded.normalized()
        }
        set {
            let normalized = newValue.normalized()
            storeDailyReminderSettings(normalized)
            defaults.set(normalized.isEnabled, forKey: dailyReminderEnabledKey)
            logger.info("Daily reminder settings updated")
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

    /// Завершена ли «Быстрая настройка».
    var isQuickSetupCompleted: Bool {
        get {
            defaults.object(forKey: quickSetupCompletedKey) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: quickSetupCompletedKey)
            logger.info("Quick setup completed: \(newValue)")
        }
    }

    /// Скрыта ли карточка «Быстрая настройка» на главной.
    var isQuickSetupBannerHidden: Bool {
        get {
            defaults.object(forKey: quickSetupBannerHiddenKey) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: quickSetupBannerHiddenKey)
            logger.info("Quick setup banner hidden: \(newValue)")
        }
    }

    /// Выбранные категории расходов в быстрой настройке.
    var quickSetupExpenseCategoryIDs: [String] {
        get {
            normalizeCategoryIDs(defaults.array(forKey: quickSetupExpenseCategoryIDsKey) as? [String] ?? [])
        }
        set {
            defaults.set(normalizeCategoryIDs(newValue), forKey: quickSetupExpenseCategoryIDsKey)
            logger.info("Quick setup expense categories updated: \(newValue.count)")
        }
    }

    var launchSplashDisplayMode: LaunchSplashDisplayMode {
        get {
            guard
                let raw = defaults.string(forKey: launchSplashDisplayModeKey),
                let mode = LaunchSplashDisplayMode(rawValue: raw)
            else {
                return .always
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: launchSplashDisplayModeKey)
            logger.info("Launch splash display mode updated: \(newValue.rawValue)")
        }
    }

    var lastLaunchSplashShownAt: Date? {
        get {
            defaults.object(forKey: lastLaunchSplashShownAtKey) as? Date
        }
        set {
            defaults.set(newValue, forKey: lastLaunchSplashShownAtKey)
        }
    }

    var isGuestModeEnabled: Bool {
        get {
            defaults.object(forKey: guestModeEnabledKey) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: guestModeEnabledKey)
            logger.info("Guest mode enabled: \(newValue)")
        }
    }

    /// Controls whether the Profile "Debug" section is visible.
    /// Hidden by default; can be unlocked via the multi-tap version gesture.
    var isDebugMenuUnlocked: Bool {
        get {
            defaults.object(forKey: debugMenuUnlockedKey) as? Bool ?? false
        }
        set {
            defaults.set(newValue, forKey: debugMenuUnlockedKey)
            logger.info("Debug menu unlocked: \(newValue)")
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

    private func normalizeCategoryIDs(_ raws: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in raws {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
        }
        return result
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Возвращает пользовательские настройки к безопасным дефолтам приложения.
    func resetToDefaults() {
        isBackupEnabled = false
        isEncryptionEnabled = false
        isDailyReminderEnabled = false
        dailyReminderSettings = .default
        isAppLockEnabled = false
        isBiometricUnlockEnabled = false
        profileDisplayName = Self.defaultProfileDisplayName
        profileAvatarFilePath = nil
        primaryCurrencyCode = Self.defaultPrimaryCurrencyCode
        favoriteCurrencyCodes = Self.defaultFavoriteCurrencyCodes
        isQuickSetupCompleted = false
        isQuickSetupBannerHidden = false
        quickSetupExpenseCategoryIDs = []
        launchSplashDisplayMode = .always
        lastLaunchSplashShownAt = nil
        isGuestModeEnabled = false
        isDebugMenuUnlocked = false

        // Модульные display-валюты и прочие временные UX-флаги.
        defaults.removeObject(forKey: "card_display_currency")
        defaults.removeObject(forKey: "credit_display_currency")
        defaults.removeObject(forKey: "investment_display_currency")
        defaults.removeObject(forKey: "conv_rate_source")
    }

    private func storeDailyReminderSettings(_ settings: DailyReminderSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            logger.error("Failed to encode daily reminder settings")
            return
        }
        defaults.set(data, forKey: dailyReminderSettingsKey)
    }
}
