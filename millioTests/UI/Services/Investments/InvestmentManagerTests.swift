//
//  InvestmentManagerTests.swift
//  millioTests
//
//  Created by Claude on 01.02.2026.
//

import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct InvestmentManagerTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([Investment.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.deleteAll(Investment.self)
        try context.save()
        return context
    }

    @Test("getAllInvestments фильтрует архивные")
    func testGetAllInvestmentsFiltersArchived() throws {
        let context = try createTestModelContext()

        let active = Investment(
            name: "Активная",
            investmentType: .positive,
            category: .stocks,
            amount: 100000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        let archived = Investment(
            name: "Архивная",
            investmentType: .positive,
            category: .crypto,
            amount: 50000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        archived.archivedAt = Date()

        context.insert(active)
        context.insert(archived)
        try context.save()

        InvestmentManager.shared.setup(modelContext: context)
        let investments = InvestmentManager.shared.getAllInvestments()

        #expect(investments.count == 1)
        #expect(investments.first?.name == "Активная")
    }

    @Test("getInvestments(by type) фильтрует по типу")
    func testGetInvestmentsByType() throws {
        let context = try createTestModelContext()

        let positive = Investment(
            name: "Плюсовая",
            investmentType: .positive,
            category: .stocks,
            amount: 100000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        let negative = Investment(
            name: "Минусовая",
            investmentType: .negative,
            category: .car,
            amount: 50000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        context.insert(positive)
        context.insert(negative)
        try context.save()

        InvestmentManager.shared.setup(modelContext: context)

        let positives = InvestmentManager.shared.getInvestments(by: .positive)
        #expect(positives.count == 1)
        #expect(positives.first?.name == "Плюсовая")

        let negatives = InvestmentManager.shared.getInvestments(by: .negative)
        #expect(negatives.count == 1)
        #expect(negatives.first?.name == "Минусовая")
    }

    @Test("getInvestments(by category) фильтрует по категории")
    func testGetInvestmentsByCategory() throws {
        let context = try createTestModelContext()

        let stocks = Investment(
            name: "Акции",
            investmentType: .positive,
            category: .stocks,
            amount: 100000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        let crypto = Investment(
            name: "Крипта",
            investmentType: .positive,
            category: .crypto,
            amount: 50000,
            currency: "USD",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        context.insert(stocks)
        context.insert(crypto)
        try context.save()

        InvestmentManager.shared.setup(modelContext: context)

        let stocksResult = InvestmentManager.shared.getInvestments(by: .stocks)
        #expect(stocksResult.count == 1)
        #expect(stocksResult.first?.name == "Акции")

        let cryptoResult = InvestmentManager.shared.getInvestments(by: .crypto)
        #expect(cryptoResult.count == 1)
        #expect(cryptoResult.first?.name == "Крипта")
    }

    @Test("getInvestmentsIncludedInTotal возвращает только учитываемые")
    func testGetInvestmentsIncludedInTotal() throws {
        let context = try createTestModelContext()

        let included = Investment(
            name: "Учитываемая",
            investmentType: .positive,
            category: .stocks,
            amount: 100000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        let notIncluded = Investment(
            name: "Не учитываемая",
            investmentType: .positive,
            category: .crypto,
            amount: 50000,
            currency: "RUB",
            includeInTotal: false,
            priority: .normal,
            isFavorite: false
        )

        context.insert(included)
        context.insert(notIncluded)
        try context.save()

        InvestmentManager.shared.setup(modelContext: context)
        let result = InvestmentManager.shared.getInvestmentsIncludedInTotal()

        #expect(result.count == 1)
        #expect(result.first?.name == "Учитываемая")
    }

    @Test("getTotalPositiveInvestments считает сумму плюсовых")
    func testGetTotalPositiveInvestments() throws {
        let context = try createTestModelContext()

        let positive1 = Investment(
            name: "Плюс 1",
            investmentType: .positive,
            category: .stocks,
            amount: 100000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        let positive2 = Investment(
            name: "Плюс 2",
            investmentType: .positive,
            category: .crypto,
            amount: 50000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        let negative = Investment(
            name: "Минус",
            investmentType: .negative,
            category: .car,
            amount: 30000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        context.insert(positive1)
        context.insert(positive2)
        context.insert(negative)
        try context.save()

        InvestmentManager.shared.setup(modelContext: context)
        let total = InvestmentManager.shared.getTotalPositiveInvestments()

        #expect(abs(total - 150000) < 0.01)
    }

    @Test("getTotalInvestmentsIncluded учитывает знак типа")
    func testGetTotalInvestmentsIncluded() throws {
        let context = try createTestModelContext()

        let positive = Investment(
            name: "Плюс",
            investmentType: .positive,
            category: .stocks,
            amount: 100000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        let negative = Investment(
            name: "Минус",
            investmentType: .negative,
            category: .car,
            amount: 30000,
            currency: "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )

        context.insert(positive)
        context.insert(negative)
        try context.save()

        InvestmentManager.shared.setup(modelContext: context)
        let total = InvestmentManager.shared.getTotalInvestmentsIncluded()

        // 100000 - 30000 = 70000
        #expect(abs(total - 70000) < 0.01)
    }
}
