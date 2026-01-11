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
    
    private init() {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
           let language = Language(rawValue: saved) {
            self.currentLanguage = language
        } else {
            self.currentLanguage = .system
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
}
