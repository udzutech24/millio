//
//  CashflowTransactionEditorViewLayoutTests.swift
//  millioTests
//
//  Created by Codex on 01.03.2026.
//

import Testing
@testable import millio

struct CashflowTransactionEditorViewLayoutTests {
    @Test("Основная информация для дохода: карта между суммой и валютой")
    func incomeMainInfoRows() {
        let rows = CashflowTransactionEditorView.mainInfoRows(for: .income)
        #expect(rows == [.amount, .fromCard, .currency, .date])
    }

    @Test("Основная информация для расхода: карта между суммой и валютой")
    func expenseMainInfoRows() {
        let rows = CashflowTransactionEditorView.mainInfoRows(for: .expense)
        #expect(rows == [.amount, .fromCard, .currency, .date])
    }

    @Test("Основная информация для перевода: обе карты между суммой и валютой")
    func transferMainInfoRows() {
        let rows = CashflowTransactionEditorView.mainInfoRows(for: .transfer)
        #expect(rows == [.amount, .fromCard, .toCard, .currency, .date])
    }

    @Test("Конфигурация cashflow-листа для дохода")
    func incomeSheetConfiguration() {
        let kind = CashflowCategoryTransactionSheetKind.income
        #expect(kind.navigationTitle == "Новый доход")
        #expect(kind.monthlyTotalTitle == "Итого доход за месяц")
        #expect(kind.categoryKind == .income)
        #expect(kind.transactionType == .income)
    }

    @Test("Конфигурация cashflow-листа для расхода")
    func expenseSheetConfiguration() {
        let kind = CashflowCategoryTransactionSheetKind.expense
        #expect(kind.navigationTitle == "Новый расход")
        #expect(kind.monthlyTotalTitle == "Итого расход за месяц")
        #expect(kind.categoryKind == .expense)
        #expect(kind.transactionType == .expense)
    }
}
