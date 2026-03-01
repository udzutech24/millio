//
//  CardManagerTests.swift
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
struct CardManagerTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([Card.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func createTestModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.deleteAll(Card.self)
        try context.save()
        return context
    }

    @Test("getAllCards фильтрует архивные карты")
    func testGetAllCardsFiltersArchived() throws {
        let context = try createTestModelContext()

        let active = Card(name: "Активная", cardNumber: "1111", bank: .sberbank, cardType: .debit, currency: "RUB")
        let archived = Card(name: "Архивная", cardNumber: "2222", bank: .sberbank, cardType: .debit, currency: "RUB")
        archived.archivedAt = Date()

        context.insert(active)
        context.insert(archived)
        try context.save()

        CardManager.shared.setup(modelContext: context)
        let cards = CardManager.shared.getAllCards()

        #expect(cards.count == 1)
        #expect(cards.first?.name == "Активная")
    }

    @Test("getAllCards сортирует: избранные первыми")
    func testGetAllCardsSortsFavoritesFirst() throws {
        let context = try createTestModelContext()

        let normal = Card(name: "Обычная", cardNumber: "1111", bank: .sberbank, cardType: .debit, currency: "RUB")
        normal.isFavorite = false

        let favorite = Card(name: "Избранная", cardNumber: "2222", bank: .tinkoff, cardType: .debit, currency: "RUB")
        favorite.isFavorite = true

        context.insert(normal)
        context.insert(favorite)
        try context.save()

        CardManager.shared.setup(modelContext: context)
        let cards = CardManager.shared.getAllCards()

        #expect(cards.first?.name == "Избранная")
    }

    @Test("getAllCards сортирует по приоритету внутри избранных")
    func testGetAllCardsSortsByPriorityWithinFavorites() throws {
        let context = try createTestModelContext()

        let lowPriority = Card(name: "Избранная Низкий", cardNumber: "1111", bank: .sberbank, cardType: .debit, priority: .low, currency: "RUB", isFavorite: true)
        let highPriority = Card(name: "Избранная Высокий", cardNumber: "2222", bank: .tinkoff, cardType: .debit, priority: .high, currency: "RUB", isFavorite: true)
        let normalPriority = Card(name: "Избранная Обычный", cardNumber: "3333", bank: .vtb, cardType: .debit, priority: .normal, currency: "RUB", isFavorite: true)

        context.insert(lowPriority)
        context.insert(highPriority)
        context.insert(normalPriority)
        try context.save()

        CardManager.shared.setup(modelContext: context)
        let cards = CardManager.shared.getAllCards()

        #expect(cards.count == 3)
        #expect(cards.map(\.name) == ["Избранная Высокий", "Избранная Обычный", "Избранная Низкий"])
    }

    @Test("getFavoriteCards возвращает только избранные")
    func testGetFavoriteCards() throws {
        let context = try createTestModelContext()

        let normal = Card(name: "Обычная", cardNumber: "1111", bank: .sberbank, cardType: .debit, currency: "RUB")
        normal.isFavorite = false

        let favorite = Card(name: "Избранная", cardNumber: "2222", bank: .tinkoff, cardType: .debit, currency: "RUB")
        favorite.isFavorite = true

        context.insert(normal)
        context.insert(favorite)
        try context.save()

        CardManager.shared.setup(modelContext: context)
        let favorites = CardManager.shared.getFavoriteCards()

        #expect(favorites.count == 1)
        #expect(favorites.first?.name == "Избранная")
    }

    @Test("getFavoriteCards сортирует по приоритету")
    func testGetFavoriteCardsSortsByPriority() throws {
        let context = try createTestModelContext()

        let lowPriority = Card(name: "Низкий", cardNumber: "1111", bank: .sberbank, cardType: .debit, priority: .low, currency: "RUB", isFavorite: true)
        let highPriority = Card(name: "Высокий", cardNumber: "2222", bank: .tinkoff, cardType: .debit, priority: .high, currency: "RUB", isFavorite: true)

        context.insert(lowPriority)
        context.insert(highPriority)
        try context.save()

        CardManager.shared.setup(modelContext: context)
        let favorites = CardManager.shared.getFavoriteCards()

        #expect(favorites.count == 2)
        #expect(favorites.map(\.name) == ["Высокий", "Низкий"])
    }

    @Test("getCards(by currency) фильтрует по валюте")
    func testGetCardsByCurrency() throws {
        let context = try createTestModelContext()

        let rubCard = Card(name: "Рублёвая", cardNumber: "1111", bank: .sberbank, cardType: .debit, currency: "RUB")
        let usdCard = Card(name: "Долларовая", cardNumber: "2222", bank: .tinkoff, cardType: .debit, currency: "USD")

        context.insert(rubCard)
        context.insert(usdCard)
        try context.save()

        CardManager.shared.setup(modelContext: context)

        let rubCards = CardManager.shared.getCards(by: "RUB")
        #expect(rubCards.count == 1)
        #expect(rubCards.first?.name == "Рублёвая")

        let usdCards = CardManager.shared.getCards(by: "USD")
        #expect(usdCards.count == 1)
        #expect(usdCards.first?.name == "Долларовая")
    }

    @Test("getCards(by bank) фильтрует по банку")
    func testGetCardsByBank() throws {
        let context = try createTestModelContext()

        let sberCard = Card(name: "Сбер", cardNumber: "1111", bank: .sberbank, cardType: .debit, currency: "RUB")
        let tinkoffCard = Card(name: "Тинькофф", cardNumber: "2222", bank: .tinkoff, cardType: .debit, currency: "RUB")

        context.insert(sberCard)
        context.insert(tinkoffCard)
        try context.save()

        CardManager.shared.setup(modelContext: context)

        let sberCards = CardManager.shared.getCards(by: .sberbank)
        #expect(sberCards.count == 1)
        #expect(sberCards.first?.name == "Сбер")

        let tinkoffCards = CardManager.shared.getCards(by: .tinkoff)
        #expect(tinkoffCards.count == 1)
        #expect(tinkoffCards.first?.name == "Тинькофф")
    }

    @Test("getTotalBalance считает сумму всех балансов")
    func testGetTotalBalance() throws {
        let context = try createTestModelContext()

        let card1 = Card(name: "Карта 1", cardNumber: "1111", bank: .sberbank, cardType: .debit, currency: "RUB")
        card1.balance = 10000

        let card2 = Card(name: "Карта 2", cardNumber: "2222", bank: .tinkoff, cardType: .debit, currency: "RUB")
        card2.balance = 5000

        context.insert(card1)
        context.insert(card2)
        try context.save()

        CardManager.shared.setup(modelContext: context)
        let total = CardManager.shared.getTotalBalance()

        #expect(abs(total - 15000) < 0.01)
    }

    @Test("getTotalBalance(currency:) считает баланс по валюте")
    func testGetTotalBalanceByCurrency() throws {
        let context = try createTestModelContext()

        let rubCard = Card(name: "Рублёвая", cardNumber: "1111", bank: .sberbank, cardType: .debit, currency: "RUB")
        rubCard.balance = 10000

        let usdCard = Card(name: "Долларовая", cardNumber: "2222", bank: .tinkoff, cardType: .debit, currency: "USD")
        usdCard.balance = 500

        context.insert(rubCard)
        context.insert(usdCard)
        try context.save()

        CardManager.shared.setup(modelContext: context)

        let rubTotal = CardManager.shared.getTotalBalance(currency: "RUB")
        #expect(abs(rubTotal - 10000) < 0.01)

        let usdTotal = CardManager.shared.getTotalBalance(currency: "USD")
        #expect(abs(usdTotal - 500) < 0.01)
    }

    @Test("Кредитная карта: долг и остаток лимита считаются из лимита и доступного баланса")
    func testCreditCardDebtAndAvailableCreditCalculation() {
        let card = Card(
            name: "Кредитная",
            cardNumber: "1234",
            bank: .other,
            cardType: .credit,
            currency: "RUB",
            balance: 7_000,
            creditLimit: 10_000
        )

        #expect(abs(card.debt - 3_000) < 0.01)
        #expect(abs(card.availableCredit - 3_000) < 0.01)
    }

    @Test("Кредитная карта: долг не уходит в минус при балансе выше лимита")
    func testCreditCardDebtDoesNotBecomeNegative() {
        let card = Card(
            name: "Кредитная",
            cardNumber: "1234",
            bank: .other,
            cardType: .credit,
            currency: "RUB",
            balance: 12_000,
            creditLimit: 10_000
        )

        #expect(card.debt == 0)
        #expect(card.availableCredit == 0)
    }
}
