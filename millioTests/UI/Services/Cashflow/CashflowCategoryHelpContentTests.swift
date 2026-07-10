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
        // Swift Testing параллелит тесты внутри таргета: без явной фиксации языка
        // тест зависит от ambient LanguageManager.shared, который другие l10n-тесты
        // временно переключают (withLanguage). Пиним язык и сравниваем через L(),
        // как это делают остальные l10n-тесты в проекте (см. AppLanguageTestSupport).
        AppLanguageTestSupport.withLanguage(.russian) {
            let content = CashflowCategoryHelpContent.make(for: .income)

            #expect(content.title == L("cashflow.operation.help.title"))
            #expect(content.notes.contains(L("cashflow.operation.help.note.currency_first")))
            #expect(content.notes.contains(L("cashflow.operation.help.note.category_month")))
            #expect(!content.notes.contains(L("cashflow.operation.help.note.income_history")))
        }
    }

    @Test("Подсказка для расходов оставляет только короткие шаги без дублирующего вступления")
    func expenseHelpContainsHistoryRestoreNote() {
        AppLanguageTestSupport.withLanguage(.russian) {
            let content = CashflowCategoryHelpContent.make(for: .expense)

            #expect(content.notes.contains(L("cashflow.operation.help.note.currency_first")))
            #expect(content.notes.contains(L("cashflow.operation.help.note.category_month")))
            #expect(!content.notes.contains(L("cashflow.operation.help.note.expense_history")))
        }
    }
}
