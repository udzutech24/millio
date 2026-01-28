//
//  CardViewModelTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 28.01.2026.
//

import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct CardViewModelTests {

    /// Общий контейнер для всех тестов (SwiftData нестабилен при создании множества контейнеров)
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
            CashflowTransaction.self
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

    @Test("Карту можно создать без последних 4 цифр")
    func testCreateCardWithEmptyNumber() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CardViewModel(modelContext: modelContext)

        let card = Card(
            name: "Карта без номера",
            cardNumber: "",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 0.0
        )

        viewModel.handle(.updateCard(card))

        let descriptor = FetchDescriptor<Card>()
        let cards = (try? modelContext.fetch(descriptor)) ?? []

        #expect(cards.count == 1)
        #expect(cards.first?.cardNumber == "")
    }

    @Test("Редактирование баланса дебетовой карты создает транзакцию корректировки")
    func testEditDebitCardCreatesBalanceAdjustmentTransaction() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CardViewModel(modelContext: modelContext)

        let card = Card(
            name: "Дебетовая карта",
            cardNumber: "1234",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 100.0
        )
        modelContext.insert(card)
        try modelContext.save()

        viewModel.handle(.editCard(card))

        let updated = Card(
            name: card.name,
            cardNumber: card.cardNumber,
            bank: card.bank,
            cardType: card.cardType,
            priority: card.priority,
            currency: card.currency,
            balance: 150.0,
            creditLimit: card.creditLimit,
            expiryDate: card.expiryDate,
            cardholderName: card.cardholderName,
            cardColor: card.cardColor,
            isFavorite: card.isFavorite,
            includeInTotal: card.includeInTotal
        )

        viewModel.handle(.updateCard(updated))

        let descriptor = FetchDescriptor<CashflowTransaction>()
        let transactions = (try? modelContext.fetch(descriptor)) ?? []

        #expect(transactions.count == 1)
        #expect(transactions.first?.transactionType == .cardBalanceAdjustment)
        #expect(abs((transactions.first?.amount ?? 0) - 50.0) < 0.01)
    }

    @Test("Редактирование баланса кредитной карты создает транзакцию корректировки долга")
    func testEditCreditCardCreatesDebtAdjustmentTransaction() throws {
        let modelContext = try createTestModelContext()
        let viewModel = CardViewModel(modelContext: modelContext)

        let card = Card(
            name: "Кредитная карта",
            cardNumber: "5678",
            bank: .other,
            cardType: .credit,
            currency: "RUB",
            balance: 200.0,
            creditLimit: 1000.0
        )
        modelContext.insert(card)
        try modelContext.save()

        viewModel.handle(.editCard(card))

        let updated = Card(
            name: card.name,
            cardNumber: card.cardNumber,
            bank: card.bank,
            cardType: card.cardType,
            priority: card.priority,
            currency: card.currency,
            balance: 150.0,
            creditLimit: card.creditLimit,
            expiryDate: card.expiryDate,
            cardholderName: card.cardholderName,
            cardColor: card.cardColor,
            isFavorite: card.isFavorite,
            includeInTotal: card.includeInTotal
        )

        viewModel.handle(.updateCard(updated))

        let descriptor = FetchDescriptor<CashflowTransaction>()
        let transactions = (try? modelContext.fetch(descriptor)) ?? []

        #expect(transactions.count == 1)
        #expect(transactions.first?.transactionType == .creditDebtAdjustment)
        #expect(abs((transactions.first?.amount ?? 0) - (-50.0)) < 0.01)
    }
}
