import Foundation
import Testing
@testable import millio

struct FinanceAddAccountProductPickerTests {
    @Test("Новый add-flow автопоказывает выбор типа только без предвыбора")
    func autoPresentationPolicy() {
        #expect(
            FinanceAddAccountPresentationPolicy.shouldAutoPresentTypePicker(
                isEditingMode: false,
                preselectedAccountType: nil
            )
        )
        #expect(
            !FinanceAddAccountPresentationPolicy.shouldAutoPresentTypePicker(
                isEditingMode: true,
                preselectedAccountType: nil
            )
        )
        #expect(
            !FinanceAddAccountPresentationPolicy.shouldAutoPresentTypePicker(
                isEditingMode: false,
                preselectedAccountType: .card
            )
        )
    }

    @Test("Опция денежного счета маппится в инвестиционный preset аккаунта")
    func accountOptionMapsToInvestmentAccountPreset() {
        let selection = FinanceAddAccountProductOption.account.selection(locale: Locale(identifier: "ru"))

        #expect(selection.accountType == .investment)
        #expect(selection.investmentCategory == .other)
        #expect(selection.investmentPreset == .account)
        #expect(selection.title == "Счет")
    }

    @Test("Опция вклада маппится в отдельный preset без конфликта с активом")
    func depositOptionMapsToDedicatedPreset() {
        let selection = FinanceAddAccountProductOption.deposit.selection(locale: Locale(identifier: "ru"))

        #expect(selection.accountType == .investment)
        #expect(selection.investmentCategory == .other)
        #expect(selection.investmentPreset == .deposit)
        #expect(selection.title == "Вклад")
    }

    @Test("Биржевой продукт маппится в ticker-категорию без двусмысленности")
    func stocksOptionMapsToTickerCategory() {
        let selection = FinanceAddAccountProductOption.stocks.selection(locale: Locale(identifier: "en"))

        #expect(selection.accountType == .investment)
        #expect(selection.investmentCategory == .stocks)
        #expect(selection.investmentPreset == .category)
        #expect(selection.title == "Stocks")
    }

    @Test("Заголовки продуктов следуют выбранной локали, а не системному fallback")
    func optionTitlesRespectExplicitLocale() {
        #expect(FinanceAddAccountProductOption.account.title(locale: Locale(identifier: "ru")) == "Счет")
        #expect(FinanceAddAccountProductOption.account.title(locale: Locale(identifier: "en")) == "Account")
        #expect(FinanceAddAccountProductOption.account.title(locale: Locale(identifier: "zh-Hans")) == "账户")
        #expect(FinanceAddAccountProductOption.deposit.title(locale: Locale(identifier: "ru")) == "Вклад")
        #expect(FinanceAddAccountProductOption.deposit.title(locale: Locale(identifier: "en")) == "Deposit")
        #expect(FinanceAddAccountProductOption.deposit.title(locale: Locale(identifier: "zh-Hans")) == "存款")
        #expect(FinanceAddAccountProductOption.house.title(locale: Locale(identifier: "ru")) == "Недвижимость")
        #expect(FinanceAddAccountProductOption.house.title(locale: Locale(identifier: "en")) == "Real Estate")
        #expect(FinanceAddAccountProductOption.house.title(locale: Locale(identifier: "zh-Hans")) == "房地产")
    }

    @Test("Опции группируются в компактные секции в ожидаемом порядке")
    func visibleSectionsAreStable() {
        let sections = FinanceAddAccountProductOption.visibleSections

        #expect(sections.map(\.section) == [.money, .liabilities, .assets])
        #expect(sections[0].options == [.card, .account, .deposit])
        #expect(sections[1].options == [.credit, .debt])
        #expect(sections[2].options == [.investment, .house, .stocks, .business, .crypto])
    }

    @Test("У каждого продукта есть ровно 2 компактные рекомендации по группам")
    func eachProductHasCompactGroupRecommendations() {
        for option in FinanceAddAccountProductOption.visibleOptions {
            #expect(option.groupRecommendations.count >= 2)
            #expect(Set(option.groupRecommendations.map(\.id)).count == option.groupRecommendations.count)
        }
    }

    @Test("Рекомендации групп и компактные подписи локализованы для zh-Hans")
    func productPickerCopySupportsSimplifiedChinese() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(AppLocalization.string("finances.add_account.product.card.compact_subtitle", locale: locale) == "借记卡、信用卡")
        #expect(AppLocalization.string("finances.add_account.product.crypto.compact_subtitle", locale: locale) == "币种和代币")
        #expect(FinanceAddAccountProductOption.card.groupRecommendations[0].title(locale: locale) == "日常资金")
        #expect(FinanceAddAccountProductOption.stocks.groupRecommendations[1].title(locale: locale) == "券商账户")
    }

    @Test("Текущий выбранный продукт корректно восстанавливается из состояния формы")
    func currentSelectionMapsStateWithoutAmbiguity() {
        #expect(
            FinanceAddAccountProductOption.currentSelection(
                accountType: .card,
                investmentCategory: .other,
                investmentPreset: .asset
            ) == .card
        )
        #expect(
            FinanceAddAccountProductOption.currentSelection(
                accountType: .investment,
                investmentCategory: .other,
                investmentPreset: .account
            ) == .account
        )
        #expect(
            FinanceAddAccountProductOption.currentSelection(
                accountType: .investment,
                investmentCategory: .other,
                investmentPreset: .deposit
            ) == .deposit
        )
        #expect(
            FinanceAddAccountProductOption.currentSelection(
                accountType: .investment,
                investmentCategory: .stocks,
                investmentPreset: .category
            ) == .stocks
        )
        #expect(
            FinanceAddAccountProductOption.currentSelection(
                accountType: .investment,
                investmentCategory: .other,
                investmentPreset: .category
            ) == .investment
        )
    }
}
