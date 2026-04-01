//
//  FinanceGroupNameTemplateTests.swift
//  millioTests
//

import Testing
import Foundation
@testable import millio

struct FinanceGroupNameTemplateTests {
    @Test("Шаблоны названий групп: 6 вариантов, уникальные ключи и валидные локализации")
    func groupNameTemplatesAreStableAndLocalized() {
        #expect(FinanceGroupNameTemplate.allCases.count == 6)

        let keys = FinanceGroupNameTemplate.allCases.map(\.localizationKey)
        #expect(Set(keys).count == keys.count)

        let titles = FinanceGroupNameTemplate.allCases.map(\.title)
        #expect(titles.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(zip(keys, titles).allSatisfy { (key, title) in title != key })
        #expect(Set(titles).count == titles.count)
    }

    @Test("Шаблоны названий групп возвращают локализованные заголовки для явной локали")
    func groupNameTemplatesRespectExplicitLocale() {
        #expect(FinanceGroupNameTemplate.debitCards.title(locale: Locale(identifier: "en_US")) == "Cards")
        #expect(FinanceGroupNameTemplate.stocks.title(locale: Locale(identifier: "ru_RU")) == "Акции")
        #expect(FinanceGroupNameTemplate.foreignCards.title(locale: Locale(identifier: "zh_Hans_CN")) == "外币卡")
    }
}
