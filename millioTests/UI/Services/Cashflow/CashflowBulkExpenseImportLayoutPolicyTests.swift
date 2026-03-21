//
//  CashflowBulkExpenseImportLayoutPolicyTests.swift
//  millioTests
//

import Testing
@testable import millio

@Suite
struct CashflowBulkExpenseImportLayoutPolicyTests {
    @Test("Галочка сохранения активна только когда импорт можно сохранить и он не в процессе")
    func saveActionPresentationReflectsAvailability() {
        let ready = CashflowBulkExpenseImportLayoutPolicy.saveActionPresentation(
            canSave: true,
            isProcessing: false
        )
        let blockedByValidation = CashflowBulkExpenseImportLayoutPolicy.saveActionPresentation(
            canSave: false,
            isProcessing: false
        )
        let blockedByProcessing = CashflowBulkExpenseImportLayoutPolicy.saveActionPresentation(
            canSave: true,
            isProcessing: true
        )

        #expect(ready.icon == "checkmark")
        #expect(ready.isEnabled)
        #expect(!blockedByValidation.isEnabled)
        #expect(!blockedByProcessing.isEnabled)
    }

    @Test("Статус блока карты показывает доступный баланс или отсутствие карт")
    func controlsStatusPrefersBalanceAndFallsBackToWarning() {
        let balance = CashflowBulkExpenseImportLayoutPolicy.controlsStatus(
            balanceText: "Доступно: 10 000 RUB",
            hasCards: true
        )
        let noCards = CashflowBulkExpenseImportLayoutPolicy.controlsStatus(
            balanceText: nil,
            hasCards: false
        )
        let hidden = CashflowBulkExpenseImportLayoutPolicy.controlsStatus(
            balanceText: nil,
            hasCards: true
        )

        #expect(balance?.text == "Доступно: 10 000 RUB")
        #expect(balance?.tone == .neutral)
        #expect(noCards?.tone == .warning)
        #expect(hidden == nil)
    }

    @Test("Обычная категория использует палитру расходов")
    func defaultCategoryTileUsesExpensePalette() {
        let presentation = CashflowBulkExpenseImportLayoutPolicy.categoryTilePresentation(
            isTransferCategory: false
        )

        #expect(presentation.borderTone == .expenseDefault)
    }

    @Test("Трансферная категория остаётся в аварийной палитре")
    func transferCategoryKeepsTransferTone() {
        let presentation = CashflowBulkExpenseImportLayoutPolicy.categoryTilePresentation(
            isTransferCategory: true
        )

        #expect(presentation.borderTone == .transfer)
    }
}
