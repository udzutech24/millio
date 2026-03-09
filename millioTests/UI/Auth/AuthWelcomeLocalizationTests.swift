import Foundation
import Testing
@testable import millio

struct AuthWelcomeLocalizationTests {
    private func localized(_ key: String, localeIdentifier: String) -> String {
        // Use a type from the app module to resolve the bundle that contains Localizable.xcstrings.
        let bundle = Bundle(for: SettingsManager.self)
        return String(
            localized: String.LocalizationValue(key),
            bundle: bundle,
            locale: Locale(identifier: localeIdentifier)
        )
    }

    private func assertNoTrailingPeriod(_ value: String, key: String, locale: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // `#expect` takes `Comment?`, not `String`. Put context into the compared values instead.
        #expect((key, locale, trimmed.isEmpty) == (key, locale, false))
        #expect((key, locale, trimmed.hasSuffix(".")) == (key, locale, false))
    }

    @Test("Auth welcome copy is localized and has no trailing periods")
    func authWelcomeCopyNoTrailingPeriods() {
        let cases: [(key: String, locale: String, expected: String)] = [
            ("auth.welcome.title", "en", "Finance, without friction"),
            ("auth.welcome.subtitle", "en", "Use your Apple account for a full session, or enter as a guest and decide later"),
            ("auth.welcome.title", "ru", "Финансы без лишних усилий"),
            ("auth.welcome.subtitle", "ru", "Войдите с Apple для полной сессии или продолжите как гость и решите позже")
        ]

        for item in cases {
            let value = localized(item.key, localeIdentifier: item.locale)
            // Keep failure output actionable by including (key, locale) in the compared tuple.
            #expect((item.key, item.locale, value) == (item.key, item.locale, item.expected))
            assertNoTrailingPeriod(value, key: item.key, locale: item.locale)
        }
    }
}
