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
            SettingsManager.shared.primaryCurrencyCode = primaryCurrencyCode
        }
    }
    var isBackupEnabled: Bool = false
    var isDailyReminderEnabled: Bool = false
    
    // Subscription status
    var subscriptionStatus: SubscriptionStatus = .notSubscribed
    var subscriptionExpirationDate: Date?
    var isTrialActive: Bool = false
    
    var isPro: Bool {
        subscriptionStatus == .subscribed || subscriptionStatus == .trial
    }
    
    // Профиль: имя и путь к аватарке
    var profileDisplayName: String = "Гость"
    var profileAvatarPath: String?
    
    init() {
        self.isBackupEnabled = SettingsManager.shared.isBackupEnabled
        self.isDailyReminderEnabled = SettingsManager.shared.isDailyReminderEnabled
        self.selectedLanguage = LanguageManager.shared.currentLanguage
        self.primaryCurrencyCode = SettingsManager.shared.primaryCurrencyCode
        self.profileDisplayName = SettingsManager.shared.profileDisplayName
        self.profileAvatarPath = SettingsManager.shared.profileAvatarFilePath
    }
}
