//
//  InvisibleTabChartRecomputeTests.swift
//  millioTests
//
//  Политика частоты пересчёта финансовых агрегатов: невидимая вкладка не считает свой график,
//  а отложенный пересчёт выполняется один раз при её показе.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct InvisibleTabChartRecomputeTests {
    private static let schema = Schema([
        Card.self,
        Credit.self,
        Investment.self,
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
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        let context = container.mainContext
        try context.save()
        return context
    }

    // MARK: - Cashflow

    @Test("Кэшфлоу: невидимая вкладка откладывает пересчёт графика")
    func cashflowDefersChartRecomputeWhileHidden() throws {
        let context = try createTestModelContext()
        let viewModel = CashflowViewModel(modelContext: context)

        viewModel.isScreenVisible = false
        viewModel.pendingChartRefresh = false

        viewModel.updateChartData()

        #expect(viewModel.pendingChartRefresh == true)
    }

    @Test("Кэшфлоу: показ вкладки выполняет отложенный пересчёт один раз")
    func cashflowRunsDeferredRecomputeOnBecomingVisible() throws {
        let context = try createTestModelContext()
        let viewModel = CashflowViewModel(modelContext: context)

        viewModel.isScreenVisible = false
        viewModel.updateChartData()
        #expect(viewModel.pendingChartRefresh == true)

        viewModel.isScreenVisible = true
        // Флаг гасится в didSet — отложенный пересчёт уже запущен и не повторится при следующем
        // показе той же вкладки без новых изменений данных.
        #expect(viewModel.pendingChartRefresh == false)
    }

    @Test("Кэшфлоу: видимая вкладка считает сразу, без откладывания")
    func cashflowVisibleScreenDoesNotDefer() throws {
        let context = try createTestModelContext()
        let viewModel = CashflowViewModel(modelContext: context)

        viewModel.pendingChartRefresh = false
        viewModel.updateChartData()

        #expect(viewModel.isScreenVisible == true)
        #expect(viewModel.pendingChartRefresh == false)
    }

    // MARK: - Dynamics

    @Test("Динамика: невидимая вкладка откладывает пересчёт графика")
    func dynamicsDefersChartRecomputeWhileHidden() throws {
        let context = try createTestModelContext()
        let financeViewModel = FinanceViewModel(
            modelContext: context,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )

        viewModel.isScreenVisible = false
        viewModel.pendingChartRefresh = false

        viewModel.updateChartData()

        #expect(viewModel.pendingChartRefresh == true)
    }

    @Test("Динамика: показ вкладки выполняет отложенный пересчёт один раз")
    func dynamicsRunsDeferredRecomputeOnBecomingVisible() throws {
        let context = try createTestModelContext()
        let financeViewModel = FinanceViewModel(
            modelContext: context,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: true
        )
        let viewModel = FinanceDynamicsViewModel(
            modelContext: context,
            financeViewModel: financeViewModel,
            currencyService: MockDynamicsCurrencyRateService()
        )

        viewModel.isScreenVisible = false
        viewModel.updateChartData()
        #expect(viewModel.pendingChartRefresh == true)

        viewModel.isScreenVisible = true
        #expect(viewModel.pendingChartRefresh == false)
    }

    // MARK: - Политика возврата из фона

    @Test("Возврат из фона пересчитывает не чаще чем раз в 5 минут")
    func foregroundStaleIntervalIsFiveMinutes() {
        #expect(FinanceRecomputePolicy.foregroundStaleInterval == 5 * 60)
    }
}
