//
//  AppState.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

// Импортируем SubscriptionStatus из SubscriptionManager
// (определен в SubscriptionManager.swift)

@Observable
@MainActor
final class AppState {
    var lifecycle: AppLifecycleState = .launching
    var isICloudAvailable: Bool = false
    var lastBackupDate: Date?
    var selectedLanguage: Language = .system {
        didSet {
            LanguageManager.shared.setLanguage(selectedLanguage)
        }
    }
    var primaryCurrencyCode: String = "RUB" {
        didSet {
            let normalized = primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty else {
                primaryCurrencyCode = oldValue
                return
            }
            if normalized != primaryCurrencyCode {
                primaryCurrencyCode = normalized
                return
            }
            let oldNormalized = oldValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            SettingsManager.shared.primaryCurrencyCode = normalized
            migrateDisplayCurrenciesIfFollowingPrimary(oldPrimary: oldNormalized, newPrimary: normalized)
        }
    }
    var isBackupEnabled: Bool = false
    var isDailyReminderEnabled: Bool = false
    var isAppLockEnabled: Bool = false {
        didSet {
            SettingsManager.shared.isAppLockEnabled = isAppLockEnabled
            if !isAppLockEnabled {
                isBiometricUnlockEnabled = false
                isAppLocked = false
            }
        }
    }
    var isBiometricUnlockEnabled: Bool = false {
        didSet {
            SettingsManager.shared.isBiometricUnlockEnabled = isBiometricUnlockEnabled
        }
    }
    var launchSplashDisplayMode: LaunchSplashDisplayMode = .always
    var isAppLocked: Bool = false
    
    // Subscription status
    var subscriptionStatus: SubscriptionStatus = .notSubscribed
    var subscriptionExpirationDate: Date?
    var isTrialActive: Bool = false
    
    var isPro: Bool {
        subscriptionStatus == .subscribed || subscriptionStatus == .trial
    }
    
    // Профиль: имя и путь к аватарке
    var profileDisplayName: String = SettingsManager.defaultProfileDisplayName
    var profileAvatarPath: String?
    /// One-shot deep-link trigger: open Finance add-product sheet (card by default).
    var pendingOpenFinanceAddCard: Bool = false
    
    init() {
        self.isBackupEnabled = SettingsManager.shared.isBackupEnabled
        self.isDailyReminderEnabled = SettingsManager.shared.isDailyReminderEnabled
        self.isAppLockEnabled = SettingsManager.shared.isAppLockEnabled
        self.isBiometricUnlockEnabled = SettingsManager.shared.isBiometricUnlockEnabled
        self.launchSplashDisplayMode = SettingsManager.shared.launchSplashDisplayMode
        self.selectedLanguage = LanguageManager.shared.currentLanguage
        self.primaryCurrencyCode = SettingsManager.shared.primaryCurrencyCode
        self.profileDisplayName = SettingsManager.shared.profileDisplayName
        self.profileAvatarPath = SettingsManager.shared.profileAvatarFilePath
        self.isAppLocked = self.isAppLockEnabled
    }

    /// При смене основной валюты мигрируем только persisted display-настройки модулей,
    /// которые хранят отдельную валюту отображения между сессиями.
    private func migrateDisplayCurrenciesIfFollowingPrimary(oldPrimary: String, newPrimary: String) {
        guard !oldPrimary.isEmpty, oldPrimary != newPrimary else { return }
        let defaults = UserDefaults.standard
        let displayCurrencyKeysFollowingPrimary = [
            "card_display_currency",
            "investment_display_currency",
            "credit_display_currency"
        ]
        for key in displayCurrencyKeysFollowingPrimary {
            guard let raw = defaults.string(forKey: key) else { continue }
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if normalized == oldPrimary {
                defaults.set(newPrimary, forKey: key)
            }
        }
    }
}
