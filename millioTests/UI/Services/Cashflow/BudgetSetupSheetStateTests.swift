//
//  BudgetSetupSheetStateTests.swift
//  millioTests
//
//  Created by Codex on 21.03.2026.
//

import Testing
@testable import millio

struct BudgetSetupSheetStateTests {
    @Test("Когда общий лимит включен, сохранить можно только с валидной суммой без переполнения")
    func totalLimitModeValidatesAmountAndOverflow() {
        let validState = BudgetSetupSheetState(
            isTotalLimitEnabled: true,
            parsedTotal: 10_000,
            categoryLimits: [ExpenseCategory.groceries.rawValue: 2_000],
            hasExistingAmount: false,
            hasExistingCategoryLimits: false
        )
        let zeroTotalState = BudgetSetupSheetState(
            isTotalLimitEnabled: true,
            parsedTotal: 0,
            categoryLimits: [ExpenseCategory.groceries.rawValue: 2_000],
            hasExistingAmount: false,
            hasExistingCategoryLimits: false
        )
        let overflowState = BudgetSetupSheetState(
            isTotalLimitEnabled: true,
            parsedTotal: 3_000,
            categoryLimits: [
                ExpenseCategory.groceries.rawValue: 2_000,
                ExpenseCategory.cafe.rawValue: 2_000
            ],
            hasExistingAmount: false,
            hasExistingCategoryLimits: false
        )

        #expect(validState.canSave == true)
        #expect(zeroTotalState.canSave == false)
        #expect(overflowState.hasOverflowConflict == true)
        #expect(overflowState.canSave == false)
    }

    @Test("Когда общий лимит выключен, можно сохранить только лимиты категорий")
    func categoryOnlyModeRequiresAtLeastOneCategoryLimit() {
        let emptyState = BudgetSetupSheetState(
            isTotalLimitEnabled: false,
            parsedTotal: 0,
            categoryLimits: [:],
            hasExistingAmount: false,
            hasExistingCategoryLimits: false
        )
        let categoryOnlyState = BudgetSetupSheetState(
            isTotalLimitEnabled: false,
            parsedTotal: 15_000,
            categoryLimits: [ExpenseCategory.transport.rawValue: 4_000],
            hasExistingAmount: false,
            hasExistingCategoryLimits: false
        )

        #expect(emptyState.canSave == false)
        #expect(categoryOnlyState.canSave == true)
        #expect(categoryOnlyState.effectiveTotalAmount == 0)
    }

    @Test("Экран считает существующей конфигурацию и без общего лимита, если уже есть лимиты категорий")
    func existingConfigurationIncludesCategoryOnlySetup() {
        let state = BudgetSetupSheetState(
            isTotalLimitEnabled: false,
            parsedTotal: 0,
            categoryLimits: [:],
            hasExistingAmount: false,
            hasExistingCategoryLimits: true
        )

        #expect(state.hasExistingConfiguration == true)
    }

    @Test("Переключатель общего лимита включается только при ненулевой стартовой сумме")
    func initialToggleStateUsesInitialAmount() {
        #expect(BudgetSetupSheetState.isTotalLimitInitiallyEnabled(nil) == false)
        #expect(BudgetSetupSheetState.isTotalLimitInitiallyEnabled(0) == false)
        #expect(BudgetSetupSheetState.isTotalLimitInitiallyEnabled(12_000) == true)
    }
}
