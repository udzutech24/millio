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
    @Test("На ширине 320 pt у расходов базовая сетка 3 колонки")
    func expenseUsesRegularColumnsOnCompactWidth() {
        let count = CashflowCategoryGridLayout.columnCount(
            for: .expense,
            containerWidth: CGFloat(320)
        )

        #expect(count == CashflowCategoryGridLayout.regularColumns)
    }

    @Test("На экране уже 280 pt сетка падает до 2 колонок")
    func veryNarrowWidthFallsBackToCompactColumns() {
        let count = CashflowCategoryGridLayout.columnCount(
            for: .expense,
            containerWidth: CGFloat(260)
        )

        #expect(count == CashflowCategoryGridLayout.compactColumns)
    }

    @Test("На обычном экране у расходов базовая сетка")
    func expenseUsesFourColumnsOnRegularWidth() {
        let count = CashflowCategoryGridLayout.columnCount(
            for: .expense,
            containerWidth: CGFloat(360)
        )

        #expect(count == CashflowCategoryGridLayout.regularColumns)
    }

    @Test("На ширине телефона сетка 3 колонки")
    func expenseUsesRegularColumnsOnPhoneWidth() {
        let count = CashflowCategoryGridLayout.columnCount(
            for: .expense,
            containerWidth: CGFloat(393)
        )

        #expect(count == CashflowCategoryGridLayout.regularColumns)
    }

    @Test("На широком экране сетка не меняется")
    func expenseKeepsRegularColumnsOnWideWidth() {
        let count = CashflowCategoryGridLayout.columnCount(
            for: .expense,
            containerWidth: CGFloat(600)
        )

        #expect(count == CashflowCategoryGridLayout.regularColumns)
    }

    @Test("У доходов сетка такая же, как у расходов")
    func incomeUsesRegularColumnsOnCompactWidth() {
        let count = CashflowCategoryGridLayout.columnCount(
            for: .income,
            containerWidth: CGFloat(320)
        )

        #expect(count == CashflowCategoryGridLayout.regularColumns)
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
