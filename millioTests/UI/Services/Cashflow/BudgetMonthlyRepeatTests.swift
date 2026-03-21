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

    @Test("Планы доходов и лимиты расходов хранятся отдельно для одного месяца")
    func monthlyPlansAreSeparatedByCategoryKind() throws {
        let context = try createTestModelContext()
        let february = monthDate(year: 2026, month: 2)
        let march = monthDate(year: 2026, month: 3)
        let viewModel = CashflowViewModel(modelContext: context, now: { march })

        viewModel.saveMonthlyBudgetConfiguration(
            categoryKind: .expense,
            month: february,
            totalAmount: 120_000,
            categoryLimits: [ExpenseCategory.groceries.rawValue: 40_000],
            currency: "RUB"
        )
        viewModel.saveMonthlyBudgetConfiguration(
            categoryKind: .income,
            month: february,
            totalAmount: 300_000,
            categoryLimits: [IncomeCategory.salary.rawValue: 250_000],
            currency: "RUB"
        )

        let expenseSuggestion = viewModel.previousMonthlyBudgetSuggestion(for: march, categoryKind: .expense)
        let incomeSuggestion = viewModel.previousMonthlyBudgetSuggestion(for: march, categoryKind: .income)

        #expect(expenseSuggestion?.totalAmount == 120_000)
        #expect(expenseSuggestion?.categoryLimits[ExpenseCategory.groceries.rawValue] == 40_000)
        #expect(expenseSuggestion?.categoryLimits[IncomeCategory.salary.rawValue] == nil)

        #expect(incomeSuggestion?.totalAmount == 300_000)
        #expect(incomeSuggestion?.categoryLimits[IncomeCategory.salary.rawValue] == 250_000)
        #expect(incomeSuggestion?.categoryLimits[ExpenseCategory.groceries.rawValue] == nil)
    }

    @Test("Выключение общего лимита и пустые категории удаляют месячную конфигурацию")
    func savingEmptyConfigurationDeletesMonthlyBudget() async throws {
        let context = try createTestModelContext()
        let march = monthDate(year: 2026, month: 3)
        let viewModel = CashflowViewModel(modelContext: context, now: { march })

        viewModel.saveMonthlyBudgetConfiguration(
            month: march,
            totalAmount: 120_000,
            categoryLimits: [ExpenseCategory.groceries.rawValue: 40_000],
            currency: "RUB"
        )

        viewModel.saveMonthlyBudgetConfiguration(
            month: march,
            totalAmount: 0,
            categoryLimits: [:],
            currency: "RUB"
        )

        let summary = await viewModel.monthlyBudgetSummary(for: .expense, month: march, in: "RUB")
        #expect(summary.plan == nil)
        #expect(summary.categoryLimits.isEmpty)
        #expect(summary.snapshot == nil)
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
