import Foundation
import Testing
@testable import millio

@Suite("Language and subscription localization")
struct LanguageAndSubscriptionLocalizationTests {
    @Test("Language display names are localized for English locale")
    func testLanguageDisplayNamesInEnglish() {
        let locale = Locale(identifier: "en")

        #expect(Language.system.displayName(for: locale) == "System")
        #expect(Language.english.displayName(for: locale) == "English")
        #expect(Language.russian.displayName(for: locale) == "Russian")
    }

    @Test("Language display names are localized for Russian locale")
    func testLanguageDisplayNamesInRussian() {
        let locale = Locale(identifier: "ru")

        #expect(Language.system.displayName(for: locale) == "Системный")
        #expect(Language.english.displayName(for: locale) == "Английский")
        #expect(Language.russian.displayName(for: locale) == "Русский")
    }

    @Test("Subscription errors are localized for English and Russian locales")
    func testSubscriptionErrorLocalization() {
        let error = SubscriptionError.trialAlreadyUsed

        #expect(error.localizedDescription(for: Locale(identifier: "en")) == "Trial has already been used")
        #expect(error.localizedDescription(for: Locale(identifier: "ru")) == "Пробный период уже использован")
    }
}
