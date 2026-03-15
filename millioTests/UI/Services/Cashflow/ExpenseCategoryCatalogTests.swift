//
//  ExpenseCategoryCatalogTests.swift
//  millioTests
//
//  Created by Codex on 15.03.2026.
//

import Foundation
import Testing
@testable import millio

@Suite
struct ExpenseCategoryCatalogTests {
    @Test("Поиск категорий понимает частичный ввод для компьютерной техники")
    func matchesDigitalCategoryForPartialComputerQuery() {
        #expect(
            ExpenseCategoryCatalog.matchesSearch(
                rawValue: ExpenseCategory.digitalServices.rawValue,
                query: "Компью"
            )
        )
    }

    @Test("Подсказки иконок для компьютеров не сваливаются в дефолтный набор")
    func suggestedIconsPreferComputerIconsForPartialComputerQuery() {
        let suggestions = ExpenseCategoryCatalog.suggestedIcons(for: "Компью")

        #expect(!suggestions.isEmpty)
        #expect(suggestions.first != CashflowCustomCategory.defaultIcon)
        #expect(suggestions.contains("💻"))
        #expect(suggestions.contains("🖥️"))
    }

    @Test("Английский запрос laptop тоже даёт релевантные иконки")
    func suggestedIconsPreferComputerIconsForLaptopQuery() {
        let suggestions = ExpenseCategoryCatalog.suggestedIcons(for: "laptop")

        #expect(suggestions.contains("💻"))
        #expect(suggestions.contains("🖥️"))
        #expect(suggestions.prefix(3).contains("💻") || suggestions.prefix(3).contains("🖥️"))
    }
}
