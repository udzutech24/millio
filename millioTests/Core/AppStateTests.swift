//
//  AppStateTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)

@MainActor
struct AppStateTests {
    @Test("App state has correct initial values")
    func testInitialState() {
        // Очищаем сохраненный язык для чистого теста
        UserDefaults.standard.removeObject(forKey: "selectedLanguage")
        UserDefaults.standard.synchronize()

        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }
        LanguageManager.shared.setLanguage(.system)

        let appState = AppState()
        
        #expect(appState.lifecycle == .launching)
        #expect(appState.isICloudAvailable == false)
        #expect(appState.lastBackupDate == nil)
        // Проверяем, что selectedLanguage соответствует LanguageManager.shared.currentLanguage
        // так как AppState инициализируется из LanguageManager
        #expect(appState.selectedLanguage == LanguageManager.shared.currentLanguage)
    }
    
    @Test("App state lifecycle transitions work correctly")
    func testLifecycleTransitions() {
        let appState = AppState()
        
        appState.lifecycle = .onboarding
        #expect(appState.lifecycle == .onboarding)
        
        appState.lifecycle = .ready
        #expect(appState.lifecycle == .ready)
        
        let error = AppError.iCloudUnavailable
        appState.lifecycle = .error(error)
        #expect(appState.lifecycle == .error(error))
    }
    
    @Test("iCloud availability can be set")
    func testICloudAvailability() {
        let appState = AppState()
        
        appState.isICloudAvailable = true
        #expect(appState.isICloudAvailable == true)
    }
    
    @Test("Last backup date can be set")
    func testLastBackupDate() {
        let appState = AppState()
        let date = Date()
        
        appState.lastBackupDate = date
        #expect(appState.lastBackupDate == date)
    }
    
    @Test("Language selection works")
    func testLanguageSelection() {
        let appState = AppState()
        
        appState.selectedLanguage = .russian
        #expect(appState.selectedLanguage == .russian)
        
        appState.selectedLanguage = .english
        #expect(appState.selectedLanguage == .english)
    }

    @Test("Simplified Chinese selection persists and updates AppleLanguages")
    func testSimplifiedChineseSelectionPersistsAndUpdatesAppleLanguages() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        let defaults = UserDefaults.standard
        let previousAppleLanguages = defaults.array(forKey: "AppleLanguages") as? [String]
        defer {
            LanguageManager.shared.setLanguage(previousLanguage)
            if let previousAppleLanguages {
                defaults.set(previousAppleLanguages, forKey: "AppleLanguages")
            } else {
                defaults.removeObject(forKey: "AppleLanguages")
            }
            defaults.synchronize()
        }

        let appState = AppState()
        appState.selectedLanguage = .simplifiedChinese

        #expect(appState.selectedLanguage == .simplifiedChinese)
        #expect(LanguageManager.shared.currentLanguage == .simplifiedChinese)
        #expect(defaults.string(forKey: "selectedLanguage") == Language.simplifiedChinese.rawValue)
        #expect(defaults.array(forKey: "AppleLanguages") as? [String] == [Language.simplifiedChinese.rawValue])
        #expect(LocalizationSupport.locale(AppLocalization.currentAppLocale, matches: .simplifiedChinese))
    }
    
    @Test("AppState.isPro зависит от subscriptionStatus")
    func testIsProComputedFromSubscriptionStatus() {
        let appState = AppState()
        
        appState.applySubscriptionSnapshot(
            SubscriptionSnapshot(
                status: .notSubscribed,
                expirationDate: nil,
                isTrialActive: false,
                hasDebugPremiumOverride: false,
                hasTrialDisabledOverride: false
            )
        )
        #expect(appState.isPro == false)
        
        appState.applySubscriptionSnapshot(
            SubscriptionSnapshot(
                status: .trial,
                expirationDate: nil,
                isTrialActive: true,
                hasDebugPremiumOverride: false,
                hasTrialDisabledOverride: false
            )
        )
        #expect(appState.isPro == true)
        
        appState.applySubscriptionSnapshot(
            SubscriptionSnapshot(
                status: .subscribed,
                expirationDate: Date(),
                isTrialActive: false,
                hasDebugPremiumOverride: false,
                hasTrialDisabledOverride: false
            )
        )
        #expect(appState.isPro == true)
        
        appState.applySubscriptionSnapshot(
            SubscriptionSnapshot(
                status: .expired,
                expirationDate: nil,
                isTrialActive: false,
                hasDebugPremiumOverride: false,
                hasTrialDisabledOverride: false
            )
        )
        #expect(appState.isPro == false)
    }

    @Test("AppState учитывает debug override как отдельный источник premium-доступа")
    func testApplySubscriptionSnapshotTracksDebugSourceSeparately() {
        let appState = AppState()

        appState.applySubscriptionSnapshot(
            SubscriptionSnapshot(
                status: .notSubscribed,
                expirationDate: nil,
                isTrialActive: false,
                hasDebugPremiumOverride: true,
                hasTrialDisabledOverride: false
            )
        )

        #expect(appState.isPro == true)
        #expect(appState.hasDebugPremiumOverride == true)
        #expect(appState.subscriptionAccessSource == .debug)
    }
    
    @Test("AppState сохраняет primaryCurrencyCode нормализованным и не принимает пустое значение")
    func testPrimaryCurrencyCodeNormalizationAndEmptyGuard() {
        let defaults = UserDefaults.standard
        let primaryKey = "primaryCurrencyCode"
        let favoritesKey = "favoriteCurrencyCodes"
        let originalPrimary = defaults.string(forKey: primaryKey)
        let originalFavorites = defaults.array(forKey: favoritesKey) as? [String]
        defer {
            if let originalPrimary {
                defaults.set(originalPrimary, forKey: primaryKey)
            } else {
                defaults.removeObject(forKey: primaryKey)
            }
            if let originalFavorites {
                defaults.set(originalFavorites, forKey: favoritesKey)
            } else {
                defaults.removeObject(forKey: favoritesKey)
            }
        }

        defaults.removeObject(forKey: primaryKey)
        defaults.removeObject(forKey: favoritesKey)
        defaults.synchronize()
        
        let appState = AppState()
        #expect(appState.primaryCurrencyCode == "RUB")
        
        appState.primaryCurrencyCode = " usd "
        #expect(appState.primaryCurrencyCode == "USD")
        #expect(SettingsManager.shared.primaryCurrencyCode == "USD")
        
        appState.primaryCurrencyCode = "   "
        #expect(appState.primaryCurrencyCode == "USD")
        #expect(SettingsManager.shared.primaryCurrencyCode == "USD")
    }

    @Test("AppState при смене primaryCurrencyCode мигрирует только persisted display currency модулей счетов")
    func testPrimaryCurrencyCodeMigratesFollowingDisplayCurrencies() {
        let defaults = UserDefaults.standard
        let primaryKey = "primaryCurrencyCode"
        let favoritesKey = "favoriteCurrencyCodes"
        let keys = [
            "cashflow_display_currency",
            "finance_display_currency",
            "card_display_currency",
            "investment_display_currency",
            "credit_display_currency"
        ]
        let originalPrimary = defaults.string(forKey: primaryKey)
        let originalFavorites = defaults.array(forKey: favoritesKey) as? [String]
        let originalValues = keys.reduce(into: [String: String?]()) { partialResult, key in
            partialResult[key] = defaults.string(forKey: key)
        }
        defer {
            if let originalPrimary {
                defaults.set(originalPrimary, forKey: primaryKey)
            } else {
                defaults.removeObject(forKey: primaryKey)
            }
            if let originalFavorites {
                defaults.set(originalFavorites, forKey: favoritesKey)
            } else {
                defaults.removeObject(forKey: favoritesKey)
            }
            for key in keys {
                if let value = originalValues[key] ?? nil {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set("RUB", forKey: primaryKey)
        defaults.removeObject(forKey: favoritesKey)
        defaults.set("AMD", forKey: "cashflow_display_currency")
        defaults.set("USD", forKey: "finance_display_currency")
        defaults.set("RUB", forKey: "card_display_currency")
        defaults.set("EUR", forKey: "investment_display_currency")
        defaults.set("RUB", forKey: "credit_display_currency")

        let appState = AppState()
        appState.primaryCurrencyCode = "USD"

        #expect(defaults.string(forKey: "cashflow_display_currency") == "AMD")
        #expect(defaults.string(forKey: "finance_display_currency") == "USD")
        #expect(defaults.string(forKey: "card_display_currency") == "USD")
        #expect(defaults.string(forKey: "investment_display_currency") == "EUR")
        #expect(defaults.string(forKey: "credit_display_currency") == "USD")
    }
    
    @Test("AppState.selectedLanguage сохраняет значение в UserDefaults")
    func testSelectedLanguagePersistsToUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "selectedLanguage")
        UserDefaults.standard.synchronize()

        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }
        LanguageManager.shared.setLanguage(.system)

        let appState = AppState()
        appState.selectedLanguage = .english

        #expect(UserDefaults.standard.string(forKey: "selectedLanguage") == Language.english.rawValue)
    }
    
    @Test("LanguageManager устанавливает AppleLanguages для конкретного языка")
    func testLanguageManagerSetsAppleLanguagesForLanguage() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }
        
        LanguageManager.shared.setLanguage(.english)
        
        #expect(UserDefaults.standard.string(forKey: "selectedLanguage") == "en")
        #expect(UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] == ["en"])
    }
    
    @Test("LanguageManager удаляет AppleLanguages для системного языка")
    func testLanguageManagerRemovesAppleLanguagesForSystemLanguage() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }
        
        LanguageManager.shared.setLanguage(.english)
        
        LanguageManager.shared.setLanguage(.system)
        
        #expect(UserDefaults.standard.array(forKey: "AppleLanguages") as? [String] != ["en"])
        #expect(UserDefaults.standard.string(forKey: "selectedLanguage") == "system")
    }

    @Test("Смена языка через AppState сразу обновляет app localization без перезапуска")
    @MainActor
    func testAppStateLanguageSwitchUpdatesRuntimeLocalizedStringsImmediately() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }

        let appState = AppState()

        appState.selectedLanguage = .english
        #expect(AppLocalization.string("profile.title", locale: AppLocalization.currentAppLocale) == "Profile")
        #expect(AppLocalization.string("profile.language", locale: AppLocalization.currentAppLocale) == "Language")

        appState.selectedLanguage = .russian
        #expect(AppLocalization.string("profile.title", locale: AppLocalization.currentAppLocale) == "Профиль")
        #expect(AppLocalization.string("profile.language", locale: AppLocalization.currentAppLocale) == "Язык")
    }

    @Test("Explicit locale lookup bypasses runtime bundle language override")
    @MainActor
    func testExplicitLocaleLookupIgnoresRuntimeLanguageOverride() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }

        LanguageManager.shared.setLanguage(.simplifiedChinese)

        #expect(AppLocalization.string("calendar_range.preset.today", locale: Locale(identifier: "en_US")) == "Today")
        #expect(AppLocalization.string("calendar_range.sheet.start_date", locale: Locale(identifier: "ru_RU")) == "Дата начала")
    }

    @Test("Explicit locale lookup keeps converter promo copy stable under runtime language override")
    @MainActor
    func testExplicitLocaleLookupForConverterPromoIgnoresRuntimeLanguageOverride() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }

        LanguageManager.shared.setLanguage(.simplifiedChinese)

        #expect(AppLocalization.string("converter.share.promo_title", locale: Locale(identifier: "en_US")) == "Smarter money decisions, faster")
        #expect(AppLocalization.string("converter.share.promo_subtitle", locale: Locale(identifier: "en_US")) == "Built with Millio")
        #expect(AppLocalization.string("converter.share.promo_subtitle", locale: Locale(identifier: "ru_RU")) == "Снято в приложении Миллио")
    }

    @Test("LanguageManager выбирает system для поддерживаемых системных языков")
    func testLanguageManagerDefaultLanguageSupportedSystem() {
        #expect(LanguageManager.defaultLanguage(forPreferredLanguage: "ru-RU") == .system)
        #expect(LanguageManager.defaultLanguage(forPreferredLanguage: "en-US") == .system)
    }

    @Test("LanguageManager выбирает system для поддерживаемых языков, english — для остальных")
    func testLanguageManagerDefaultLanguageUnsupportedSystem() {
        #expect(LanguageManager.defaultLanguage(forPreferredLanguage: "de-DE") == .system)
        #expect(LanguageManager.defaultLanguage(forPreferredLanguage: "es-ES") == .system)
        #expect(LanguageManager.defaultLanguage(forPreferredLanguage: "zh-Hans-CN") == .system)
        #expect(LanguageManager.defaultLanguage(forPreferredLanguage: "fr-FR") == .english)
        #expect(LanguageManager.defaultLanguage(forPreferredLanguage: "ja-JP") == .english)
        #expect(LanguageManager.defaultLanguage(forPreferredLanguage: nil) == .english)
    }
}

