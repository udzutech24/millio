//
//  CardViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Card State

struct CardState {
    /// Все карты
    var cards: [Card] = []
    
    /// Отфильтрованные карты (для поиска)
    var filteredCards: [Card] = []
    
    /// Текст поиска
    var searchText: String = ""
    
    /// Выбранный фильтр банка
    var selectedBank: Bank? = nil
    
    /// Выбранный фильтр типа карты
    var selectedCardType: CardType? = nil
    
    /// Выбранный фильтр валюты
    var selectedCurrency: String? = nil
    
    /// Показывать ли экран добавления/редактирования
    var showCardEditor: Bool = false
    
    /// Редактируемая карта (nil = новая карта)
    var editingCard: Card? = nil
    
    /// Показывать ли статистику
    var showStats: Bool = false
    
    /// Общий баланс всех карт
    var totalBalance: Double = 0.0
    
    /// Баланс по валютам
    var balanceByCurrency: [String: Double] = [:]
}

// MARK: - Card Actions

enum CardAction {
    case loadCards
    case addCard
    case editCard(Card)
    case deleteCard(Card)
    case toggleFavorite(Card)
    case updateCard(Card)
    case search(String)
    case filterByBank(Bank?)
    case filterByCardType(CardType?)
    case filterByCurrency(String?)
    case clearFilters
    case showCardEditor
    case hideCardEditor
    case showStats
    case hideStats
}

// MARK: - Card ViewModel

@MainActor
final class CardViewModel: ViewModelProtocol {
    @Published var state = CardState()
    
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadCards()
    }
    
    func handle(_ action: CardAction) {
        switch action {
        case .loadCards:
            loadCards()
            
        case .addCard:
            state.editingCard = nil
            state.showCardEditor = true
            
        case .editCard(let card):
            state.editingCard = card
            state.showCardEditor = true
            
        case .deleteCard(let card):
            deleteCard(card)
            
        case .toggleFavorite(let card):
            toggleFavorite(card)
            
        case .updateCard(let card):
            updateCard(card)
            
        case .search(let text):
            state.searchText = text
            applyFilters()
            
        case .filterByBank(let bank):
            state.selectedBank = bank
            applyFilters()
            
        case .filterByCardType(let type):
            state.selectedCardType = type
            applyFilters()
            
        case .filterByCurrency(let currency):
            state.selectedCurrency = currency
            applyFilters()
            
        case .clearFilters:
            state.searchText = ""
            state.selectedBank = nil
            state.selectedCardType = nil
            state.selectedCurrency = nil
            applyFilters()
            
        case .showCardEditor:
            state.showCardEditor = true
            
        case .hideCardEditor:
            state.showCardEditor = false
            state.editingCard = nil
            
        case .showStats:
            state.showStats = true
            calculateStats()
            
        case .hideStats:
            state.showStats = false
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCards() {
        let descriptor = FetchDescriptor<Card>()
        if let cards = try? modelContext.fetch(descriptor) {
            // Сортируем вручную: сначала избранные, потом по дате обновления
            state.cards = cards.sorted { card1, card2 in
                if card1.isFavorite != card2.isFavorite {
                    return card1.isFavorite
                }
                return card1.updatedAt > card2.updatedAt
            }
            applyFilters()
            calculateStats()
            
            // Обновляем CardManager
            CardManager.shared.setup(modelContext: modelContext)
        }
    }
    
    private func applyFilters() {
        var filtered = state.cards
        
        // Фильтр по поисковому запросу
        if !state.searchText.isEmpty {
            let searchLower = state.searchText.lowercased()
            filtered = filtered.filter { card in
                card.name.lowercased().contains(searchLower) ||
                card.cardNumber.contains(searchLower) ||
                card.bank.displayName.lowercased().contains(searchLower) ||
                (card.cardholderName?.lowercased().contains(searchLower) ?? false)
            }
        }
        
        // Фильтр по банку
        if let bank = state.selectedBank {
            filtered = filtered.filter { $0.bank == bank }
        }
        
        // Фильтр по типу карты
        if let cardType = state.selectedCardType {
            filtered = filtered.filter { $0.cardType == cardType }
        }
        
        // Фильтр по валюте
        if let currency = state.selectedCurrency {
            filtered = filtered.filter { $0.currency == currency }
        }
        
        state.filteredCards = filtered
    }
    
    private func calculateStats() {
        state.totalBalance = state.cards.reduce(0) { $0 + $1.balance }
        
        var balanceByCurrency: [String: Double] = [:]
        for card in state.cards {
            balanceByCurrency[card.currency, default: 0] += card.balance
        }
        state.balanceByCurrency = balanceByCurrency
    }
    
    private func deleteCard(_ card: Card) {
        modelContext.delete(card)
        
        do {
            try modelContext.save()
            loadCards()
        } catch {
            AppLogger.log(.error, category: "Card", "Failed to delete card: \(error.localizedDescription)")
        }
    }
    
    private func toggleFavorite(_ card: Card) {
        card.isFavorite.toggle()
        card.updatedAt = Date()
        
        do {
            try modelContext.save()
            loadCards()
        } catch {
            AppLogger.log(.error, category: "Card", "Failed to toggle favorite: \(error.localizedDescription)")
        }
    }
    
    private func updateCard(_ card: Card) {
        if let existing = state.editingCard {
            // Обновляем существующую карту
            existing.name = card.name
            existing.cardNumber = card.cardNumber
            existing.bank = card.bank
            existing.cardType = card.cardType
            existing.currency = card.currency
            existing.balance = card.balance
            existing.creditLimit = card.creditLimit
            existing.expiryDate = card.expiryDate
            existing.cardholderName = card.cardholderName
            existing.cardColor = card.cardColor
            existing.isFavorite = card.isFavorite
            existing.updatedAt = Date()
        } else {
            // Создаем новую карту
            let newCard = Card(
                name: card.name,
                cardNumber: card.cardNumber,
                bank: card.bank,
                cardType: card.cardType,
                currency: card.currency,
                balance: card.balance,
                creditLimit: card.creditLimit,
                expiryDate: card.expiryDate,
                cardholderName: card.cardholderName,
                cardColor: card.cardColor,
                isFavorite: card.isFavorite
            )
            modelContext.insert(newCard)
        }
        
        do {
            try modelContext.save()
            loadCards()
            state.showCardEditor = false
            state.editingCard = nil
        } catch {
            AppLogger.log(.error, category: "Card", "Failed to save card: \(error.localizedDescription)")
        }
    }
}
