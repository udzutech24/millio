//
//  InvestmentViewModelTests.swift
//  millioTests
//
//  Created by Claude on 01.02.2026.
//

import Foundation
import Testing
import SwiftData
@testable import millio

@MainActor
final class MockInvestmentCurrencyService: CurrencyRateServiceProtocol {
    var rates: [String: Double] = ["USD": 1.0, "RUB": 90.0, "EUR": 0.92]

    func getRate(from: String, to: String) async -> Double? {
        if from == to { return 1.0 }
        guard let fromRate = rates[from.uppercased()],
              let toRate = rates[to.uppercased()] else { return nil }
        return toRate / fromRate
    }

    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? {
        await getRate(from: from, to: to)
    }

    func convert(amount: Double, from: String, to: String) async -> Double? {
        guard let rate = await getRate(from: from, to: to) else { return nil }
        return amount * rate
    }

    func forceRefreshRates() async {}
}

@Suite(.serialized)
@MainActor
struct InvestmentViewModelTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Investment.self,
            CashflowTransaction.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.deleteAll(CashflowTransaction.self)
        try context.deleteAll(Investment.self)
        try context.save()
        return context
    }

    @Test("Загрузка инвестиций фильтрует архивные")
    func testLoadInvestmentsFiltersArchived() async throws {
        let context = try createTestModelContext()

        let active = Investment(
            name: "Активная",
            investmentType: .positive,
            category: .stocks,
            amount: 10000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        let archived = Investment(
            name: "Архивная",
            investmentType: .positive,
            category: .stocks,
            amount: 5000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        archived.archivedAt = Date()

        context.insert(active)
        context.insert(archived)
        try context.save()

        let viewModel = InvestmentViewModel(modelContext: context)

        #expect(viewModel.state.investments.count == 1)
        #expect(viewModel.state.investments.first?.name == "Активная")
    }

    @Test("Сортировка: избранные первыми")
    func testSortingFavoritesFirst() async throws {
        let context = try createTestModelContext()

        let normal = Investment(
            name: "Обычная",
            investmentType: .positive,
            category: .stocks,
            amount: 10000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        let favorite = Investment(
            name: "Избранная",
            investmentType: .positive,
            category: .stocks,
            amount: 5000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: true
        )

        context.insert(normal)
        context.insert(favorite)
        try context.save()

        let viewModel = InvestmentViewModel(modelContext: context)

        #expect(viewModel.state.investments.first?.name == "Избранная")
    }

    @Test("Сортировка: по приоритету (high → normal → low)")
    func testSortingByPriority() async throws {
        let context = try createTestModelContext()

        let low = Investment(
            name: "Низкий",
            investmentType: .positive,
            category: .stocks,
            amount: 1000,
            currency: "RUB",
            includeInTotal: true,
            priority: .low,
            isFavorite: false
        )
        let high = Investment(
            name: "Высокий",
            investmentType: .positive,
            category: .stocks,
            amount: 2000,
            currency: "RUB",
            includeInTotal: true,
            priority: .high,
            isFavorite: false
        )
        let normal = Investment(
            name: "Обычный",
            investmentType: .positive,
            category: .stocks,
            amount: 3000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        context.insert(low)
        context.insert(high)
        context.insert(normal)
        try context.save()

        let viewModel = InvestmentViewModel(modelContext: context)

        #expect(viewModel.state.investments[0].name == "Высокий")
        #expect(viewModel.state.investments[1].name == "Обычный")
        #expect(viewModel.state.investments[2].name == "Низкий")
    }

    @Test("Удаление инвестиции устанавливает archivedAt")
    func testDeleteInvestmentSetsArchivedAt() async throws {
        let context = try createTestModelContext()

        let investment = Investment(
            name: "Удаляемая",
            investmentType: .positive,
            category: .stocks,
            amount: 10000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        context.insert(investment)
        try context.save()

        let viewModel = InvestmentViewModel(modelContext: context)
        #expect(viewModel.state.investments.count == 1)

        viewModel.handle(.deleteInvestment(investment))

        #expect(viewModel.state.investments.count == 0)
        #expect(investment.archivedAt != nil)
    }

    @Test("Переключение избранного меняет флаг")
    func testToggleFavorite() async throws {
        let context = try createTestModelContext()

        let investment = Investment(
            name: "Тест",
            investmentType: .positive,
            category: .stocks,
            amount: 10000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        context.insert(investment)
        try context.save()

        let viewModel = InvestmentViewModel(modelContext: context)
        #expect(investment.isFavorite == false)

        viewModel.handle(.toggleFavorite(investment))
        #expect(investment.isFavorite == true)

        viewModel.handle(.toggleFavorite(investment))
        #expect(investment.isFavorite == false)
    }

    @Test("Создание новой инвестиции")
    func testCreateNewInvestment() async throws {
        let context = try createTestModelContext()

        let viewModel = InvestmentViewModel(modelContext: context)
        #expect(viewModel.state.investments.count == 0)

        viewModel.handle(.updateInvestment(
            name: "Новая инвестиция",
            investmentType: .positive,
            category: .crypto,
            amount: 50000,
            currency: "USD",
            includeInTotal: true,
            priority: .high,
            isFavorite: true,
            uniqueID: nil
        ))

        #expect(viewModel.state.investments.count == 1)
        #expect(viewModel.state.investments.first?.name == "Новая инвестиция")
        #expect(viewModel.state.investments.first?.amount == 50000)
        #expect(viewModel.state.investments.first?.investmentType == .positive)
    }

    @Test("Обновление инвестиции создаёт CashflowTransaction")
    func testUpdateInvestmentCreatesTransaction() async throws {
        let context = try createTestModelContext()

        let investment = Investment(
            name: "Акции",
            investmentType: .positive,
            category: .stocks,
            amount: 10000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        context.insert(investment)
        try context.save()

        let viewModel = InvestmentViewModel(modelContext: context)
        viewModel.handle(.editInvestment(investment))

        // Изменяем сумму
        viewModel.handle(.updateInvestment(
            name: "Акции",
            investmentType: .positive,
            category: .stocks,
            amount: 15000, // +5000
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false,
            uniqueID: investment.investmentUniqueID
        ))

        // Проверяем что создалась транзакция
        let descriptor = FetchDescriptor<CashflowTransaction>()
        let transactions = try context.fetch(descriptor)

        #expect(transactions.count == 1)
        #expect(abs(transactions.first!.amount - 5000) < 0.01)
        #expect(transactions.first!.investmentID == investment.investmentUniqueID)
    }

    @Test("Расчёт totalPositive и totalNegative")
    func testCalculateTotals() async throws {
        let context = try createTestModelContext()

        let positive1 = Investment(
            name: "Плюс 1",
            investmentType: .positive,
            category: .stocks,
            amount: 10000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        let positive2 = Investment(
            name: "Плюс 2",
            investmentType: .positive,
            category: .crypto,
            amount: 5000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        let negative = Investment(
            name: "Минус",
            investmentType: .negative,
            category: .car,
            amount: 3000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        context.insert(positive1)
        context.insert(positive2)
        context.insert(negative)
        try context.save()

        let viewModel = InvestmentViewModel(modelContext: context)

        // Ждём асинхронный расчёт
        try await Task.sleep(for: .milliseconds(100))

        #expect(abs(viewModel.state.totalPositive - 15000) < 0.01)
        #expect(abs(viewModel.state.totalNegative - 3000) < 0.01)
        #expect(abs(viewModel.state.balance - 12000) < 0.01)
    }

    @Test("Смена валюты отображения сохраняется")
    func testSetDisplayCurrencySaves() async throws {
        let context = try createTestModelContext()

        let viewModel = InvestmentViewModel(modelContext: context)
        let initialCurrency = viewModel.state.displayCurrency

        viewModel.handle(.setDisplayCurrency("USD"))

        #expect(viewModel.state.displayCurrency == "USD")

        // Создаём новый ViewModel и проверяем что валюта сохранилась
        let viewModel2 = InvestmentViewModel(modelContext: context)
        #expect(viewModel2.state.displayCurrency == "USD")

        // Возвращаем исходную валюту
        viewModel2.handle(.setDisplayCurrency(initialCurrency))
    }
}
