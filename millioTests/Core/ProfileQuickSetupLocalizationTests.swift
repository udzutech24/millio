import Foundation
import Testing
@testable import millio

/// Строку «Быстрая настройка» из профиля убрали — путь к языку и валюте теперь
/// только через отдельные строки «Язык» и «Основная валюта».
@Suite("Profile language and currency localization")
struct ProfileLanguageCurrencyLocalizationTests {
    private func localizedString(_ key: String, languageCode: String) -> String {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            Issue.record("Missing \(languageCode).lproj in app bundle")
            return key
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    @Test("Language and currency rows are localized for English and Russian locales")
    func testLanguageAndCurrencyLocalization() {
        #expect(localizedString("profile.language", languageCode: "en") == "Language")
        #expect(localizedString("profile.language", languageCode: "ru") == "Язык")

        #expect(localizedString("profile.currency", languageCode: "en") == "Currency")
        #expect(localizedString("profile.currency", languageCode: "ru") == "Валюта")
    }

    /// Регрессия: ключ удалён вместе со строкой меню — если он вернётся, значит
    /// вернулась и мёртвая строка профиля.
    @Test("Quick setup profile row key is gone")
    func testQuickSetupKeyRemoved() {
        #expect(localizedString("profile.quick_setup", languageCode: "ru") == "profile.quick_setup")
    }
}
