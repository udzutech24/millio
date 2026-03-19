//
//  CashbackCategoryCatalogTests.swift
//  millioTests
//
//  Created by Codex on 19.03.2026.
//

import Foundation
import Testing
@testable import millio

@Suite
struct CashbackCategoryCatalogTests {
    @Test("Частичный запрос по компьютерам даёт релевантные иконки для кэшбэка")
    func suggestedIconsPreferComputerIconsForPartialComputerQuery() {
        let suggestions = CashbackCategoryCatalog.suggestedIcons(for: "Компью")

        #expect(!suggestions.isEmpty)
        #expect(suggestions.contains("💻"))
        #expect(suggestions.contains("🖥️"))
    }

    @Test("Неполное слово пиццы даёт релевантную рекомендацию для кэшбэка")
    func suggestedIconsPreferPizzaForPartialPizzaQuery() {
        let suggestions = CashbackCategoryCatalog.suggestedIcons(for: "Пицц")

        #expect(!suggestions.isEmpty)
        #expect(suggestions.prefix(3).contains("🍕"))
    }

    @Test("Рекомендации кэшбэка учитывают все слова в названии категории")
    func suggestedIconsUseAllWordsInQuery() {
        let suggestions = CashbackCategoryCatalog.suggestedIcons(for: "доставка роллов домой")

        #expect(!suggestions.isEmpty)
        #expect(suggestions.prefix(3).contains("🍣"))
    }
}
