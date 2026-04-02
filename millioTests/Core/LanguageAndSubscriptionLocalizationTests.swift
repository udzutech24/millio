import Foundation
import Testing
@testable import millio

@Suite("Language and subscription localization", .serialized)
struct LanguageAndSubscriptionLocalizationTests {
    @Test("Language display names use self names with localized system option")
    func testLanguageDisplayNamesInEnglish() {
        let locale = Locale(identifier: "en")

        #expect(Language.system.displayName(for: locale) == "System")
        #expect(Language.english.displayName(for: locale) == "English")
        #expect(Language.russian.displayName(for: locale) == "Русский")
        #expect(Language.simplifiedChinese.displayName(for: locale) == "中文")
    }

    @Test("Language display names stay in native scripts for Russian locale")
    func testLanguageDisplayNamesInRussian() {
        let locale = Locale(identifier: "ru")

        #expect(Language.system.displayName(for: locale) == "Системный")
        #expect(Language.english.displayName(for: locale) == "English")
        #expect(Language.russian.displayName(for: locale) == "Русский")
        #expect(Language.simplifiedChinese.displayName(for: locale) == "中文")
    }

    @Test("Language display names stay in native scripts for Simplified Chinese locale")
    func testLanguageDisplayNamesInSimplifiedChinese() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(Language.system.displayName(for: locale) == "跟随系统")
        #expect(Language.english.displayName(for: locale) == "English")
        #expect(Language.russian.displayName(for: locale) == "Русский")
        #expect(Language.simplifiedChinese.displayName(for: locale) == "中文")
    }

    @Test("Language search aliases keep translated queries working")
    func testLanguageSearchAliases() {
        let locale = Locale(identifier: "ru")

        #expect(Language.english.searchableNames(for: locale).contains("Английский"))
        #expect(Language.simplifiedChinese.searchableNames(for: locale).contains("Китайский (упрощенный)"))
        #expect(Language.simplifiedChinese.searchableNames(for: locale).contains("中文"))
    }

    @Test("Subscription errors are localized for release-ready locales")
    func testSubscriptionErrorLocalization() {
        let error = SubscriptionError.trialAlreadyUsed

        #expect(error.localizedDescription(for: Locale(identifier: "en")) == "Trial has already been used")
        #expect(error.localizedDescription(for: Locale(identifier: "ru")) == "Пробный период уже использован")
        #expect(error.localizedDescription(for: Locale(identifier: "zh-Hans")) == "试用期已使用")
    }

    @Test("Subscription per-month suffix is localized for release-ready locales")
    func testSubscriptionPerMonthSuffixLocalization() {
        #expect(AppLocalization.string("subscription.plan.per_month_suffix", locale: Locale(identifier: "en")) == "/mo")
        #expect(AppLocalization.string("subscription.plan.per_month_suffix", locale: Locale(identifier: "ru")) == "/мес")
        #expect(AppLocalization.string("subscription.plan.per_month_suffix", locale: Locale(identifier: "zh-Hans")) == "/月")
    }

    @Test("Explicit region locales do not fall back to the development language")
    func testExplicitRegionLocalesAvoidDevelopmentLanguageFallback() {
        #expect(AppLocalization.string("cashflow.chart.title", locale: Locale(identifier: "en_US")) == "Income and Expenses")
        #expect(AppLocalization.string("cashflow.chart.title", locale: Locale(identifier: "ru_RU")) == "Доходы и расходы")
        #expect(AppLocalization.string("Salary", locale: Locale(identifier: "en_US")) == "Salary")
        #expect(AppLocalization.string("Salary", locale: Locale(identifier: "ru_RU")) == "Зарплата")
    }

    @Test("Explicit locale lookup stays pinned to the requested language for profile strings")
    func testProfileStringsDoNotLeakAcrossLanguages() {
        #expect(AppLocalization.string("profile.launch_splash.mode.once_per_day", locale: Locale(identifier: "en")) == "Once per day")
        #expect(AppLocalization.string("profile.launch_splash.mode.off", locale: Locale(identifier: "zh-Hans")) == "关闭")
        #expect(AppLocalization.string("profile.rate_app.block.subtitle", locale: Locale(identifier: "en")) == "A short review helps us make Millio better")
        #expect(AppLocalization.string("profile.rate_app.summary.idle", locale: Locale(identifier: "zh-Hans")) == "请选择评分")
        #expect(AppLocalization.string("profile.rate_app.dialog.rate.title", locale: Locale(identifier: "en")) == "Thank you!")
    }

    @Test("Current app locale resolves from the catalog immediately after language switch")
    func testCurrentAppLocaleDoesNotLeakPreviousLanguage() {
        AppLanguageTestSupport.withLanguage(.simplifiedChinese) {
            #expect(AppLocalization.string("cashflow.budget.setup.title.expense", locale: AppLocalization.currentAppLocale) == "预算限额")
        }

        AppLanguageTestSupport.withLanguage(.russian) {
            #expect(AppLocalization.string("cashflow.budget.setup.title.expense", locale: AppLocalization.currentAppLocale) == "Лимит бюджета")
        }
    }

    @Test("Subscription yearly savings badge is localized for release-ready locales")
    func testSubscriptionYearlySavingsBadgeLocalization() {
        let englishFormat = AppLocalization.string(
            "subscription.plan.yearly.savings_format",
            locale: Locale(identifier: "en")
        )
        let russianFormat = AppLocalization.string(
            "subscription.plan.yearly.savings_format",
            locale: Locale(identifier: "ru")
        )
        let chineseFormat = AppLocalization.string(
            "subscription.plan.yearly.savings_format",
            locale: Locale(identifier: "zh-Hans")
        )

        #expect(String(format: englishFormat, locale: Locale(identifier: "en"), 30) == "Save 30%")
        #expect(String(format: russianFormat, locale: Locale(identifier: "ru"), 30) == "Экономия 30%")
        #expect(String(format: chineseFormat, locale: Locale(identifier: "zh-Hans"), 30) == "立省 30%")
    }

    @Test("Subscription paywall copy is localized for Simplified Chinese")
    func testSubscriptionPaywallCopyInSimplifiedChinese() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(AppLocalization.string("subscription.navigation.title", locale: locale) == "订阅")
        #expect(AppLocalization.string("subscription.hero.eyebrow", locale: locale) == "PRO 全部功能")
        #expect(AppLocalization.string("subscription.plan.yearly.title", locale: locale) == "年度")
        #expect(AppLocalization.string("subscription.plan.monthly.title", locale: locale) == "月度")
        #expect(AppLocalization.string("subscription.features.title", locale: locale) == "PRO 全部权益")
        #expect(AppLocalization.string("subscription.button.start_trial", locale: locale) == "开始试用（7天）")
        #expect(AppLocalization.string("subscription.button.restore", locale: locale) == "恢复购买")
    }

    @Test("Legal titles follow the selected app locale for system Chinese")
    func testLegalTitlesForSystemChinese() {
        let links = ProfileLegalLinks.make(for: .system, fallbackLocale: Locale(identifier: "zh_Hans_CN"))

        #expect(links.privacyTitle == "隐私政策")
        #expect(links.termsTitle == "使用条款（EULA）")
    }

    @Test("Finance account and investment titles are localized for Russian locale")
    func testFinanceTitlesInRussian() {
        let locale = Locale(identifier: "ru")

        #expect(FinanceAccountType.card.displayName(for: locale) == "Карта")
        #expect(FinanceAccountType.credit.displayName(for: locale) == "Кредит")
        #expect(FinanceAccountType.investment.displayName(for: locale) == "Актив")
        #expect(InvestmentCategory.house.displayName(for: locale) == "Недвижимость")
        #expect(InvestmentCategory.crypto.displayName(for: locale) == "Криптовалюта")
    }

    @Test("Finance account and investment titles are localized for English locale")
    func testFinanceTitlesInEnglish() {
        let locale = Locale(identifier: "en")

        #expect(FinanceAccountType.card.displayName(for: locale) == "Card")
        #expect(FinanceAccountType.credit.displayName(for: locale) == "Credit")
        #expect(FinanceAccountType.investment.displayName(for: locale) == "Asset")
        #expect(InvestmentCategory.house.displayName(for: locale) == "Real estate")
        #expect(InvestmentCategory.crypto.displayName(for: locale) == "Cryptocurrency")
    }

}
