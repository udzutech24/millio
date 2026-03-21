//
//  BudgetVisualStyleTests.swift
//  millioTests
//
//  Created by Codex on 21.03.2026.
//

import Testing
@testable import millio

struct BudgetVisualStyleTests {
    @Test("Расходы в норме оставляют сумму нейтральной, а статус вторичным")
    func expenseNormalStyle() {
        let snapshot = BudgetProgressSnapshot(
            spent: 264_479,
            limit: 1_212_121,
            remaining: 947_642,
            progress: 0.22,
            status: .normal,
            categorySnapshots: [],
            categoriesLimitOverflow: 0
        )

        let style = budgetMonthlySummaryStyle(kind: .expense, snapshot: snapshot)

        #expect(style.valueText == .primaryText)
        #expect(style.usageText == .secondaryText)
        #expect(style.progressFill == .calmAccent)
        #expect(style.statusText == .secondaryText)
    }

    @Test("Перерасход расходов поднимает danger только в статусе и прогрессе")
    func expenseExceededStyle() {
        let snapshot = BudgetProgressSnapshot(
            spent: 1_400,
            limit: 1_000,
            remaining: -400,
            progress: 1.4,
            status: .exceeded,
            categorySnapshots: [],
            categoriesLimitOverflow: 0
        )

        let style = budgetMonthlySummaryStyle(kind: .expense, snapshot: snapshot)

        #expect(style.valueText == .primaryText)
        #expect(style.progressFill == .dangerAccent)
        #expect(style.statusText == .dangerAccent)
    }

    @Test("Доходы до выполнения плана используют спокойный акцент без зеленой суммы")
    func incomeInProgressStyle() {
        let snapshot = BudgetProgressSnapshot(
            spent: 187_000,
            limit: 275_000,
            remaining: 88_000,
            progress: 0.68,
            status: .normal,
            categorySnapshots: [],
            categoriesLimitOverflow: 0
        )

        let style = budgetMonthlySummaryStyle(kind: .income, snapshot: snapshot)

        #expect(style.valueText == .primaryText)
        #expect(style.usageText == .secondaryText)
        #expect(style.progressFill == .calmAccent)
        #expect(style.statusText == .secondaryText)
    }

    @Test("Доходы после выполнения плана подсвечивают только статус и прогресс")
    func incomeCompletedStyle() {
        let snapshot = BudgetProgressSnapshot(
            spent: 310_000,
            limit: 275_000,
            remaining: 0,
            progress: 1,
            status: .normal,
            categorySnapshots: [],
            categoriesLimitOverflow: 0
        )

        let style = budgetMonthlySummaryStyle(kind: .income, snapshot: snapshot)

        #expect(style.valueText == .primaryText)
        #expect(style.progressFill == .successAccent)
        #expect(style.statusText == .successAccent)
    }
}
