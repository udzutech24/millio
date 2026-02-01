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
}
