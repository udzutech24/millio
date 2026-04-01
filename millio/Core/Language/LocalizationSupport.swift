//
//  LocalizationSupport.swift
//  millio
//
//  Created by Codex on 30.03.2026.
//

import Foundation

enum LocalizationReleaseReadiness: String {
    case releaseReady
    case planned
}

enum LocalizationSupport {
    static let fallbackLanguage: Language = .english
    /// Public selectors expose the three product languages that must work today.
    /// Hardening is enforced through tests and UI audits rather than hiding a language.
    static let releaseReadySelectableLanguages: [Language] = [.system, .english, .russian, .simplifiedChinese]

    static var userSelectableLanguages: [Language] {
        releaseReadySelectableLanguages
    }

    static func releaseReadiness(for language: Language) -> LocalizationReleaseReadiness {
        switch language {
        case .system, .english, .russian, .simplifiedChinese:
            return .releaseReady
        }
    }

    static func resolvedLanguage(
        for selectedLanguage: Language,
        fallbackLocale: Locale = .autoupdatingCurrent
    ) -> Language {
        guard selectedLanguage == .system else {
            return selectedLanguage
        }

        switch effectiveLanguage(for: fallbackLocale) {
        case Language.russian.rawValue:
            return .russian
        case Language.simplifiedChinese.rawValue:
            return .simplifiedChinese
        case Language.english.rawValue:
            return .english
        default:
            return fallbackLanguage
        }
    }

    static func resolvedLocale(
        for selectedLanguage: Language,
        fallbackLocale: Locale = .autoupdatingCurrent
    ) -> Locale {
        resolvedLanguage(for: selectedLanguage, fallbackLocale: fallbackLocale).locale ?? fallbackLocale
    }

    static func shouldUseSystemLanguage(_ preferredLanguage: String?) -> Bool {
        normalizedLanguageCode(from: preferredLanguage) == Language.russian.rawValue
            || normalizedLanguageCode(from: preferredLanguage) == Language.simplifiedChinese.rawValue
            || normalizedLanguageCode(from: preferredLanguage) == Language.english.rawValue
    }

    static func quickSetupSelectableLanguages(
        preferredLanguageIdentifiers: [String],
        locale: Locale
    ) -> [Language] {
        _ = preferredLanguageIdentifiers
        _ = locale
        return releaseReadySelectableLanguages
    }

    static func normalizedLanguageCode(from identifier: String?) -> String {
        guard let identifier else {
            return ""
        }

        let normalizedIdentifier = identifier.replacingOccurrences(of: "_", with: "-")
        let segments = normalizedIdentifier
            .split(separator: "-")
            .map { String($0).lowercased() }

        guard let rawLanguageCode = segments.first else {
            return ""
        }

        if rawLanguageCode == "zh" {
            let hasHansScript = segments.contains("hans")
                || normalizedIdentifier.lowercased().contains("zh-hans")
            if hasHansScript {
                return Language.simplifiedChinese.rawValue
            }
        }

        return rawLanguageCode
    }

    static func effectiveLanguage(for locale: Locale) -> String {
        if #available(iOS 16.0, *) {
            let languageCode = locale.language.languageCode?.identifier.lowercased() ?? ""
            let scriptCode = locale.language.script?.identifier.lowercased()

            if languageCode == "zh", scriptCode == "hans" {
                return Language.simplifiedChinese.rawValue
            }

            if !languageCode.isEmpty {
                return normalizedLanguageCode(from: locale.identifier)
            }
        }

        return normalizedLanguageCode(from: locale.identifier)
    }

    static func locale(_ locale: Locale, matches language: Language) -> Bool {
        effectiveLanguage(for: locale) == normalizedLanguageCode(from: language.rawValue)
    }

    static func presentationLocale(
        for requestedLocale: Locale,
        selectedLanguage: Language = LanguageManager.shared.currentLanguage,
        currentDeviceLocales: [Locale] = [.autoupdatingCurrent, .current]
    ) -> Locale {
        guard let appLocale = selectedLanguage.locale else {
            return requestedLocale
        }

        let requestedIdentifier = requestedLocale.identifier.lowercased()
        let currentIdentifiers = Set(currentDeviceLocales.map { $0.identifier.lowercased() })

        guard currentIdentifiers.contains(requestedIdentifier) else {
            return requestedLocale
        }

        return appLocale
    }
}
