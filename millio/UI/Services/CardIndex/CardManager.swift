//
//  CardManager.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Глобальный менеджер для доступа к картам из других сервисов
@MainActor
final class CardManager {
    static let shared = CardManager()
    
    private var modelContext: ModelContext?
    
    private init() {}
    
    /// Инициализация с ModelContext
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Получить все карты
    func getAllCards() -> [Card] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Card>()
        let cards = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.archivedAt == nil }

        return sortCards(cards)
    }
    
    /// Получить избранные карты
    func getFavoriteCards() -> [Card] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { $0.isFavorite == true }
        )
        let cards = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.archivedAt == nil }

        return sortCards(cards)
    }
    
    /// Получить карты по валюте
    func getCards(by currency: String) -> [Card] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { $0.currency == currency }
        )
        let cards = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.archivedAt == nil }

        return sortCards(cards)
    }
    
    /// Получить карты по банку
    func getCards(by bank: Bank) -> [Card] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { $0.bankRaw == bank.rawValue }
        )
        let cards = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.archivedAt == nil }

        return sortCards(cards)
    }
    
    /// Получить карту по ID
    func getCard(id: PersistentIdentifier) -> Card? {
        guard let modelContext = modelContext else { return nil }
        return modelContext.model(for: id) as? Card
    }
    
    /// Общий баланс всех карт
    func getTotalBalance() -> Double {
        getAllCards().reduce(0) { $0 + $1.balance }
    }
    
    /// Общий баланс по валюте
    func getTotalBalance(currency: String) -> Double {
        getCards(by: currency).reduce(0) { $0 + $1.balance }
    }

    private func sortCards(_ cards: [Card]) -> [Card] {
        cards.sorted { card1, card2 in
            if card1.isFavorite != card2.isFavorite {
                return card1.isFavorite
            }
            if card1.priority.sortOrder != card2.priority.sortOrder {
                return card1.priority.sortOrder < card2.priority.sortOrder
            }
            return card1.updatedAt > card2.updatedAt
        }
    }
}
