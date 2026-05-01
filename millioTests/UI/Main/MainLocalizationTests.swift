import Foundation
import Testing
@testable import millio

struct MainLocalizationTests {
    @Test("Main screen strings are localized for Simplified Chinese")
    func mainScreenStringsInSimplifiedChinese() {
        let locale = Locale(identifier: "zh-Hans")

        #expect(AppLocalization.string("main.history.accessibility", locale: locale) == "交易历史")
        #expect(AppLocalization.string("main.quick_action.expense", locale: locale) == "支出")
        #expect(AppLocalization.string("main.quick_action.income", locale: locale) == "收入")
        #expect(AppLocalization.string("main.service.finances", locale: locale) == "资产")
        #expect(AppLocalization.string("main.service.courses", locale: locale) == "汇率")
        #expect(AppLocalization.string("main.service.cashback", locale: locale) == "返现")
        #expect(AppLocalization.string("main.service.cashflow", locale: locale) == "现金流")
        #expect(AppLocalization.string("main.quick_setup.banner.title", locale: locale) == "快速设置")
        #expect(AppLocalization.string("main.quick_setup.banner.subtitle", locale: locale) == "1 分钟完成语言、货币、分类和产品设置")
        #expect(AppLocalization.string("main.quick_setup.banner.open", locale: locale) == "打开")
    }
}
