//
//  ProfileLegalLinks.swift
//  millio
//
//  Created by Codex on 03.03.2026.
//

import Foundation

/// Centralized mapping for profile legal document links by selected app language.
struct ProfileLegalLinks {
    private static let appleStandardEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    let privacyURL: URL
    let termsURL: URL
    let privacyTitle: String
    let termsTitle: String

    static func make(for language: Language, fallbackLocale: Locale = .current) -> ProfileLegalLinks {
        let isRussian = isRussianLanguage(language, fallbackLocale: fallbackLocale)

        if isRussian {
            return ProfileLegalLinks(
                privacyURL: URL(string: "https://millio.udzutech.com/?lang=ru&page=privacy")!,
                termsURL: appleStandardEULAURL,
                privacyTitle: "Политика конфиденциальности",
                termsTitle: "Условия использования (EULA)"
            )
        }

        return ProfileLegalLinks(
            privacyURL: URL(string: "https://millio.udzutech.com/?lang=en&page=privacy")!,
            termsURL: appleStandardEULAURL,
            privacyTitle: "Privacy Policy",
            termsTitle: "Terms of Use (EULA)"
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
