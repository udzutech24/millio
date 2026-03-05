//
//  CashflowCategoryHelpContentTests.swift
//  millioTests
//
//  Created by Codex on 04.03.2026.
//

import Testing
@testable import millio

struct CashflowCategoryHelpContentTests {
    @Test("Подсказка для доходов описывает экран и ключевые действия")
    func incomeHelpContainsMainGuidance() {
        let content = CashflowCategoryHelpContent.make(for: .income)

        #expect(content.title == "How it works")
        #expect(content.lines.contains { $0.contains("Income screen") })
        #expect(content.lines.contains { $0.contains("Tap +") })
        #expect(content.lines.contains { $0.contains("Long press a category") })
    }

    @Test("Подсказка для расходов содержит текст про перенос в системную категорию")
    func expenseHelpContainsSafeMigrationNote() {
        let content = CashflowCategoryHelpContent.make(for: .expense)

        #expect(content.lines.contains { $0.contains("Expense screen") })
        #expect(content.lines.contains { $0.contains("moved to a safe system category") })
    }
}
