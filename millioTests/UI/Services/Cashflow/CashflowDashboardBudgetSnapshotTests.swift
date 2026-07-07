//
//  CashflowDashboardBudgetSnapshotTests.swift
//  millioTests
//
//  Фаза 1 редизайна add-flow (plans/2026-07-05__cashflow-add-transaction-redesign.md):
//  бюджет-карточка вынесена из формы добавления на главный экран Cashflow.
//  Тесты покрывают `reloadDashboardBudgetSnapshots` — per-kind снапшоты, R3 (пересчёт при смене
//  периода/месяца) и R6 (скрытие вне конкретного месяца / при отсутствии бюджета).
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct CashflowDashboardBudgetSnapshotTests {
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

    @Test("Карточка показывает и расходы, и доходы одновременно для конкретного месяца")
    func dashboardSnapshotsPopulateBothKindsForSpecificMonth() async throws {
        let context = try createTestModelContext()
        let march = monthDate(year: 2026, month: 3)
        let viewModel = CashflowViewModel(modelContext: context, now: { march })

        viewModel.saveMonthlyBudgetConfiguration(
            categoryKind: .expense,
            month: march,
            totalAmount: 100_000,
            categoryLimits: [:],
            currency: "RUB"
        )
        viewModel.saveMonthlyBudgetConfiguration(
            categoryKind: .income,
            month: march,
            totalAmount: 200_000,
            categoryLimits: [:],
            currency: "RUB"
        )

        viewModel.state.chartPeriod = .specificMonth
        viewModel.state.selectedMonth = march
        await viewModel.updateChartDataAsync()

        #expect(viewModel.state.dashboardExpenseBudgetSnapshot?.limit == 100_000)
        #expect(viewModel.state.dashboardIncomeBudgetSnapshot?.limit == 200_000)
    }

    @Test("Вне конкретного месяца (квартал/год/произвольный период) карточка скрывается — R6")
    func dashboardSnapshotsHiddenOutsideSpecificMonth() async throws {
        let context = try createTestModelContext()
        let march = monthDate(year: 2026, month: 3)
        let viewModel = CashflowViewModel(modelContext: context, now: { march })

        viewModel.saveMonthlyBudgetConfiguration(
            categoryKind: .expense,
            month: march,
            totalAmount: 100_000,
            categoryLimits: [:],
            currency: "RUB"
        )

        viewModel.state.chartPeriod = .specificMonth
        viewModel.state.selectedMonth = march
        await viewModel.updateChartDataAsync()
        #expect(viewModel.state.dashboardExpenseBudgetSnapshot != nil)

        viewModel.state.chartPeriod = .specificQuarter
        viewModel.state.selectedQuarter = march
        await viewModel.updateChartDataAsync()

        #expect(viewModel.state.dashboardExpenseBudgetSnapshot == nil)
        #expect(viewModel.state.dashboardIncomeBudgetSnapshot == nil)
    }

    @Test("Пустой стор без настроенного бюджета — оба снапшота nil (R6)")
    func dashboardSnapshotsNilWhenNoBudgetConfigured() async throws {
        let context = try createTestModelContext()
        let march = monthDate(year: 2026, month: 3)
        let viewModel = CashflowViewModel(modelContext: context, now: { march })

        viewModel.state.chartPeriod = .specificMonth
        viewModel.state.selectedMonth = march
        await viewModel.updateChartDataAsync()

        #expect(viewModel.state.dashboardExpenseBudgetSnapshot == nil)
        #expect(viewModel.state.dashboardIncomeBudgetSnapshot == nil)
    }

    @Test("Смена выбранного месяца пересчитывает карточку под новый месяц — R3")
    func dashboardSnapshotsRecomputeOnMonthChange() async throws {
        let context = try createTestModelContext()
        let february = monthDate(year: 2026, month: 2)
        let march = monthDate(year: 2026, month: 3)
        let viewModel = CashflowViewModel(modelContext: context, now: { march })

        viewModel.saveMonthlyBudgetConfiguration(
            categoryKind: .expense,
            month: february,
            totalAmount: 50_000,
            categoryLimits: [:],
            currency: "RUB"
        )
        viewModel.saveMonthlyBudgetConfiguration(
            categoryKind: .expense,
            month: march,
            totalAmount: 90_000,
            categoryLimits: [:],
            currency: "RUB"
        )

        viewModel.state.chartPeriod = .specificMonth
        viewModel.state.selectedMonth = february
        await viewModel.updateChartDataAsync()
        #expect(viewModel.state.dashboardExpenseBudgetSnapshot?.limit == 50_000)

        viewModel.state.selectedMonth = march
        await viewModel.updateChartDataAsync()
        #expect(viewModel.state.dashboardExpenseBudgetSnapshot?.limit == 90_000)
    }
}
