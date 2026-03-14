//
//  BudgetMonthlyRepeatTests.swift
//  millioTests
//
//  Created by Codex on 14.03.2026.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct BudgetMonthlyRepeatTests {
    private static let schema = Schema([
        Card.self,
        FinanceGroup.self,
        FinanceAccount.self,
        CashflowTransaction.self,
        CashflowCustomCategory.self,
        CashflowSystemCategoryOverride.self,
        HistoricalRate.self,
        BudgetPlan.self,
        BudgetCategoryLimit.self
    ])
    private static var retainedContainers: [ModelContainer] = []

    private func createTestModelContext() throws -> ModelContext {
        let defaults = UserDefaults.standard
        defaults.set("RUB", forKey: "primaryCurrencyCode")

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        let context = container.mainContext
        try context.save()
        return context
    }

    private func monthDate(year: Int, month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    @Test("Повтор лимитов берет конфигурацию из прошлого месяца")
    func previousMonthlyBudgetSuggestionUsesPreviousMonth() throws {
        let context = try createTestModelContext()
        let february = monthDate(year: 2026, month: 2)
        let march = monthDate(year: 2026, month: 3)
        let viewModel = CashflowViewModel(modelContext: context, now: { march })

        viewModel.saveMonthlyBudgetConfiguration(
            month: february,
            totalAmount: 120_000,
            categoryLimits: [
                ExpenseCategory.groceries.rawValue: 40_000,
                ExpenseCategory.cafe.rawValue: 12_000
            ],
            currency: "RUB"
        )

        let suggestion = viewModel.previousMonthlyBudgetSuggestion(for: march)

        #expect(suggestion?.totalAmount == 120_000)
        #expect(suggestion?.categoryLimits[ExpenseCategory.groceries.rawValue] == 40_000)
        #expect(suggestion?.categoryLimits[ExpenseCategory.cafe.rawValue] == 12_000)
        #expect(Calendar.current.isDate(suggestion?.sourceMonth ?? .distantPast, equalTo: february, toGranularity: .month))
    }

    @Test("Настройка автоповтора хранится в пользовательских настройках")
    func budgetAutoRepeatPrefsPersistValue() {
        let suiteName = "BudgetMonthlyRepeatTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let prefs = BudgetAutoRepeatPrefs(defaults: defaults)
        #expect(prefs.isEnabled == false)

        prefs.isEnabled = true

        let reloadedPrefs = BudgetAutoRepeatPrefs(defaults: defaults)
        #expect(reloadedPrefs.isEnabled == true)
    }
}
