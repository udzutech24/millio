//
//  CashflowCategoryUpdateFeedbackPlanTests.swift
//  millioTests
//
//  Created by Codex on 16.03.2026.
//

import Foundation
import Testing
@testable import millio

struct CashflowCategoryUpdateFeedbackPlanTests {
    @Test("Builds feedback when selected category total changes")
    func buildsFeedbackForChangedCategory() {
        let plan = CashflowCategoryUpdateFeedbackPlan.make(
            for: ExpenseCategory.groceries.rawValue,
            previousTotals: [ExpenseCategory.groceries.rawValue: 1_200],
            updatedTotals: [ExpenseCategory.groceries.rawValue: 1_650]
        )

        #expect(plan?.categoryRawValue == ExpenseCategory.groceries.rawValue)
        #expect(plan?.previousTotal == 1_200)
        #expect(plan?.updatedTotal == 1_650)
        #expect(plan?.delta == 450)
    }

    @Test("Returns nil when category total did not change")
    func returnsNilForUnchangedCategory() {
        let plan = CashflowCategoryUpdateFeedbackPlan.make(
            for: ExpenseCategory.groceries.rawValue,
            previousTotals: [ExpenseCategory.groceries.rawValue: 900],
            updatedTotals: [ExpenseCategory.groceries.rawValue: 900]
        )

        #expect(plan == nil)
    }

    @Test("Treats missing previous total as zero")
    func usesZeroWhenPreviousValueMissing() {
        let plan = CashflowCategoryUpdateFeedbackPlan.make(
            for: ExpenseCategory.cafe.rawValue,
            previousTotals: [:],
            updatedTotals: [ExpenseCategory.cafe.rawValue: 320]
        )

        #expect(plan?.previousTotal == 0)
        #expect(plan?.updatedTotal == 320)
        #expect(plan?.delta == 320)
    }
}
