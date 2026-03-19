//
//  CashflowCategoryGridLayoutTests.swift
//  millioTests
//
//  Created by Codex on 12.03.2026.
//

import Testing
import CoreGraphics
@testable import millio

struct CashflowCategoryGridLayoutTests {
    @Test("На узком экране у расходов 3 колонки")
    func expenseUsesThreeColumnsOnCompactWidth() {
        let count = CashflowCategoryGridLayout.columnCount(
            for: .expense,
            containerWidth: CGFloat(320)
        )

        #expect(count == CashflowCategoryGridLayout.compactColumns)
    }

    @Test("На обычном экране у расходов 4 колонки")
    func expenseUsesFourColumnsOnRegularWidth() {
        let count = CashflowCategoryGridLayout.columnCount(
            for: .expense,
            containerWidth: CGFloat(360)
        )

        #expect(count == CashflowCategoryGridLayout.regularColumns)
    }

    @Test("При включенных лимитах у расходов на ширине телефона 3 колонки")
    func expenseWithBudgetUsesThreeColumnsOnPhoneWidth() {
        let count = CashflowCategoryGridLayout.columnCount(
            for: .expense,
            containerWidth: CGFloat(393),
            showsBudgetDetails: true
        )

        #expect(count == CashflowCategoryGridLayout.compactColumns)
    }

    @Test("При включенных лимитах на широком экране у расходов остается 4 колонки")
    func expenseWithBudgetKeepsFourColumnsOnWideWidth() {
        let count = CashflowCategoryGridLayout.columnCount(
            for: .expense,
            containerWidth: CGFloat(600),
            showsBudgetDetails: true
        )

        #expect(count == CashflowCategoryGridLayout.regularColumns)
    }

    @Test("На узком экране доходы тоже переходят на 3 колонки")
    func incomeUsesThreeColumnsOnCompactWidth() {
        let count = CashflowCategoryGridLayout.columnCount(
            for: .income,
            containerWidth: CGFloat(320)
        )

        #expect(count == CashflowCategoryGridLayout.compactColumns)
    }

    @Test("Карточки категорий сохраняют одинаковую высоту с лимитом и без")
    func cardsKeepSameHeightWithAndWithoutBudget() {
        let compact = CashflowCategoryGridLayout.cardMetrics(showsBudgetDetails: false)
        let budget = CashflowCategoryGridLayout.cardMetrics(showsBudgetDetails: true)

        #expect(compact.cardMinHeight == budget.cardMinHeight)
        #expect(compact.cardMinHeight == CashflowCategoryGridLayout.unifiedCardMinHeight)
        #expect(compact.topRowMinHeight == budget.topRowMinHeight)
        #expect(compact.topRowMinHeight == CashflowCategoryGridLayout.unifiedTopRowMinHeight)
        #expect(compact.amountTopPadding > budget.amountTopPadding)
        #expect(compact.usesFlexibleSpacer == true)
        #expect(budget.usesFlexibleSpacer == true)
        #expect(compact.footerMinHeight == budget.footerMinHeight)
        #expect(compact.footerMinHeight == CashflowCategoryGridLayout.unifiedFooterMinHeight)
    }

    @Test("У расхода unpinned-пин скрыт по умолчанию")
    func expenseUnpinnedPinIsHidden() {
        let style = CashflowCategoryGridLayout.pinAffordanceStyle(
            for: .expense,
            isPinned: false
        )

        #expect(style == .hidden)
    }

    @Test("У расхода pinned-пин показывается компактным badge")
    func expensePinnedPinUsesCompactBadge() {
        let style = CashflowCategoryGridLayout.pinAffordanceStyle(
            for: .expense,
            isPinned: true
        )

        #expect(style == .compactBadge)
    }

    @Test("У дохода unpinned-пин скрыт по умолчанию")
    func incomeUnpinnedPinIsHidden() {
        let style = CashflowCategoryGridLayout.pinAffordanceStyle(
            for: .income,
            isPinned: false
        )

        #expect(style == .hidden)
    }

    @Test("У дохода pinned-пин показывается компактным badge")
    func incomePinnedPinUsesCompactBadge() {
        let style = CashflowCategoryGridLayout.pinAffordanceStyle(
            for: .income,
            isPinned: true
        )

        #expect(style == .compactBadge)
    }
}
