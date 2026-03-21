//
//  CashflowCategorySheetBootstrapTests.swift
//  millioTests
//
//  Created by Codex on 16.03.2026.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct CashflowCategorySheetBootstrapTests {
    private static let schema = Schema([
        Card.self,
        FinanceGroup.self,
        FinanceAccount.self,
        CashflowTransaction.self,
        CashflowCustomCategory.self,
        CashflowSystemCategoryOverride.self,
        HistoricalRate.self
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

    @Test("Bootstrap category-sheet подтягивает операции и карты для быстрого входа")
    func bootstrapRefreshesStaleCashflowViewModel() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CashflowViewModel(modelContext: modelContext)

        #expect(viewModel.state.availableCards.isEmpty)
        #expect(viewModel.state.transactions.isEmpty)

        let card = Card(
            name: "Main",
            cardNumber: "1234",
            bank: .tinkoff,
            cardType: .debit,
            currency: "RUB",
            balance: 5_000
        )
        modelContext.insert(card)

        let transaction = CashflowTransaction(
            transactionType: .income,
            amount: 1_300,
            currency: "RUB",
            transactionDate: Date(),
            cardID: card.cardUniqueID,
            incomeCategory: .salary,
            affectsCardBalance: true
        )
        modelContext.insert(transaction)
        try modelContext.save()

        CashflowCategorySheetBootstrap.prepare(viewModel: viewModel)

        #expect(viewModel.state.availableCards.contains { $0.cardUniqueID == card.cardUniqueID })
        #expect(viewModel.state.transactions.contains { $0.persistentModelID == transaction.persistentModelID })
    }

    @Test("Новая операция из выбранного месяца берет сегодняшний день внутри этого месяца")
    func initialTransactionDateKeepsReferenceDayInsideSelectedMonth() {
        let calendar = Calendar.current
        let selectedMonth = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 21, hour: 11, minute: 59))!

        let result = CashflowCategorySheetBootstrap.initialTransactionDate(
            forSelectedMonth: selectedMonth,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        #expect(components.year == 2026)
        #expect(components.month == 2)
        #expect(components.day == 21)
        #expect(components.hour == 11)
        #expect(components.minute == 59)
    }

    @Test("Новая операция из короткого месяца зажимает день в конец месяца")
    func initialTransactionDateClampsOverflowDayToMonthEnd() {
        let calendar = Calendar.current
        let selectedMonth = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 31, hour: 9, minute: 30))!

        let result = CashflowCategorySheetBootstrap.initialTransactionDate(
            forSelectedMonth: selectedMonth,
            referenceDate: referenceDate,
            calendar: calendar
        )

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        #expect(components.year == 2026)
        #expect(components.month == 2)
        #expect(components.day == 28)
        #expect(components.hour == 9)
        #expect(components.minute == 30)
    }
}
