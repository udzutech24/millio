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

    @Test("Сводка активов считает изменение стоимости по формуле и использует снапшот из Финансов")
    func testAssetsBreakdownFormula() async throws {
        let modelContext = try createTestModelContext()
        let fixedNow = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 13)) ?? Date()
        let defaults = UserDefaults.standard
        let previousDisplayCurrency = defaults.string(forKey: "cashflow_display_currency")
        defaults.set("RUB", forKey: "cashflow_display_currency")
        defer {
            if let previousDisplayCurrency {
                defaults.set(previousDisplayCurrency, forKey: "cashflow_display_currency")
            } else {
                defaults.removeObject(forKey: "cashflow_display_currency")
            }
        }

        let income = CashflowTransaction(
            transactionType: .income,
            amount: 500,
            currency: "RUB",
            transactionDate: fixedNow,
            cardID: nil
        )
        let expense = CashflowTransaction(
            transactionType: .expense,
            amount: 100,
            currency: "RUB",
            transactionDate: fixedNow,
            cardID: nil
        )
        modelContext.insert(income)
        modelContext.insert(expense)
        try modelContext.save()

        let viewModel = CashflowViewModel(
            modelContext: modelContext,
            now: { fixedNow },
            assetsSnapshotProvider: { _, _, _ in
                (start: 1_000, end: 1_300)
            }
        )

        viewModel.handle(.loadTransactions)

        try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            abs(viewModel.state.assetsAtPeriodStart - 1_000) < 0.01 &&
            abs(viewModel.state.assetsAtPeriodEnd - 1_300) < 0.01 &&
            abs(viewModel.state.totalIncome - 500) < 0.01 &&
            abs(viewModel.state.contributedExpense - 100) < 0.01 &&
            abs(viewModel.state.assetValueChange + 100) < 0.01 &&
            abs(viewModel.state.periodTotalChange - 300) < 0.01
        }

        #expect(abs(viewModel.state.assetsAtPeriodStart - 1_000) < 0.01)
        #expect(abs(viewModel.state.assetsAtPeriodEnd - 1_300) < 0.01)
        #expect(abs(viewModel.state.totalIncome - 500) < 0.01)
        #expect(abs(viewModel.state.contributedExpense - 100) < 0.01)
        #expect(abs(viewModel.state.assetValueChange + 100) < 0.01) // 300 - 500 + 100 = -100
        #expect(abs(viewModel.state.periodTotalChange - 300) < 0.01)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64,
        intervalNanoseconds: UInt64 = 50_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: intervalNanoseconds)
        }
        #expect(Bool(false), "Condition was not met before timeout")
    }
}