@Suite(.serialized)
@MainActor
struct AppLifecycleUseCaseTests {
    private static func restoreDefaults(_ snapshots: [String: Any?], defaults: UserDefaults) {
        for (key, value) in snapshots {
            if let value {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    @Test("initialize переводит в onboarding при непройденном онбординге")
    func testInitializeSetsOnboardingWhenNotCompleted() async {
        let defaults = UserDefaults.standard
        let key = "hasCompletedOnboarding"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        defaults.set(false, forKey: key)
        
        let appState = AppState()
        appState.isBackupEnabled = false
        
        let useCase = AppLifecycleUseCase(appState: appState, backupManager: FakeBackupManager())
        await useCase.initialize()
        
        #expect(appState.lifecycle == .onboarding)
        #expect(appState.isICloudAvailable == false)
        #expect(appState.lastBackupDate == nil)
    }
    
    @Test("initialize переводит в ready при пройденном онбординге")
    func testInitializeSetsReadyWhenOnboardingCompleted() async {
        let defaults = UserDefaults.standard
        let key = "hasCompletedOnboarding"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        defaults.set(true, forKey: key)
        
        let appState = AppState()
        appState.isBackupEnabled = false
        
        let useCase = AppLifecycleUseCase(appState: appState, backupManager: FakeBackupManager())
        await useCase.initialize()
        
        #expect(appState.lifecycle == .ready)
    }

    @Test("initialize скрывает баннер быстрой настройки для legacy пользователей")
    func testInitializeSuppressesQuickSetupBannerForLegacyUsers() async {
        let defaults = UserDefaults.standard
        let keys = [
            "hasCompletedOnboarding",
            "quickSetupCompleted",
            "quickSetupBannerHidden",
            "quickSetupBannerMigrationApplied",
            "lastSeenAppVersion"
        ]
        let snapshot = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer { Self.restoreDefaults(snapshot, defaults: defaults) }

        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.removeObject(forKey: "quickSetupCompleted")
        defaults.set(false, forKey: "quickSetupBannerHidden")
        defaults.removeObject(forKey: "quickSetupBannerMigrationApplied")
        defaults.set("0.9 (1)", forKey: "lastSeenAppVersion")

        let appState = AppState()
        appState.isBackupEnabled = false

        let useCase = AppLifecycleUseCase(appState: appState, backupManager: FakeBackupManager())
        await useCase.initialize()

        #expect(SettingsManager.shared.isQuickSetupBannerHidden == true)
    }

    @Test("initialize не трогает баннер если статус quick setup уже известен")
    func testInitializeKeepsQuickSetupBannerWhenStatusStored() async {
        let defaults = UserDefaults.standard
        let keys = [
            "hasCompletedOnboarding",
            "quickSetupCompleted",
            "quickSetupBannerHidden",
            "quickSetupBannerMigrationApplied",
            "lastSeenAppVersion"
        ]
        let snapshot = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer { Self.restoreDefaults(snapshot, defaults: defaults) }

        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.set(false, forKey: "quickSetupCompleted")
        defaults.set(false, forKey: "quickSetupBannerHidden")
        defaults.removeObject(forKey: "quickSetupBannerMigrationApplied")
        defaults.set("0.9 (1)", forKey: "lastSeenAppVersion")

        let appState = AppState()
        appState.isBackupEnabled = false

        let useCase = AppLifecycleUseCase(appState: appState, backupManager: FakeBackupManager())
        await useCase.initialize()

        #expect(SettingsManager.shared.isQuickSetupBannerHidden == false)
    }

    @Test("initialize не скрывает баннер при первом запуске (без lastSeen версии)")
    func testInitializeDoesNotSuppressBannerOnFirstLaunch() async {
        let defaults = UserDefaults.standard
        let keys = [
            "hasCompletedOnboarding",
            "quickSetupCompleted",
            "quickSetupBannerHidden",
            "quickSetupBannerMigrationApplied",
            "lastSeenAppVersion"
        ]
        let snapshot = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer { Self.restoreDefaults(snapshot, defaults: defaults) }

        defaults.set(true, forKey: "hasCompletedOnboarding")
        defaults.removeObject(forKey: "quickSetupCompleted")
        defaults.set(false, forKey: "quickSetupBannerHidden")
        defaults.removeObject(forKey: "quickSetupBannerMigrationApplied")
        defaults.removeObject(forKey: "lastSeenAppVersion")

        let appState = AppState()
        appState.isBackupEnabled = false

        let useCase = AppLifecycleUseCase(appState: appState, backupManager: FakeBackupManager())
        await useCase.initialize()

        #expect(SettingsManager.shared.isQuickSetupBannerHidden == false)
    }

    @Test("initialize обновляет iCloud статус в фоне при включенном backup")
    func testInitializeRefreshesICloudStatusWhenBackupEnabled() async throws {
        let defaults = UserDefaults.standard
        let key = "hasCompletedOnboarding"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        defaults.set(true, forKey: key)
        
        let expectedDate = Date(timeIntervalSince1970: 123)
        let backupManager = FakeBackupManager(isAvailableResult: true, lastBackupInfoResult: BackupInfo(date: expectedDate, size: 1, version: "2.0.0"))
        
        let appState = AppState()
        appState.isBackupEnabled = true
        
        let useCase = AppLifecycleUseCase(appState: appState, backupManager: backupManager)
        await useCase.initialize()
        
        var didUpdate = false
        for _ in 0..<50 {
            if appState.isICloudAvailable == true, appState.lastBackupDate == expectedDate {
                didUpdate = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        
        #expect(didUpdate == true)
    }

    @Test("initialize обновляет iCloud статус даже при выключенном backup для recovery после reinstall")
    func testInitializeRefreshesICloudStatusWhenBackupDisabled() async throws {
        let defaults = UserDefaults.standard
        let key = "hasCompletedOnboarding"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        defaults.set(true, forKey: key)

        let expectedDate = Date(timeIntervalSince1970: 456)
        let backupManager = FakeBackupManager(isAvailableResult: true, lastBackupInfoResult: BackupInfo(date: expectedDate, size: 1, version: "2.0.0"))

        let appState = AppState()
        appState.isBackupEnabled = false

        let useCase = AppLifecycleUseCase(appState: appState, backupManager: backupManager)
        await useCase.initialize()

        var didUpdate = false
        for _ in 0..<50 {
            if appState.isICloudAvailable == true, appState.lastBackupDate == expectedDate {
                didUpdate = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(didUpdate == true)
    }

    @Test("initialize не запрашивает backup info если iCloud недоступен")
    func testInitializeSkipsBackupInfoLookupWhenICloudUnavailable() async throws {
        let defaults = UserDefaults.standard
        let key = "hasCompletedOnboarding"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        defaults.set(true, forKey: key)

        let backupManager = FakeBackupManager(
            isAvailableResult: false,
            lastBackupInfoResult: BackupInfo(date: Date(timeIntervalSince1970: 789), size: 1, version: "2.0.0")
        )

        let appState = AppState()
        appState.isBackupEnabled = true

        let useCase = AppLifecycleUseCase(appState: appState, backupManager: backupManager)
        await useCase.initialize()

        for _ in 0..<20 where backupManager.isAvailableCalls == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(backupManager.isAvailableCalls > 0)
        #expect(backupManager.lastBackupInfoCalls == 0)
        #expect(appState.isICloudAvailable == false)
        #expect(appState.lastBackupDate == nil)
    }

    @Test("initialize удерживает launching минимум указанное время")
    func testInitializeRespectsMinimumLaunchDuration() async throws {
        let defaults = UserDefaults.standard
        let key = "hasCompletedOnboarding"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        defaults.set(true, forKey: key)

        let appState = AppState()
        appState.isBackupEnabled = false
        let splashPrefs = FakeLaunchSplashPreferences(mode: .always, lastShownAt: nil)

        let useCase = AppLifecycleUseCase(
            appState: appState,
            backupManager: FakeBackupManager(),
            splashPreferences: splashPrefs,
            minimumLaunchDuration: 0.06
        )

        let start = ContinuousClock.now
        async let initialization: Void = useCase.initialize()

        try await Task.sleep(for: .milliseconds(20))
        #expect(appState.lifecycle == .launching)

        await initialization
        let elapsed = start.duration(to: .now)

        #expect(elapsed >= .milliseconds(55))
        #expect(appState.lifecycle == .ready)
    }

    @Test("initialize не удерживает splash когда режим показа выключен")
    func testInitializeSkipsSplashDelayWhenDisabled() async {
        let defaults = UserDefaults.standard
        let key = "hasCompletedOnboarding"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        defaults.set(true, forKey: key)

        let appState = AppState()
        appState.isBackupEnabled = false

        let splashPrefs = FakeLaunchSplashPreferences(mode: .disabled, lastShownAt: nil)
        let useCase = AppLifecycleUseCase(
            appState: appState,
            backupManager: FakeBackupManager(),
            splashPreferences: splashPrefs,
            minimumLaunchDuration: 0.2
        )

        await useCase.initialize()

        #expect(appState.lifecycle == .ready)
        #expect(splashPrefs.lastLaunchSplashShownAt == nil)
    }

    @Test("initialize пропускает splash в режиме раз в день, если уже показывали сегодня")
    func testInitializeSkipsSplashDelayWhenAlreadyShownToday() async {
        let defaults = UserDefaults.standard
        let key = "hasCompletedOnboarding"
        let previous = defaults.object(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        defaults.set(true, forKey: key)

        let now = Date(timeIntervalSince1970: 1_741_170_000)
        let appState = AppState()
        appState.isBackupEnabled = false

        let splashPrefs = FakeLaunchSplashPreferences(mode: .oncePerDay, lastShownAt: now)
        let useCase = AppLifecycleUseCase(
            appState: appState,
            backupManager: FakeBackupManager(),
            splashPreferences: splashPrefs,
            calendar: Calendar(identifier: .gregorian),
            nowProvider: { now },
            minimumLaunchDuration: 0.2
        )

        await useCase.initialize()

        #expect(appState.lifecycle == .ready)
        #expect(splashPrefs.lastLaunchSplashShownAt == now)
    }

    @Test("EntitlementPolicy временно снимает лимит тикеров во время beta")
    func testTrackedTickerLimitPolicy() {
        #expect(EntitlementPolicy.isTrackedTickerLimitProOnly == false)
        #expect(EntitlementPolicy.canAddTrackedTicker(isPro: false, currentTrackedTickers: 0) == true)
        #expect(EntitlementPolicy.canAddTrackedTicker(isPro: false, currentTrackedTickers: EntitlementPolicy.freeTrackedTickerLimit - 1) == true)
        #expect(EntitlementPolicy.canAddTrackedTicker(isPro: false, currentTrackedTickers: EntitlementPolicy.freeTrackedTickerLimit) == true)
        #expect(EntitlementPolicy.canAddTrackedTicker(isPro: true, currentTrackedTickers: 999) == true)
    }

    @Test("EntitlementPolicy временно открывает все карты кешбэка во время beta")
    func testCashbackCardLimitPolicy() {
        #expect(EntitlementPolicy.isCashbackCardsProOnly == false)
        #expect(EntitlementPolicy.canUseCashbackCard(isPro: false, cardIndex: 0) == true)
        #expect(EntitlementPolicy.canUseCashbackCard(isPro: false, cardIndex: EntitlementPolicy.freeCashbackCardLimit - 1) == true)
        #expect(EntitlementPolicy.canUseCashbackCard(isPro: false, cardIndex: EntitlementPolicy.freeCashbackCardLimit) == true)
        #expect(EntitlementPolicy.canUseCashbackCard(isPro: true, cardIndex: 100) == true)
    }

    @Test("EntitlementPolicy открывает crypto-конвертацию для всех во время beta")
    func testConverterCryptoPolicy() {
        #expect(EntitlementPolicy.isConverterCryptoProOnly == false)
        #expect(EntitlementPolicy.canUseConverterCrypto(isPro: false) == true)
        #expect(EntitlementPolicy.canUseConverterCrypto(isPro: true) == true)
    }

    @Test("EntitlementPolicy открывает акции и крипту в финансах для всех во время beta")
    func testFinanceMarketAccessPolicy() {
        #expect(EntitlementPolicy.isFinanceStocksProOnly == false)
        #expect(EntitlementPolicy.isFinanceCryptoProOnly == false)
        #expect(EntitlementPolicy.canUseFinanceStocks(isPro: false) == true)
        #expect(EntitlementPolicy.canUseFinanceStocks(isPro: true) == true)
        #expect(EntitlementPolicy.canUseFinanceCrypto(isPro: false) == true)
        #expect(EntitlementPolicy.canUseFinanceCrypto(isPro: true) == true)
    }

    @Test("EntitlementPolicy ограничивает продукты в финансах до 10 в Free и снимает лимит в PRO")
    func testFinanceProductLimitPolicy() {
        #expect(EntitlementPolicy.isFinanceProductsProOnly == true)
        #expect(EntitlementPolicy.canAddFinanceProduct(isPro: false, currentProducts: 0) == true)
        #expect(EntitlementPolicy.canAddFinanceProduct(isPro: false, currentProducts: EntitlementPolicy.freeFinanceProductLimit - 1) == true)
        #expect(EntitlementPolicy.canAddFinanceProduct(isPro: false, currentProducts: EntitlementPolicy.freeFinanceProductLimit) == false)
        #expect(EntitlementPolicy.canAddFinanceProduct(isPro: true, currentProducts: 999) == true)
    }

    @Test("EntitlementPolicy закрывает импорт кешбэка со скриншота в Free и открывает в PRO")
    func testCashbackScreenshotImportPolicy() {
        #expect(EntitlementPolicy.isCashbackScreenshotImportProOnly == true)
        #expect(EntitlementPolicy.canImportCashbackFromScreenshot(isPro: false) == false)
        #expect(EntitlementPolicy.canImportCashbackFromScreenshot(isPro: true) == true)
    }

    @Test("EntitlementPolicy закрывает импорт расходов со скриншота в Free и открывает в PRO")
    func testCashflowExpenseScreenshotImportPolicy() {
        #expect(EntitlementPolicy.isCashflowExpenseScreenshotImportProOnly == true)
        #expect(EntitlementPolicy.canImportCashflowExpensesFromScreenshot(isPro: false) == false)
        #expect(EntitlementPolicy.canImportCashflowExpensesFromScreenshot(isPro: true) == true)
    }
}

final class FakeBackupManager: BackupManagerProtocol {
    private let isAvailableResult: Bool
    private let lastBackupInfoResult: BackupInfo?
    private(set) var isAvailableCalls: Int = 0
    private(set) var lastBackupInfoCalls: Int = 0
    
    init(isAvailableResult: Bool = false, lastBackupInfoResult: BackupInfo? = nil) {
        self.isAvailableResult = isAvailableResult
        self.lastBackupInfoResult = lastBackupInfoResult
    }
    
    func isAvailable() async -> Bool {
        isAvailableCalls += 1
        return isAvailableResult
    }
    func backupNow() async throws {}
    func backupNow(passphrase: String?) async throws {}
    func saveVersionNow(passphrase: String?) async throws {}
    func exportVersion(recordName: String) async throws -> BackupTransferPayload {
        BackupTransferPayload(
            fileName: "backup.milliobackup",
            data: Data(),
            versionInfo: BackupVersionInfo(
                recordName: recordName,
                date: Date(timeIntervalSince1970: 0),
                size: 0,
                version: "1.0",
                isPinned: true
            )
        )
    }
    func importVersion(from data: Data) async throws -> BackupVersionInfo {
        BackupVersionInfo(
            recordName: "imported-test-backup",
            date: Date(timeIntervalSince1970: 0),
            size: Int64(data.count),
            version: "1.0",
            isPinned: true
        )
    }
    func restoreLatest() async throws {}
    func restoreLatest(passphrase: String?) async throws {}
    func restoreVersion(recordName: String, passphrase: String?) async throws {}
    func listBackupVersions() async -> [BackupVersionInfo] { [] }
    func deleteBackupVersion(recordName: String) async throws {}
    func lastBackupInfo() async -> BackupInfo? {
        lastBackupInfoCalls += 1
        return lastBackupInfoResult
    }
}

final class FakeLaunchSplashPreferences: LaunchSplashPreferences {
    var launchSplashDisplayMode: LaunchSplashDisplayMode
    var lastLaunchSplashShownAt: Date?

    init(mode: LaunchSplashDisplayMode, lastShownAt: Date?) {
        self.launchSplashDisplayMode = mode
        self.lastLaunchSplashShownAt = lastShownAt
    }
}
