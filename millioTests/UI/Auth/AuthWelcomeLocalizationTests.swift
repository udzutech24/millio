import Foundation
import Testing
@testable import millio

struct AuthWelcomeLocalizationTests {
    private func localized(_ key: String, localeIdentifier: String) -> String {
        let bundle = Bundle(for: SettingsManager.self)
        let languageCode = Locale(identifier: localeIdentifier).language.languageCode?.identifier ?? localeIdentifier
        guard let localizedPath = bundle.path(forResource: languageCode, ofType: "lproj"),
              let localizedBundle = Bundle(path: localizedPath) else {
            return bundle.localizedString(forKey: key, value: nil, table: nil)
        }
        return localizedBundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private func assertNoTrailingPeriod(_ value: String, _ message: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty == false)
        #expect(trimmed.hasSuffix(".") == false)
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
            #expect(value == item.expected)
            assertNoTrailingPeriod(value, "\(item.key) (\(item.locale)) must not end with a period")
        }
    }
}
