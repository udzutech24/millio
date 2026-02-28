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
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "LanguageManager")
    private let userDefaultsKey = "selectedLanguage"
    
    private(set) var currentLanguage: Language {
        didSet {
            logger.info("Language changed to: \(self.currentLanguage.rawValue)")
        }
    }

    private static let supportedSystemLanguageCodes: Set<String> = ["ru", "en"]
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
           let language = Language(rawValue: saved) {
            self.currentLanguage = language
        } else {
            let fallback = Self.defaultLanguage(forPreferredLanguage: Locale.preferredLanguages.first)
            self.currentLanguage = fallback
            UserDefaults.standard.set(fallback.rawValue, forKey: userDefaultsKey)

            if let locale = fallback.locale {
                UserDefaults.standard.set([locale.identifier], forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            UserDefaults.standard.synchronize()
        }
    }
    
    func setLanguage(_ language: Language) {
        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: userDefaultsKey)
        
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

    static func defaultLanguage(forPreferredLanguage preferredLanguage: String?) -> Language {
        guard
            let preferredLanguage,
            let rawLanguageCode = preferredLanguage.split(whereSeparator: { $0 == "-" || $0 == "_" }).first
        else {
            return .english
        }

        let languageCode = String(rawLanguageCode).lowercased()
        if supportedSystemLanguageCodes.contains(languageCode) {
            return .system
        }
        return .english
    }
}
