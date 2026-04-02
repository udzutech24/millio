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
            return "English"
        case .russian:
            return "Русский"
        case .simplifiedChinese:
            return "中文"
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
        }
    }
}
