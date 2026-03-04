//
//  Language.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

enum Language: String, Codable, CaseIterable, Hashable {
    case system = "system"
    case english = "en"
    case russian = "ru"
    
    var displayName: String {
        displayName(for: locale ?? Locale.current)
    }

    func displayName(for locale: Locale) -> String {
        switch self {
        case .system:
            return String(localized: "language.option.system", locale: locale)
        case .english:
            return String(localized: "language.option.english", locale: locale)
        case .russian:
            return String(localized: "language.option.russian", locale: locale)
        }
    }
    
    var locale: Locale? {
        switch self {
        case .system:
            return nil
        case .english:
            return Locale(identifier: "en")
        case .russian:
            return Locale(identifier: "ru")
        }
    }
}
