//
//  BudgetProgressCalculatorTests.swift
//  millioTests
//
//  Created by Codex on 14.03.2026.
//

import Foundation
import Testing
@testable import millio

struct BudgetProgressCalculatorTests {
    @Test("Budget snapshot uses warning, critical and exceeded thresholds")
    func statusesFollowThresholds() {
        #expect(BudgetProgressCalculator.status(for: 0.2) == .normal)
        #expect(BudgetProgressCalculator.status(for: 0.7) == .warning)
        #expect(BudgetProgressCalculator.status(for: 0.9) == .critical)
        #expect(BudgetProgressCalculator.status(for: 1.01) == .exceeded)
    }

    @Test("Budget snapshot computes remaining amount and category overflow")
    func snapshotTotalsAndOverflow() {
        let groceries = BudgetCategoryLimit(
            budgetID: "plan",
            categoryKind: .expense,
            categoryRawValue: ExpenseCategory.groceries.rawValue,
            limitAmount: 800
        )
        let cafe = BudgetCategoryLimit(
            budgetID: "plan",
            categoryKind: .expense,
            categoryRawValue: ExpenseCategory.cafe.rawValue,
            limitAmount: 500
        )

        let snapshot = BudgetProgressCalculator.calculate(
            totalSpent: 950,
            totalLimit: 1_000,
            categorySpentByRawValue: [
                ExpenseCategory.groceries.rawValue: 700,
                ExpenseCategory.cafe.rawValue: 250
            ],
            categoryLimits: [groceries, cafe],
            categoryTitleResolver: { raw in raw.capitalized }
        )

        #expect(snapshot != nil)
        #expect(snapshot?.remaining == 50)
        #expect(snapshot?.status == .critical)
        #expect(snapshot?.categoriesLimitOverflow == 300)
        #expect(snapshot?.categorySnapshots.count == 2)
        #expect(snapshot?.categorySnapshots.first?.categoryRawValue == ExpenseCategory.groceries.rawValue)
    }

    @Test("Category snapshots keep severity priority and use alphabetical tie-breaks")
    func categorySnapshotsUseDeterministicOrdering() {
        let salary = BudgetCategoryLimit(
            budgetID: "plan",
            categoryKind: .income,
            categoryRawValue: IncomeCategory.salary.rawValue,
            limitAmount: 250_000
        )
        let business = BudgetCategoryLimit(
            budgetID: "plan",
            categoryKind: .income,
            categoryRawValue: IncomeCategory.business.rawValue,
            limitAmount: 100_000
        )

        let snapshot = BudgetProgressCalculator.calculate(
            totalSpent: 250_000,
            totalLimit: 400_000,
            categorySpentByRawValue: [
                IncomeCategory.salary.rawValue: 180_000,
                IncomeCategory.business.rawValue: 70_000
            ],
            categoryLimits: [salary, business],
            categoryTitleResolver: { raw in
                switch raw {
                case IncomeCategory.salary.rawValue:
                    return "Salary"
                case IncomeCategory.business.rawValue:
                    return "Business"
                default:
                    return raw
                }
            }
        )

        #expect(snapshot?.categorySnapshots.map(\.categoryRawValue) == [
            IncomeCategory.business.rawValue,
            IncomeCategory.salary.rawValue
        ])
    }

    @Test("Zero limit produces no snapshot")
    func zeroLimitHasNoSnapshot() {
        let snapshot = BudgetProgressCalculator.calculate(totalSpent: 100, totalLimit: 0)
        #expect(snapshot == nil)
    }
}
