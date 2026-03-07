//
//  FinanceGroupNameTemplateTests.swift
//  millioTests
//

import Testing
import Foundation
@testable import millio

struct FinanceGroupNameTemplateTests {
    @Test("Шаблоны названий групп: 7 вариантов, уникальные ключи и валидные локализации")
    func groupNameTemplatesAreStableAndLocalized() {
        #expect(FinanceGroupNameTemplate.allCases.count == 7)

        let keys = FinanceGroupNameTemplate.allCases.map(\.localizationKey)
        #expect(Set(keys).count == keys.count)

        let titles = FinanceGroupNameTemplate.allCases.map(\.title)
        #expect(titles.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        #expect(zip(keys, titles).allSatisfy { (key, title) in title != key })
        #expect(Set(titles).count == titles.count)
    }
}
