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

        #expect(content.title == "Как это работает")
        #expect(content.lines.contains { $0.contains("«Доход»") })
        #expect(content.lines.contains { $0.contains("Нажмите «+»") })
        #expect(content.lines.contains { $0.contains("Удерживайте категорию") })
    }

    @Test("Подсказка для расходов содержит текст про перенос в системную категорию")
    func expenseHelpContainsSafeMigrationNote() {
        let content = CashflowCategoryHelpContent.make(for: .expense)

        #expect(content.lines.contains { $0.contains("«Расход»") })
        #expect(content.lines.contains { $0.contains("переносятся в безопасную системную категорию") })
    }
}
