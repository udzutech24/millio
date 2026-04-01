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
    case simplifiedChinese = "zh-Hans"
    
    var displayName: String {
        displayName(for: AppLocalization.currentAppLocale)
    }

    func displayName(for locale: Locale) -> String {
        switch self {
        case .system:
            return AppLocalization.string("language.option.system", locale: locale)
        case .english:
            return AppLocalization.string("language.option.english", locale: locale)
        case .russian:
            return AppLocalization.string("language.option.russian", locale: locale)
        case .simplifiedChinese:
            return AppLocalization.string("language.option.chinese_simplified", locale: locale)
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
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        }
    }
}
