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
            Card.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    /// Получить чистый контекст (очищаем данные от предыдущих тестов)
    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
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
}
