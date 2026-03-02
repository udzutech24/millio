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
        
        // Сбрасываем LanguageManager, устанавливая системный язык
        // Это нужно, так как LanguageManager - singleton и может иметь старое значение
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
    
    @Test("AppState.isPro зависит от subscriptionStatus")
    func testIsProComputedFromSubscriptionStatus() {
        let appState = AppState()
        
        appState.subscriptionStatus = .notSubscribed
        #expect(appState.isPro == false)
        
        appState.subscriptionStatus = .trial
        #expect(appState.isPro == true)
        
        appState.subscriptionStatus = .subscribed
        #expect(appState.isPro == true)
        
        appState.subscriptionStatus = .expired
        #expect(appState.isPro == false)
    }
    
    @Test("AppState сохраняет primaryCurrencyCode нормализованным и не принимает пустое значение")
    func testPrimaryCurrencyCodeNormalizationAndEmptyGuard() {
        UserDefaults.standard.removeObject(forKey: "primaryCurrencyCode")
        UserDefaults.standard.synchronize()
        
        let appState = AppState()
        #expect(appState.primaryCurrencyCode == "RUB")
        
        appState.primaryCurrencyCode = " usd "
        #expect(appState.primaryCurrencyCode == "USD")
        #expect(SettingsManager.shared.primaryCurrencyCode == "USD")
        
        appState.primaryCurrencyCode = "   "
        #expect(appState.primaryCurrencyCode == "USD")
        #expect(SettingsManager.shared.primaryCurrencyCode == "USD")
    }

    @Test("AppState при смене primaryCurrencyCode мигрирует display currency только если модуль следовал прошлой основной")
    func testPrimaryCurrencyCodeMigratesFollowingDisplayCurrencies() {
        let defaults = UserDefaults.standard
        let primaryKey = "primaryCurrencyCode"
        let keys = [
            "cashflow_display_currency",
            "finance_display_currency",
            "card_display_currency",
            "investment_display_currency",
            "credit_display_currency"
        ]
        let originalPrimary = defaults.string(forKey: primaryKey)
        let originalValues = keys.reduce(into: [String: String?]()) { partialResult, key in
            partialResult[key] = defaults.string(forKey: key)
        }
        defer {
            if let originalPrimary {
                defaults.set(originalPrimary, forKey: primaryKey)
            } else {
                defaults.removeObject(forKey: primaryKey)
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
        defaults.set("RUB", forKey: "cashflow_display_currency")
        defaults.set("USD", forKey: "finance_display_currency")
        defaults.set("RUB", forKey: "card_display_currency")
        defaults.set("EUR", forKey: "investment_display_currency")
        defaults.set("RUB", forKey: "credit_display_currency")

        let appState = AppState()
        appState.primaryCurrencyCode = "USD"

        #expect(defaults.string(forKey: "cashflow_display_currency") == "RUB")
        #expect(defaults.string(forKey: "finance_display_currency") == "USD")
        #expect(defaults.string(forKey: "card_display_currency") == "USD")
        #expect(defaults.string(forKey: "investment_display_currency") == "EUR")
        #expect(defaults.string(forKey: "credit_display_currency") == "USD")
    }
    
    @Test("AppState.selectedLanguage сохраняет значение в UserDefaults")
    func testSelectedLanguagePersistsToUserDefaults() {
        UserDefaults.standard.removeObject(forKey: "selectedLanguage")
        UserDefaults.standard.synchronize()
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

    @Test("LanguageManager выбирает system для поддерживаемых системных языков")
    func testLanguageManagerDefaultLanguageSupportedSystem() {
        #expect(LanguageManager.defaultLanguage(forPreferredLanguage: "ru-RU") == .system)
        #expect(LanguageManager.defaultLanguage(forPreferredLanguage: "en-US") == .system)
    }

    @Test("LanguageManager выбирает english для неподдерживаемого системного языка")
    func testLanguageManagerDefaultLanguageUnsupportedSystem() {
        #expect(LanguageManager.defaultLanguage(forPreferredLanguage: "de-DE") == .english)
        #expect(LanguageManager.defaultLanguage(forPreferredLanguage: nil) == .english)
    }
}

@Suite(.serialized)
@MainActor
struct AppLifecycleUseCaseTests {
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
}

final class FakeBackupManager: BackupManagerProtocol {
    private let isAvailableResult: Bool
    private let lastBackupInfoResult: BackupInfo?
    
    init(isAvailableResult: Bool = false, lastBackupInfoResult: BackupInfo? = nil) {
        self.isAvailableResult = isAvailableResult
        self.lastBackupInfoResult = lastBackupInfoResult
    }
    
    func isAvailable() async -> Bool { isAvailableResult }
    func backupNow() async throws {}
    func backupNow(passphrase: String?) async throws {}
    func restoreLatest() async throws {}
    func restoreLatest(passphrase: String?) async throws {}
    func lastBackupInfo() async -> BackupInfo? { lastBackupInfoResult }
}
