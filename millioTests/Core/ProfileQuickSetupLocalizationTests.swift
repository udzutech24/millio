import Foundation
import Testing
@testable import millio

@Suite("Profile quick setup localization")
struct ProfileQuickSetupLocalizationTests {
    @Test("Quick setup strings are localized for English and Russian locales")
    func testQuickSetupLocalization() {
        let enLocale = Locale(identifier: "en")
        let ruLocale = Locale(identifier: "ru")

        #expect(String(localized: "profile.quick_setup", locale: enLocale) == "Quick setup")
        #expect(String(localized: "profile.quick_setup", locale: ruLocale) == "Быстрая настройка")

        #expect(String(localized: "profile.status.completed", locale: enLocale) == "Completed")
        #expect(String(localized: "profile.status.completed", locale: ruLocale) == "Завершена")

        #expect(String(localized: "profile.status.not_completed", locale: enLocale) == "Not completed")
        #expect(String(localized: "profile.status.not_completed", locale: ruLocale) == "Не завершена")
    }
}
