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

    @Test("Subscription per-month suffix is localized for English and Russian locales")
    func testSubscriptionPerMonthSuffixLocalization() {
        #expect(AppLocalization.string("subscription.plan.per_month_suffix", locale: Locale(identifier: "en")) == "/mo")
        #expect(AppLocalization.string("subscription.plan.per_month_suffix", locale: Locale(identifier: "ru")) == "/мес")
    }

    @Test("Subscription yearly savings badge is localized for English and Russian locales")
    func testSubscriptionYearlySavingsBadgeLocalization() {
        let englishFormat = AppLocalization.string(
            "subscription.plan.yearly.savings_format",
            locale: Locale(identifier: "en")
        )
        let russianFormat = AppLocalization.string(
            "subscription.plan.yearly.savings_format",
            locale: Locale(identifier: "ru")
        )

        #expect(String(format: englishFormat, locale: Locale(identifier: "en"), 30) == "Save 30%")
        #expect(String(format: russianFormat, locale: Locale(identifier: "ru"), 30) == "Экономия 30%")
    }

}
