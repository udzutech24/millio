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
    case german = "de"
    case spanish = "es"
    case turkish = "tr"
    case french = "fr"

    var displayName: String {
        displayName(for: AppLocalization.currentAppLocale)
    }

    func displayName(for locale: Locale) -> String {
        switch self {
        case .system:
            return AppLocalization.string("language.option.system", locale: locale)
        case .english:
            return "English"
        case .russian:
            return "Русский"
        case .simplifiedChinese:
            return "中文"
        case .german:
            return "Deutsch"
        case .spanish:
            return "Español"
        case .turkish:
            return "Türkçe"
        case .french:
            return "Français"
        }
    }

    /// Search stays forgiving even though visible labels are self-names.
    /// This keeps queries like "китайский" and "english" working.
    func searchableNames(for locale: Locale) -> [String] {
        var names = [displayName(for: locale)]

        switch self {
        case .system:
            names.append(AppLocalization.string("language.option.system", locale: locale))
        case .english:
            names.append(AppLocalization.string("language.option.english", locale: locale))
            names.append("English")
        case .russian:
            names.append(AppLocalization.string("language.option.russian", locale: locale))
            names.append("Russian")
            names.append("Русский")
        case .simplifiedChinese:
            names.append(AppLocalization.string("language.option.chinese_simplified", locale: locale))
            names.append("Chinese")
            names.append("Simplified Chinese")
            names.append("中文")
            names.append("简体中文")
            names.append("Китайский")
        case .german:
            names.append("German")
            names.append("Deutsch")
            names.append("Немецкий")
        case .spanish:
            names.append(AppLocalization.string("language.option.spanish", locale: locale))
            names.append("Spanish")
            names.append("Español")
            names.append("Испанский")
        case .turkish:
            names.append(AppLocalization.string("language.option.turkish", locale: locale))
            names.append("Turkish")
            names.append("Türkçe")
            names.append("Турецкий")
        case .french:
            names.append(AppLocalization.string("language.option.french", locale: locale))
            names.append("French")
            names.append("Français")
            names.append("Французский")
        }

        var seen = Set<String>()
        return names.filter { candidate in
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
            seen.insert(normalized)
            return true
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
        case .german:
            return Locale(identifier: "de")
        case .spanish:
            return Locale(identifier: "es")
        case .turkish:
            return Locale(identifier: "tr")
        case .french:
            return Locale(identifier: "fr")
        }
    }
}
