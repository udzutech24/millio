//
//  CashflowViewModelTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 29.01.2026.
//

import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct CashflowViewModelTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
            CashflowTransaction.self,
            HistoricalRate.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.deleteAll(CashflowTransaction.self)
        try context.deleteAll(HistoricalRate.self)
        try context.deleteAll(Card.self)
        try context.save()
        return context
    }

    @Test("Расход не превышает доступный баланс карты")
    func testExpenseCannotExceedBalance() async throws {
        let modelContext = try createTestModelContext()
        let card = Card(
            name: "Карта",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000.0
        )
        modelContext.insert(card)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        viewModel.handle(.loadCards)

        let available = try await viewModel.isAmountAvailable(
            amount: 1_500.0,
            currency: "RUB",
            fromCardID: card.cardUniqueID,
            on: Date()
        )
        #expect(!available)
    }

    @Test("Перевод разрешен в пределах доступного баланса")
    func testTransferWithinBalanceAllowed() async throws {
        let modelContext = try createTestModelContext()
        let card = Card(
            name: "Карта",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000.0
        )
        modelContext.insert(card)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        viewModel.handle(.loadCards)

        let available = try await viewModel.isAmountAvailable(
            amount: 500.0,
            currency: "RUB",
            fromCardID: card.cardUniqueID,
            on: Date()
        )
        #expect(available)
    }

    @Test("Cashflow обновляет историю по событию transactionsUpdated")
    func testTransactionsUpdatedEventReloadsTransactions() async throws {
        let modelContext = try createTestModelContext()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        #expect(viewModel.state.transactions.isEmpty)

        let transaction = CashflowTransaction(
            transactionType: .income,
            amount: 1000,
            currency: "RUB",
            transactionDate: Date(),
            cardID: nil,
            note: "Тест"
        )
        modelContext.insert(transaction)
        try modelContext.save()

        EventBus.shared.publish(FinanceEvent.transactionsUpdated)

        #expect(viewModel.state.transactions.count == 1)
        #expect(viewModel.state.transactions.first?.note == "Тест")
    }

    @Test("Стрелки периода переключают месяцы и не уходят в будущее")
    func testMonthNavigationByArrows() async throws {
        let modelContext = try createTestModelContext()
        let fixedNow = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 13)) ?? Date()
        let viewModel = CashflowViewModel(modelContext: modelContext, now: { fixedNow })

        let calendar = Calendar.current
        let initialMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: fixedNow)) ?? fixedNow

        #expect(!viewModel.canMovePeriodForward())

        viewModel.handle(.movePeriodBackward)
        #expect(viewModel.state.chartPeriod == .specificMonth)
        #expect(calendar.component(.month, from: viewModel.state.selectedMonth) == 1)
        #expect(calendar.component(.year, from: viewModel.state.selectedMonth) == 2026)
        #expect(viewModel.canMovePeriodForward())

        viewModel.handle(.movePeriodForward)
        #expect(calendar.component(.month, from: viewModel.state.selectedMonth) == calendar.component(.month, from: initialMonth))
        #expect(calendar.component(.year, from: viewModel.state.selectedMonth) == calendar.component(.year, from: initialMonth))
        #expect(!viewModel.canMovePeriodForward())

        viewModel.handle(.movePeriodForward)
        #expect(calendar.component(.month, from: viewModel.state.selectedMonth) == calendar.component(.month, from: initialMonth))
        #expect(calendar.component(.year, from: viewModel.state.selectedMonth) == calendar.component(.year, from: initialMonth))
    }
}
