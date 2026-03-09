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

    private func assertNoTrailingPeriod(_ value: String, _ message: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty == false, message)
        #expect(trimmed.hasSuffix(".") == false, message)
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
            #expect(value == item.expected, "Unexpected localization for \(item.key) (\(item.locale))")
            assertNoTrailingPeriod(value, "\(item.key) (\(item.locale)) must not end with a period")
        }
    }
}

