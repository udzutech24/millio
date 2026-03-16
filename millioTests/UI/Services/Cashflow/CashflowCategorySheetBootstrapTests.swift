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
}
