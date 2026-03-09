import Foundation

enum QuickSetupLocalization {
    static func text(locale: Locale, ru: String, en: String) -> String {
        isRussian(locale) ? ru : en
    }

    static func isRussian(_ locale: Locale) -> Bool {
        normalizedLanguageCode(from: locale.identifier) == "ru"
    }

    private static func normalizedLanguageCode(from identifier: String) -> String {
        String(
            identifier
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .first?
                .lowercased() ?? ""
        )
    }
}
