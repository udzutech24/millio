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
        // Prefer the source string catalog first. Runtime bundle overrides and
        // compiled `.lproj` assets can lag behind the requested locale and return
        // a valid string in the wrong language, which is worse than a miss.
        if let catalogLocalized = ExplicitStringCatalog.shared.localizedString(for: key, locale: locale) {
            return catalogLocalized
        }

        // When the caller asks for the active app locale, prefer the runtime
        // bundle override after the source catalog lookup. This keeps live
        // language switching working for entries that may exist only in the
        // built bundle while avoiding stale-language leakage.
        if sharesLanguageCandidates(locale, currentAppLocale) {
            let localized = bundle.localizedString(forKey: key, value: fallback, table: nil)
            if localized != key {
                return localized
            }
        }

        // Runtime bundle overrides are useful for live language switching, but they
        // break explicit locale lookups because `Bundle.main` always resolves through
        // the currently selected app language. Walk locale candidates manually only
        // after the source catalog lookup, so standalone bundles remain a fallback
        // rather than a source of cross-language leakage.
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
        let catalogBundle = freshBundleCopy(for: bundle) ?? bundle
        let catalogLocalized = BundleLanguageOverride.performWithoutOverride {
            String(
                localized: String.LocalizationValue(key),
                bundle: catalogBundle,
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

    private static func freshBundleCopy(for bundle: Bundle) -> Bundle? {
        Bundle(path: bundle.bundlePath)
    }
}

private struct ExplicitStringCatalog {
    static let shared = ExplicitStringCatalog()

    private let sourceLanguage: String?
    private let strings: [String: [String: String]]

    init() {
        for catalogURL in Self.catalogURLs() {
            do {
                let data = try Data(contentsOf: catalogURL)
                let jsonObject = try JSONSerialization.jsonObject(with: data)
                guard
                    let root = jsonObject as? [String: Any],
                    let entries = root["strings"] as? [String: Any]
                else {
                    continue
                }

                self.sourceLanguage = LocalizationSupport.normalizedLanguageCode(from: root["sourceLanguage"] as? String)
                self.strings = Self.parse(entries)
                return
            } catch {
                continue
            }
        }

        self.sourceLanguage = nil
        self.strings = [:]
    }

    func localizedString(for key: String, locale: Locale) -> String? {
        guard let localizations = strings[key] else {
            return nil
        }

        let candidates = AppLocalization.preferredLanguageCandidates(
            from: locale,
            includeDevelopmentFallback: false
        )

        for candidate in candidates {
            if let value = localizedValue(in: localizations, for: candidate) {
                return value
            }
        }

        if let sourceLanguage, let value = localizedValue(in: localizations, for: sourceLanguage) {
            return value
        }

        return nil
    }

    private static func parse(_ entries: [String: Any]) -> [String: [String: String]] {
        var parsed: [String: [String: String]] = [:]

        for (key, value) in entries {
            guard
                let entry = value as? [String: Any],
                let localizations = entry["localizations"] as? [String: Any]
            else {
                continue
            }

            var localizedValues: [String: String] = [:]
            for (localeIdentifier, localizationValue) in localizations {
                guard
                    let localization = localizationValue as? [String: Any],
                    let stringUnit = localization["stringUnit"] as? [String: Any],
                    let stringValue = stringUnit["value"] as? String,
                    !stringValue.isEmpty
                else {
                    continue
                }

                for candidate in localeCandidates(for: localeIdentifier) {
                    localizedValues[candidate] = stringValue
                }
            }

            if !localizedValues.isEmpty {
                parsed[key] = localizedValues
            }
        }

        return parsed
    }

    private static func catalogURLs(filePath: String = #filePath) -> [URL] {
        var urls: [URL] = []

        var directory = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        let fileManager = FileManager.default

        for _ in 0..<12 {
            let candidate = directory
                .appendingPathComponent("millio", isDirectory: true)
                .appendingPathComponent("Localizable.xcstrings", isDirectory: false)
            if fileManager.fileExists(atPath: candidate.path) {
                urls.append(candidate)
                break
            }

            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }

        if let bundledURL = AppLocalization.resourceBundle.url(forResource: "Localizable", withExtension: "xcstrings") {
            urls.append(bundledURL)
        }

        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.path).inserted
        }
    }

    private func localizedValue(in localizations: [String: String], for localeIdentifier: String) -> String? {
        for candidate in Self.localeCandidates(for: localeIdentifier) {
            if let value = localizations[candidate], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func localeCandidates(for localeIdentifier: String) -> [String] {
        var candidates: [String] = []
        let normalizedIdentifier = localeIdentifier.replacingOccurrences(of: "_", with: "-")

        if !localeIdentifier.isEmpty {
            candidates.append(localeIdentifier)
        }
        if !normalizedIdentifier.isEmpty {
            candidates.append(normalizedIdentifier)
        }

        let normalizedLanguage = LocalizationSupport.normalizedLanguageCode(from: normalizedIdentifier)
        if !normalizedLanguage.isEmpty {
            candidates.append(normalizedLanguage)
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            guard !candidate.isEmpty, !seen.contains(candidate) else { return false }
            seen.insert(candidate)
            return true
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
