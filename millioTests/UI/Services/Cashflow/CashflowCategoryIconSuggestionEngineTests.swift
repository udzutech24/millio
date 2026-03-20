//
//  CashflowCategoryIconSuggestionEngineTests.swift
//  millioTests
//
//  Created by Codex on 20.03.2026.
//

import Testing
@testable import millio

@Suite
struct CashflowCategoryIconSuggestionEngineTests {
    @Test("Движок рекомендаций категории расходов совпадает с основным каталогом")
    func expenseSuggestionsReuseExpenseCatalogEngine() {
        let suggestions = CashflowCategoryIconSuggestionEngine.suggestedIcons(forExpenseName: "Пицца")

        #expect(suggestions == ExpenseCategoryCatalog.suggestedIcons(for: "Пицца"))
        #expect(suggestions.prefix(3).contains("🍕"))
    }
}
