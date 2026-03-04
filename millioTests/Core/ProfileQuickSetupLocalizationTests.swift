import Foundation
import Testing
@testable import millio

@Suite("Profile quick setup localization")
struct ProfileQuickSetupLocalizationTests {
    private func localizedString(_ key: String, languageCode: String) -> String {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            Issue.record("Missing \(languageCode).lproj in app bundle")
            return key
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    @Test("Quick setup strings are localized for English and Russian locales")
    func testQuickSetupLocalization() {
        #expect(localizedString("profile.quick_setup", languageCode: "en") == "Quick setup")
        #expect(localizedString("profile.quick_setup", languageCode: "ru") == "Быстрая настройка")

        #expect(localizedString("profile.status.completed", languageCode: "en") == "Completed")
        #expect(localizedString("profile.status.completed", languageCode: "ru") == "Завершена")

        #expect(localizedString("profile.status.not_completed", languageCode: "en") == "Not completed")
        #expect(localizedString("profile.status.not_completed", languageCode: "ru") == "Не завершена")
    }
}
