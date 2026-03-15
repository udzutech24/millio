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
        let cards = CardCatalog.fetchAll(in: modelContext)
        return sortCards(cards.filter { $0.archivedAt == nil })
    }
    
    /// Получить избранные карты
    func getFavoriteCards() -> [Card] {
        guard let modelContext = modelContext else { return [] }
        let cards = CardCatalog.fetchAll(in: modelContext)
        return sortCards(cards.filter { $0.archivedAt == nil && $0.isFavorite })
    }
    
    /// Получить карты по валюте
    func getCards(by currency: String) -> [Card] {
        guard let modelContext = modelContext else { return [] }
        let cards = CardCatalog.fetchAll(in: modelContext)
        return sortCards(cards.filter { $0.archivedAt == nil && $0.currency == currency })
    }
    
    /// Получить карты по банку
    func getCards(by bank: Bank) -> [Card] {
        guard let modelContext = modelContext else { return [] }
        let cards = CardCatalog.fetchAll(in: modelContext)
        return sortCards(cards.filter { $0.archivedAt == nil && $0.bankRaw == bank.rawValue })
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
        CardCatalog.sortForDisplay(cards)
    }
}
