//
//  CashflowViewModelTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 27.01.2026.
//

import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct CashflowViewModelTests {

    /// Общий контейнер для всех тестов (SwiftData нестабилен при создании множества контейнеров)
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
            CashflowTransaction.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    /// Получить чистый контекст (очищаем данные от предыдущих тестов)
    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.delete(model: CashflowTransaction.self)
        try context.delete(model: Card.self)
        try context.save()
        return context
    }

    @Test("Открытие создания транзакции подтягивает новые карты")
    func testAddTransactionRefreshesCards() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CashflowViewModel(modelContext: modelContext)

        #expect(viewModel.state.availableCards.isEmpty)

        let newCard = Card(
            name: "Новая карта",
            cardNumber: "1234",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 100.0
        )
        modelContext.insert(newCard)
        try modelContext.save()

        viewModel.handle(.addTransaction(.expense))

        let cardIDs = Set(viewModel.state.availableCards.map { $0.cardUniqueID })
        #expect(cardIDs.contains(newCard.cardUniqueID))
    }

    @Test("Удаленная карта не попадает в список при создании транзакции")
    func testAddTransactionRefreshesCardsAfterDelete() throws {
        let modelContext = try createTestModelContext()

        let firstCard = Card(
            name: "Первая карта",
            cardNumber: "1111",
            bank: .sberbank,
            cardType: .debit,
            currency: "RUB",
            balance: 50.0
        )
        let secondCard = Card(
            name: "Вторая карта",
            cardNumber: "2222",
            bank: .vtb,
            cardType: .debit,
            currency: "RUB",
            balance: 75.0
        )
        modelContext.insert(firstCard)
        modelContext.insert(secondCard)
        try modelContext.save()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        #expect(viewModel.state.availableCards.count == 2)

        modelContext.delete(secondCard)
        try modelContext.save()

        viewModel.handle(.addTransaction(.income))

        let cardIDs = Set(viewModel.state.availableCards.map { $0.cardUniqueID })
        #expect(cardIDs.contains(firstCard.cardUniqueID))
        #expect(!cardIDs.contains(secondCard.cardUniqueID))
    }

    @Test("Событие обновления карт синхронизирует список в Кэшфлоу")
    func testCardsUpdatedEventRefreshesCashflowCards() throws {
        let modelContext = try createTestModelContext()

        let viewModel = CashflowViewModel(modelContext: modelContext)
        #expect(viewModel.state.availableCards.isEmpty)

        let newCard = Card(
            name: "Карта для события",
            cardNumber: "9999",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 10.0
        )
        modelContext.insert(newCard)
        try modelContext.save()

        EventBus.shared.publish(FinanceEvent.cardsUpdated)

        let cardIDs = Set(viewModel.state.availableCards.map { $0.cardUniqueID })
        #expect(cardIDs.contains(newCard.cardUniqueID))
    }
}
