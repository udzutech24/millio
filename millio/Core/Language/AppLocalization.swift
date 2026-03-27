//
//  AppLocalization.swift
//  millio
//
//  Created by Александр Сидоркин on 04.03.2026.
//

import Foundation

enum AppLocalization {
    static var currentAppLocale: Locale {
        LanguageManager.shared.currentLanguage.locale ?? Locale.autoupdatingCurrent
    }

    /// Resolves a localized string for an explicit locale, independent of app-wide language overrides.
    static func string(_ key: String, locale: Locale, fallback: String? = nil, bundle: Bundle = .main) -> String {
        let languageCode = preferredLanguageCode(from: locale)
        let localizationBundle = bundle.bundle(forLanguageCode: languageCode) ?? bundle
        return localizationBundle.localizedString(forKey: key, value: fallback, table: nil)
    }

    private static func preferredLanguageCode(from locale: Locale) -> String {
        if #available(iOS 16.0, *),
           let code = locale.language.languageCode?.identifier,
           !code.isEmpty {
            return code.lowercased()
        }

        if let code = locale.identifier
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased() {
            return String(code)
        }

        return "en"
    }
}

private extension Bundle {
    func bundle(forLanguageCode languageCode: String) -> Bundle? {
        let candidates = [languageCode, "en", developmentLocalization].compactMap { $0 }

        for candidate in candidates {
            guard let path = path(forResource: candidate, ofType: "lproj"),
                  let localizedBundle = Bundle(path: path) else {
                continue
            }
            return localizedBundle
        }

        return nil
    }
}
