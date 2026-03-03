//
//  ProfileLegalLinks.swift
//  millio
//
//  Created by Codex on 03.03.2026.
//

import Foundation

/// Centralized mapping for profile legal document links by selected app language.
struct ProfileLegalLinks {
    let privacyURL: URL
    let termsURL: URL
    let privacyTitle: String
    let termsTitle: String

    static func make(for language: Language, fallbackLocale: Locale = .current) -> ProfileLegalLinks {
        let isRussian = isRussianLanguage(language, fallbackLocale: fallbackLocale)

        if isRussian {
            return ProfileLegalLinks(
                privacyURL: URL(string: "https://millio.udzutech.com/?lang=ru&page=privacy")!,
                termsURL: URL(string: "https://millio.udzutech.com/?lang=ru&page=terms")!,
                privacyTitle: "Политика конфиденциальности",
                termsTitle: "Пользовательское соглашение"
            )
        }

        return ProfileLegalLinks(
            privacyURL: URL(string: "https://millio.udzutech.com/?lang=en&page=privacy")!,
            termsURL: URL(string: "https://millio.udzutech.com/?lang=en&page=terms")!,
            privacyTitle: "Privacy Policy",
            termsTitle: "Terms of Use"
        )
    }

    private static func isRussianLanguage(_ language: Language, fallbackLocale: Locale) -> Bool {
        switch language {
        case .russian:
            return true
        case .english:
            return false
        case .system:
            return fallbackLocale.language.languageCode?.identifier.lowercased().hasPrefix("ru") == true
        }
    }
}
