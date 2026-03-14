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
        #expect(content.notes.contains(String(localized: "cashflow.operation.help.note.currency_first")))
        #expect(content.notes.contains(String(localized: "cashflow.operation.help.note.category_month")))
        #expect(!content.notes.contains(String(localized: "cashflow.operation.help.note.income_history")))
    }

    @Test("Подсказка для расходов оставляет только короткие шаги без дублирующего вступления")
    func expenseHelpContainsHistoryRestoreNote() {
        let content = CashflowCategoryHelpContent.make(for: .expense)

        #expect(content.notes.contains(String(localized: "cashflow.operation.help.note.currency_first")))
        #expect(content.notes.contains(String(localized: "cashflow.operation.help.note.category_month")))
        #expect(!content.notes.contains(String(localized: "cashflow.operation.help.note.expense_history")))
    }
}
