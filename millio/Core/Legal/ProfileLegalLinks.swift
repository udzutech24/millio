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

    static func make(for language: Language, fallbackLocale: Locale = AppLocalization.currentAppLocale) -> ProfileLegalLinks {
        let resolvedLanguage = LocalizationSupport.resolvedLanguage(for: language, fallbackLocale: fallbackLocale)
        let locale = resolvedLanguage.locale ?? fallbackLocale
        let privacyTitle = AppLocalization.string("legal.privacy_title", locale: locale, fallback: "Privacy Policy")
        let termsTitle = AppLocalization.string("legal.terms_title", locale: locale, fallback: "Terms of Use (EULA)")

        switch resolvedLanguage {
        case .russian:
            return ProfileLegalLinks(
                privacyURL: URL(string: "https://millio.udzutech.com/?lang=ru&page=privacy")!,
                termsURL: appleStandardEULAURL,
                privacyTitle: privacyTitle,
                termsTitle: termsTitle
            )
        case .simplifiedChinese:
            return ProfileLegalLinks(
                privacyURL: URL(string: "https://millio.udzutech.com/?lang=en&page=privacy")!,
                termsURL: appleStandardEULAURL,
                privacyTitle: privacyTitle,
                termsTitle: termsTitle
            )
        case .english, .system, .german, .spanish, .turkish, .french:
            return ProfileLegalLinks(
                privacyURL: URL(string: "https://millio.udzutech.com/?lang=en&page=privacy")!,
                termsURL: appleStandardEULAURL,
                privacyTitle: privacyTitle,
                termsTitle: termsTitle
            )
        }
    }
}
