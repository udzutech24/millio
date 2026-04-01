//
//  AppLocalization.swift
//  millio
//
//  Created by Александр Сидоркин on 04.03.2026.
//

import Foundation

private final class AppLocalizationBundleMarker {}

enum AppLocalization {
    static let resourceBundle = Bundle(for: AppLocalizationBundleMarker.self)

    static var currentAppLocale: Locale {
        LocalizationSupport.resolvedLocale(
            for: LanguageManager.shared.currentLanguage,
            fallbackLocale: .autoupdatingCurrent
        )
    }

    static func localizedBundle(for locale: Locale, bundle: Bundle = resourceBundle) -> Bundle? {
        bundle.bundle(for: locale)
    }

    /// Resolves a localized string for an explicit locale, independent of app-wide language overrides.
    static func string(_ key: String, locale: Locale, fallback: String? = nil, bundle: Bundle = resourceBundle) -> String {
        // When the caller asks for the active app locale, prefer the runtime
        // bundle override directly. This keeps hot reload working for string
        // catalog entries that may not exist as standalone `.lproj` bundles.
        if sharesLanguageCandidates(locale, currentAppLocale) {
            let localized = bundle.localizedString(forKey: key, value: fallback, table: nil)
            if localized != key {
                return localized
            }
        }

        // Runtime bundle overrides are useful for live language switching, but they
        // break explicit locale lookups because `Bundle.main` always resolves through
        // the currently selected app language. Walk locale candidates manually, but
        // keep that walk strict: once we fall through to the app's development
        // localization here, locale-specific lookups can silently return the wrong
        // language (for example Chinese for Russian tests).
        let candidates = preferredLanguageCandidates(from: locale, includeDevelopmentFallback: false)
        for candidate in candidates {
            guard let localizedBundle = bundle.localizedBundle(forResource: candidate) else {
                continue
            }

            let localized = BundleLanguageOverride.rawLocalizedString(
                from: localizedBundle,
                key: key,
                value: fallback,
                table: nil
            )
            if localized != key {
                return localized
            }
        }

        // String catalogs can resolve explicit locales even when standalone
        // `.lproj` bundles are absent in source checkout. Use the locale-aware
        // Foundation resolver as a final explicit-locale lookup before falling
        // back to the provided default value or key.
        let resolvedExplicitLocale = canonicalExplicitLocale(for: locale)
        let catalogLocalized = BundleLanguageOverride.performWithoutOverride {
            String(
                localized: String.LocalizationValue(key),
                bundle: bundle,
                locale: resolvedExplicitLocale
            )
        }
        if catalogLocalized != key {
            return catalogLocalized
        }

        return fallback ?? key
    }

    static func preferredLanguageCandidates(from locale: Locale) -> [String] {
        preferredLanguageCandidates(from: locale, includeDevelopmentFallback: true)
    }

    fileprivate static func preferredLanguageCandidates(
        from locale: Locale,
        includeDevelopmentFallback: Bool
    ) -> [String] {
        var candidates: [String] = []

        let normalizedIdentifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        if !normalizedIdentifier.isEmpty {
            candidates.append(normalizedIdentifier)

            let components = normalizedIdentifier.split(separator: "-")
            if components.count >= 2 {
                for index in stride(from: components.count - 1, through: 2, by: -1) {
                    candidates.append(components.prefix(index).joined(separator: "-"))
                }
            }
        }

        if #available(iOS 16.0, *),
           let code = locale.language.languageCode?.identifier.lowercased(),
           !code.isEmpty {
            if code == "zh",
               let script = locale.language.script?.identifier,
               !script.isEmpty {
                candidates.append("\(code)-\(script)")
            }
            candidates.append(code)
        }

        if let code = normalizedIdentifier
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased() {
            candidates.append(String(code))
        }

        if includeDevelopmentFallback {
            candidates.append("en")
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            guard !candidate.isEmpty, !seen.contains(candidate) else { return false }
            seen.insert(candidate)
            return true
        }
    }

    private static func sharesLanguageCandidates(_ lhs: Locale, _ rhs: Locale) -> Bool {
        // Do not treat the shared development-language fallback as a language
        // match. Otherwise explicit locale lookups can incorrectly resolve
        // through the currently selected app language.
        let rhsCandidates = Set(preferredLanguageCandidates(from: rhs, includeDevelopmentFallback: false))
        return preferredLanguageCandidates(from: lhs, includeDevelopmentFallback: false)
            .contains(where: rhsCandidates.contains)
    }

    private static func canonicalExplicitLocale(for locale: Locale) -> Locale {
        switch LocalizationSupport.effectiveLanguage(for: locale) {
        case Language.russian.rawValue:
            return Locale(identifier: "ru_RU")
        case Language.simplifiedChinese.rawValue:
            return Locale(identifier: "zh_Hans_CN")
        case Language.english.rawValue:
            return Locale(identifier: "en_US")
        default:
            return locale
        }
    }
}

private extension Bundle {
    func localizedBundle(forResource candidate: String) -> Bundle? {
        guard let path = path(forResource: candidate, ofType: "lproj") else {
            return nil
        }
        return Bundle(path: path)
    }

    func bundle(for locale: Locale) -> Bundle? {
        let candidates = AppLocalization.preferredLanguageCandidates(
            from: locale,
            includeDevelopmentFallback: false
        )
        for candidate in candidates {
            guard let localizedBundle = localizedBundle(forResource: candidate) else {
                continue
            }
            return localizedBundle
        }

        return nil
    }
}
