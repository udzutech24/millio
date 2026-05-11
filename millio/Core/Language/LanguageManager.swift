//
//  LanguageManager.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import OSLog

protocol LanguageManagerProtocol {
    var currentLanguage: Language { get }
    func setLanguage(_ language: Language)
}

final class LanguageManager: LanguageManagerProtocol {
    static let shared = LanguageManager()
    private static let languageLock = NSRecursiveLock()
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "LanguageManager")
    private let userDefaultsKey = "selectedLanguage"

    private var storedCurrentLanguage: Language {
        didSet {
            logger.info("Language changed to: \(self.storedCurrentLanguage.rawValue)")
        }
    }

    var currentLanguage: Language {
        Self.languageLock.lock()
        defer { Self.languageLock.unlock() }
        return storedCurrentLanguage
    }

    /// Возвращает bundle для текущего языка приложения.
    /// Используется как явный `bundle:` параметр в `String(localized:)`.
    var currentBundle: Bundle {
        Self.languageLock.lock()
        defer { Self.languageLock.unlock() }
        guard let locale = storedCurrentLanguage.locale,
              let lb = AppLocalization.localizedBundle(for: locale, bundle: .main)
        else { return .main }
        return lb
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
           let language = Language(rawValue: saved) {
            self.storedCurrentLanguage = language
        } else {
            let fallback = Self.defaultLanguage(forPreferredLanguage: Locale.preferredLanguages.first)
            self.storedCurrentLanguage = fallback
            UserDefaults.standard.set(fallback.rawValue, forKey: userDefaultsKey)

            if let locale = fallback.locale {
                UserDefaults.standard.set([locale.identifier], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            UserDefaults.standard.synchronize()
        }

        BundleLanguageOverride.apply(language: storedCurrentLanguage)
    }
    
    func setLanguage(_ language: Language) {
        Self.languageLock.lock()
        defer { Self.languageLock.unlock() }

        storedCurrentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: userDefaultsKey)
        BundleLanguageOverride.apply(language: language)
        
        // Применяем locale для локализации
        if let locale = language.locale {
            UserDefaults.standard.set([locale.identifier], forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        } else {
            // Для системного языка удаляем настройку
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            UserDefaults.standard.synchronize()
        }
    }

    static func withLockedLanguageMutation<T>(_ body: () throws -> T) rethrows -> T {
        languageLock.lock()
        defer { languageLock.unlock() }
        return try body()
    }

    static func defaultLanguage(forPreferredLanguage preferredLanguage: String?) -> Language {
        guard let preferredLanguage else {
            return .english
        }

        if LocalizationSupport.shouldUseSystemLanguage(preferredLanguage) {
            return .system
        }
        return .english
    }
}
