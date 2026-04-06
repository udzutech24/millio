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
    /// Forces SwiftUI to rebuild the UI tree on language change (soft restart).
    var languageRefreshToken: UUID = UUID()
    var selectedLanguage: Language = .system {
        didSet {
            guard selectedLanguage != oldValue else { return }
            LanguageManager.shared.setLanguage(selectedLanguage)
            if isDailyReminderEnabled {
                let settings = SettingsManager.shared.dailyReminderSettings
                Task { @MainActor in
                    await NotificationManager.shared.scheduleDailyReminder(using: settings)
                }
            }
            languageRefreshToken = UUID()
            if SettingsManager.isDefaultProfileDisplayName(profileDisplayName) {
                let localizedDefault = SettingsManager.defaultProfileDisplayName(for: selectedLanguage)
                if profileDisplayName != localizedDefault {
                    profileDisplayName = localizedDefault
                    SettingsManager.shared.profileDisplayName = localizedDefault
                }
            }
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
            CurrencyWidgetSyncService.setString(normalized, forKey: CurrencyWidgetShared.Keys.primaryCurrencyCode)
            migrateDisplayCurrenciesIfFollowingPrimary(oldPrimary: oldNormalized, newPrimary: normalized)
        }
    }
    var isBackupEnabled: Bool = false
    var isAutoBackupEnabled: Bool = false
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
    var mainScreenLayoutMode: MainScreenLayoutMode = .classic {
        didSet {
            SettingsManager.shared.mainScreenLayoutMode = mainScreenLayoutMode
        }
    }
    var isAppLocked: Bool = false
    var isGuestModeEnabled: Bool = false {
        didSet {
            SettingsManager.shared.isGuestModeEnabled = isGuestModeEnabled
        }
    }

    /// Controls whether the Profile "Debug" section is visible.
    var isDebugMenuUnlocked: Bool = false {
        didSet {
            SettingsManager.shared.isDebugMenuUnlocked = isDebugMenuUnlocked
        }
    }
    
    // Subscription status
    var subscriptionStatus: SubscriptionStatus = .notSubscribed
    var subscriptionExpirationDate: Date?
    var isTrialActive: Bool = false
    var hasDebugPremiumOverride: Bool = false
    var hasTrialDisabledOverride: Bool = false
    var subscriptionAccessSource: SubscriptionAccessSource = .free
    
    var isPro: Bool {
        subscriptionAccessSource.hasPremiumAccess
    }
    
    // Профиль: имя и путь к аватарке
    var profileDisplayName: String = SettingsManager.defaultProfileDisplayName
    var profileAvatarPath: String?
    /// One-shot deep-link trigger: open Finance add-product sheet (card by default).
    var pendingOpenFinanceAddCard: Bool = false
    /// One-shot deep-link trigger from widget to quick expense sheet on Home.
    var pendingOpenMainExpenseSheet: Bool = false
    /// One-shot deep-link trigger from widget to quick income sheet on Home.
    var pendingOpenMainIncomeSheet: Bool = false
    /// One-shot trigger to open expense flow inside the actual Cashflow service.
    var pendingOpenCashflowExpense: Bool = false
    /// One-shot trigger to open income flow inside the actual Cashflow service.
    var pendingOpenCashflowIncome: Bool = false
    /// One-shot trigger to open history inside the actual Cashflow service.
    var pendingOpenCashflowHistory: Bool = false
    /// One-shot deep-link trigger from widget to open converter service.
    var pendingOpenConverterService: Bool = false
    var backendRegionCode: String = ""
    var backendBaseURLString: String = ""
    var isBackendFallbackActive: Bool = false
    var backendSelectionSummary: String = ""

    init() {
        self.isBackupEnabled = SettingsManager.shared.isBackupEnabled
        self.isAutoBackupEnabled = SettingsManager.shared.isAutoBackupEnabled
        self.isDailyReminderEnabled = SettingsManager.shared.isDailyReminderEnabled
        self.isAppLockEnabled = SettingsManager.shared.isAppLockEnabled
        self.isBiometricUnlockEnabled = SettingsManager.shared.isBiometricUnlockEnabled
        self.launchSplashDisplayMode = SettingsManager.shared.launchSplashDisplayMode
        self.mainScreenLayoutMode = SettingsManager.shared.mainScreenLayoutMode
        self.selectedLanguage = LanguageManager.shared.currentLanguage
        self.primaryCurrencyCode = SettingsManager.shared.primaryCurrencyCode
        self.profileDisplayName = SettingsManager.shared.profileDisplayName
        self.profileAvatarPath = SettingsManager.shared.profileAvatarFilePath
        self.isAppLocked = self.isAppLockEnabled
        self.isGuestModeEnabled = SettingsManager.shared.isGuestModeEnabled
        self.isDebugMenuUnlocked = SettingsManager.shared.isDebugMenuUnlocked
    }

    func applyBackendRuntime(_ runtime: BackendSessionRuntime) {
        backendRegionCode = runtime.selectedEndpoint.region.rawValue
        backendBaseURLString = runtime.selectedEndpoint.baseURL.absoluteString
        isBackendFallbackActive = runtime.fallbackActivated
        backendSelectionSummary = runtime.selectionSummaryLine
    }

    func applySubscriptionSnapshot(_ snapshot: SubscriptionSnapshot) {
        subscriptionStatus = snapshot.status
        subscriptionExpirationDate = snapshot.expirationDate
        isTrialActive = snapshot.isTrialActive
        hasDebugPremiumOverride = snapshot.hasDebugPremiumOverride
        hasTrialDisabledOverride = snapshot.hasTrialDisabledOverride
        subscriptionAccessSource = snapshot.accessSource
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

/// Централизованные правила монетизации Free/PRO.
enum EntitlementPolicy {
    static let freeTrackedTickerLimit = 5
    static let freeQuickSetupTrackedTickerLimit = 1
    static let freeCashbackCardLimit = 3
    static let freeCashbackCategoryLimitPerMonth = 10
    static let freeFinanceProductLimit = 10
    /// Beta flag: криптовалюта в конвертере временно доступна всем.
    static let isConverterCryptoProOnly = false
    /// Feature flag: импорт категорий кешбэка со скриншота доступен только при PRO-подписке.
    static let isCashbackScreenshotImportProOnly = true
    /// Feature flag: OCR-импорт расходов из банковских скриншотов доступен только при PRO-подписке.
    static let isCashflowExpenseScreenshotImportProOnly = true
    /// Beta flag: все карты кешбэка временно доступны всем.
    static let isCashbackCardsProOnly = false
    /// Beta flag: акции в финансах временно доступны всем.
    static let isFinanceStocksProOnly = false
    /// Beta flag: крипта в финансах временно доступна всем.
    static let isFinanceCryptoProOnly = false
    /// Beta flag: лимиты на рыночные тикеры временно сняты.
    static let isTrackedTickerLimitProOnly = false
    /// Feature flag: лимит продуктов в финансах действует только без PRO-подписки.
    static let isFinanceProductsProOnly = true
    /// Feature flag: графики в финансах доступны только при PRO-подписке.
    static let isFinanceChartsProOnly = true
    /// Feature flag: график cashflow доступен только при PRO-подписке.
    static let isCashflowChartProOnly = true

    static func canUseConverterCrypto(isPro: Bool) -> Bool {
        guard isConverterCryptoProOnly else { return true }
        return isPro
    }

    static func canUseQuickSetupCrypto(isPro: Bool) -> Bool {
        canUseFinanceCrypto(isPro: isPro)
    }

    static func canAddQuickSetupTrackedProduct(
        type: QuickSetupProductType,
        isPro: Bool,
        currentTrackedTickers: Int
    ) -> Bool {
        switch type {
        case .crypto:
            return canUseQuickSetupCrypto(isPro: isPro) && canAddQuickSetupTrackedTicker(
                isPro: isPro,
                currentTrackedTickers: currentTrackedTickers
            )
        case .ticker:
            return canAddQuickSetupTrackedTicker(
                isPro: isPro,
                currentTrackedTickers: currentTrackedTickers
            )
        default:
            return true
        }
    }

    static func canAddTrackedTicker(isPro: Bool, currentTrackedTickers: Int) -> Bool {
        guard isTrackedTickerLimitProOnly else { return true }
        return isPro || currentTrackedTickers < freeTrackedTickerLimit
    }

    static func hasTrackedTickerLimit(isPro: Bool) -> Bool {
        return isTrackedTickerLimitProOnly && !isPro
    }

    static func canUseCashbackCard(isPro: Bool, cardIndex: Int) -> Bool {
        guard isCashbackCardsProOnly else { return true }
        return isPro || cardIndex < freeCashbackCardLimit
    }

    static func canImportCashbackFromScreenshot(isPro: Bool) -> Bool {
        guard isCashbackScreenshotImportProOnly else { return true }
        return isPro
    }

    static func canImportCashflowExpensesFromScreenshot(isPro: Bool) -> Bool {
        guard isCashflowExpenseScreenshotImportProOnly else { return true }
        return isPro
    }

    static func canAddCashbackCategories(isPro: Bool, projectedCategoryCount: Int) -> Bool {
        isPro || projectedCategoryCount <= freeCashbackCategoryLimitPerMonth
    }

    static func canAddFinanceProduct(isPro: Bool, currentProducts: Int) -> Bool {
        guard isFinanceProductsProOnly else { return true }
        return isPro || currentProducts < freeFinanceProductLimit
    }

    static func canUseFinanceStocks(isPro: Bool) -> Bool {
        guard isFinanceStocksProOnly else { return true }
        return isPro
    }

    static func canUseFinanceCrypto(isPro: Bool) -> Bool {
        guard isFinanceCryptoProOnly else { return true }
        return isPro
    }

    static func canUseFinanceCharts(isPro: Bool) -> Bool {
        guard isFinanceChartsProOnly else { return true }
        return isPro
    }

    static func canUseCashflowChart(isPro: Bool) -> Bool {
        guard isCashflowChartProOnly else { return true }
        return isPro
    }

    private static func canAddQuickSetupTrackedTicker(isPro: Bool, currentTrackedTickers: Int) -> Bool {
        guard isTrackedTickerLimitProOnly else { return true }
        return isPro || currentTrackedTickers < freeQuickSetupTrackedTickerLimit
    }
}
