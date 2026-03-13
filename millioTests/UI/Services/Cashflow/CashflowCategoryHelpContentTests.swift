//
//  CashflowCategoryHelpContentTests.swift
//  millioTests
//
//  Created by Codex on 04.03.2026.
//

import Testing
@testable import millio
import Foundation

struct CashflowCategoryHelpContentTests {
    @Test("Подсказка для доходов описывает экран и ключевые действия")
    func incomeHelpContainsMainGuidance() {
        let content = CashflowCategoryHelpContent.make(for: .income)

        #expect(content.title == String(localized: "cashflow.operation.help.title"))
        #expect(content.lines.contains(String(localized: "cashflow.operation.help.income_intro")))
        #expect(content.lines.contains(String(localized: "cashflow.operation.help.tap_plus")))
        #expect(content.lines.contains(String(localized: "cashflow.operation.help.long_press")))
    }

    @Test("Подсказка для расходов содержит текст про перенос в системную категорию")
    func expenseHelpContainsSafeMigrationNote() {
        let content = CashflowCategoryHelpContent.make(for: .expense)

        #expect(content.lines.contains(String(localized: "cashflow.operation.help.expense_intro")))
        #expect(content.lines.contains(String(localized: "cashflow.operation.help.safe_migration")))
    }
}
