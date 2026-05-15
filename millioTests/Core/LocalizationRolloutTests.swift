import Foundation
import Testing
@testable import millio

struct LocalizationRolloutTests {
    @Test("Profile language picker includes all release-ready languages")
    func testUserSelectableLanguages() {
        #expect(LocalizationSupport.userSelectableLanguages == [.system, .english, .russian, .simplifiedChinese, .german, .spanish])
        #expect(LocalizationSupport.releaseReadiness(for: .simplifiedChinese) == .releaseReady)
        #expect(LocalizationSupport.releaseReadiness(for: .german) == .releaseReady)
        #expect(LocalizationSupport.releaseReadiness(for: .spanish) == .releaseReady)
        #expect(LocalizationSupport.releaseReadiness(for: .turkish) == .planned)
        #expect(LocalizationSupport.releaseReadiness(for: .french) == .planned)
    }

    @Test("System locale resolves to Simplified Chinese when device language is zh-Hans")
    func testSystemLocaleResolvesToSimplifiedChinese() {
        let fallbackLocale = Locale(identifier: "zh_Hans_CN")

        #expect(LocalizationSupport.resolvedLanguage(for: .system, fallbackLocale: fallbackLocale) == .simplifiedChinese)
        #expect(LocalizationSupport.locale(
            LocalizationSupport.resolvedLocale(for: .system, fallbackLocale: fallbackLocale),
            matches: .simplifiedChinese
        ))
    }

    @Test("Quick setup exposes all release-ready languages regardless of system locale")
    func testQuickSetupSelectableLanguages() {
        let chineseSystem = QuickSetupSystemContext(
            preferredLanguageIdentifiers: ["zh-Hans-CN"],
            locale: Locale(identifier: "zh_Hans_CN")
        )
        let russianSystem = QuickSetupSystemContext(
            preferredLanguageIdentifiers: ["ru-RU"],
            locale: Locale(identifier: "ru_RU")
        )
        let expected: [Language] = [.system, .english, .russian, .simplifiedChinese, .german, .spanish]

        #expect(chineseSystem.quickSetupAvailableLanguages == expected)
        #expect(russianSystem.quickSetupAvailableLanguages == expected)
    }

    @Test("Presentation locale prefers selected app language over device locale for product copy")
    func testPresentationLocaleUsesAppLanguageForCurrentDeviceLocale() {
        let locale = LocalizationSupport.presentationLocale(
            for: Locale(identifier: "en_US"),
            selectedLanguage: .simplifiedChinese,
            currentDeviceLocales: [Locale(identifier: "en_US"), Locale(identifier: "en_GB")]
        )

        #expect(LocalizationSupport.locale(locale, matches: .simplifiedChinese))
    }

    @Test("Presentation locale preserves explicit legacy locale inputs")
    func testPresentationLocalePreservesExplicitLocale() {
        let locale = LocalizationSupport.presentationLocale(
            for: Locale(identifier: "ru_RU"),
            selectedLanguage: .simplifiedChinese,
            currentDeviceLocales: [Locale(identifier: "en_US"), Locale(identifier: "en_GB")]
        )

        #expect(LocalizationSupport.locale(locale, matches: .russian))
    }

    @Test("Daily reminders fall back to English copy for unsupported system locale")
    func testDailyReminderSystemFallbackCopy() {
        let settings = DailyReminderSettings.default

        #expect(
            settings.notificationBody(
                for: .custom,
                language: .system,
                fallbackLocale: Locale(identifier: "fr_FR"),
                calendar: Calendar(identifier: .gregorian),
                now: Date(timeIntervalSince1970: 0)
            ) == "Open millio and update your data"
        )
    }

    @Test("Explicit Simplified Chinese reminder copy uses zh-Hans localization")
    func testDailyReminderChineseCopy() {
        let settings = DailyReminderSettings.default

        #expect(
            settings.notificationBody(
                for: .custom,
                language: .simplifiedChinese,
                calendar: Calendar(identifier: .gregorian),
                now: Date(timeIntervalSince1970: 0)
            ) == "打开 millio 并更新数据"
        )
    }

    @Test("Daily reminder summary uses localized subject forms for supported languages")
    func testDailyReminderSummaryUsesLocalizedSubjects() {
        let calendar = Calendar(identifier: .gregorian)
        let settings = DailyReminderSettings(
            isEnabled: true,
            enabledKinds: [.expense],
            cadence: .daily,
            hour: 20,
            minute: 0,
            dayOfMonth: 1,
            selectedDate: Date(timeIntervalSince1970: 0),
            customText: ""
        )

        let english = DailyReminderLocalization.configuredSummaryText(
            settings: settings,
            locale: Locale(identifier: "en"),
            calendar: calendar
        )
        let russian = DailyReminderLocalization.configuredSummaryText(
            settings: settings,
            locale: Locale(identifier: "ru"),
            calendar: calendar
        )
        let chinese = DailyReminderLocalization.configuredSummaryText(
            settings: settings,
            locale: Locale(identifier: "zh-Hans"),
            calendar: calendar
        )

        #expect(english.contains("expenses"))
        #expect(russian.contains("расходах"))
        #expect(chinese.contains("支出"))
    }

    @Test("Daily reminder summary avoids raw joined kind lists for multi-kind selection")
    func testDailyReminderSummaryUsesGenericSubjectForMultipleKinds() {
        let calendar = Calendar(identifier: .gregorian)
        let settings = DailyReminderSettings(
            isEnabled: true,
            enabledKinds: [.expense, .income],
            cadence: .monthly,
            hour: 20,
            minute: 0,
            dayOfMonth: 15,
            selectedDate: Date(timeIntervalSince1970: 0),
            customText: ""
        )

        let english = DailyReminderLocalization.configuredSummaryText(
            settings: settings,
            locale: Locale(identifier: "en"),
            calendar: calendar
        )
        let russian = DailyReminderLocalization.configuredSummaryText(
            settings: settings,
            locale: Locale(identifier: "ru"),
            calendar: calendar
        )

        #expect(english.contains("selected items"))
        #expect(!english.contains("Expenses, Income"))
        #expect(russian.contains("выбранных записях"))
        #expect(!russian.contains("Расходы, Доходы"))
    }
}
