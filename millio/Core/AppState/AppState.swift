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
    var isBackupEnabled: Bool = false
    var isDailyReminderEnabled: Bool = false
    
    // Subscription status
    var subscriptionStatus: SubscriptionStatus = .notSubscribed
    var subscriptionExpirationDate: Date?
    var isTrialActive: Bool = false
    
    var isPro: Bool {
        subscriptionStatus == .subscribed || subscriptionStatus == .trial
    }
    
    init() {
        self.isBackupEnabled = SettingsManager.shared.isBackupEnabled
        self.isDailyReminderEnabled = SettingsManager.shared.isDailyReminderEnabled
        self.selectedLanguage = LanguageManager.shared.currentLanguage
    }
}
