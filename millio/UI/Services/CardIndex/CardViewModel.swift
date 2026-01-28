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
    
    /// Показывать ли sheet выбора банка
    var showBankFilterSheet: Bool = false
    
    /// Показывать ли sheet выбора типа карты
    var showCardTypeFilterSheet: Bool = false
    
    /// Показывать ли sheet выбора валюты
    var showCurrencyFilterSheet: Bool = false
    
    /// Показывать ли sheet выбора валюты для отображения общего баланса
    var showDisplayCurrencySheet: Bool = false
    
    /// Валюта для отображения общего баланса
    var displayCurrency: String = "RUB"
    
    /// Общий баланс всех карт (в выбранной валюте)
    var totalBalance: Double = 0.0
    
    /// Баланс по валютам (оригинальные значения)
    var balanceByCurrency: [String: Double] = [:]
    
    /// Флаг загрузки курсов
    var isLoadingRates: Bool = false
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
    case showBankFilterSheet
    case hideBankFilterSheet
    case showCardTypeFilterSheet
    case hideCardTypeFilterSheet
    case showCurrencyFilterSheet
    case hideCurrencyFilterSheet
    case showDisplayCurrencySheet
    case hideDisplayCurrencySheet
    case setDisplayCurrency(String)
}

// MARK: - Card ViewModel

@MainActor
final class CardViewModel: ViewModelProtocol {
    @Published var state = CardState()
    
    let modelContext: ModelContext
    
    private let defaults = UserDefaults.standard
    
    private var storedDisplayCurrency: String {
        get { defaults.string(forKey: "card_display_currency") ?? "RUB" }
        set { defaults.set(newValue, forKey: "card_display_currency") }
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        state.displayCurrency = storedDisplayCurrency
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
            
        case .showBankFilterSheet:
            state.showBankFilterSheet = true
            
        case .hideBankFilterSheet:
            state.showBankFilterSheet = false
            
        case .showCardTypeFilterSheet:
            state.showCardTypeFilterSheet = true
            
        case .hideCardTypeFilterSheet:
            state.showCardTypeFilterSheet = false
            
        case .showCurrencyFilterSheet:
            state.showCurrencyFilterSheet = true
            
        case .hideCurrencyFilterSheet:
            state.showCurrencyFilterSheet = false
            
        case .showDisplayCurrencySheet:
            state.showDisplayCurrencySheet = true
            
        case .hideDisplayCurrencySheet:
            state.showDisplayCurrencySheet = false
            
        case .setDisplayCurrency(let currency):
            state.displayCurrency = currency
            storedDisplayCurrency = currency
            calculateStats()
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCards() {
        let descriptor = FetchDescriptor<Card>()
        if let cards = try? modelContext.fetch(descriptor) {
            // Сортируем: сначала избранные, потом по приоритету, потом по дате обновления
            state.cards = cards.sorted { card1, card2 in
                // Сначала избранные
                if card1.isFavorite != card2.isFavorite {
                    return card1.isFavorite
                }
                // Затем по приоритету (высокий > обычный > низкий)
                if card1.priority.sortOrder != card2.priority.sortOrder {
                    return card1.priority.sortOrder < card2.priority.sortOrder
                }
                // Затем по дате обновления (новые выше)
                return card1.updatedAt > card2.updatedAt
            }
            applyFilters()
            calculateStats()
            
            // Обновляем CardManager
            CardManager.shared.setup(modelContext: modelContext)
        }
    }
    
    private func applyFilters() {
        let filtered = state.cards
        
        // Показываем все карты без фильтрации
        state.filteredCards = filtered
    }
    
    private func calculateStats() {
        // Сначала считаем балансы по валютам (оригинальные значения)
        // Для дебетовых карт добавляем баланс, для кредитных вычитаем долг
        var balanceByCurrency: [String: Double] = [:]
        for card in state.cards {
            if card.cardType == .credit {
                // Для кредитных карт вычитаем долг из общего баланса
                balanceByCurrency[card.currency, default: 0] -= card.debt
            } else {
                // Для дебетовых карт добавляем баланс
                balanceByCurrency[card.currency, default: 0] += card.balance
            }
        }
        state.balanceByCurrency = balanceByCurrency
        
        // Затем конвертируем общий баланс в выбранную валюту
        Task {
            await calculateTotalBalance()
        }
    }
    
    private func calculateTotalBalance() async {
        let displayCurrency = state.displayCurrency
        var total: Double = 0.0
        
        for (currency, amount) in state.balanceByCurrency {
            if currency == displayCurrency {
                total += amount
            } else {
                // Конвертируем через CurrencyRateService
                if let converted = await CurrencyRateService.shared.convert(
                    amount: amount,
                    from: currency,
                    to: displayCurrency
                ) {
                    total += converted
                } else {
                    // Если курс недоступен, просто суммируем (fallback)
                    total += amount
                }
            }
        }
        
        state.totalBalance = total
    }
    
    func refreshRates() async {
        state.isLoadingRates = true
        defer { state.isLoadingRates = false }
        
        // Просто вызываем refreshRates у сервиса, чтобы обновить кэш
        // Затем пересчитываем баланс
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        await calculateTotalBalance()
    }
    
    private func deleteCard(_ card: Card) {
        modelContext.delete(card)
        
        do {
            try modelContext.save()
            loadCards()
            EventBus.shared.publish(FinanceEvent.cardsUpdated)
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
            EventBus.shared.publish(FinanceEvent.cardsUpdated)
        } catch {
            AppLogger.log(.error, category: "Card", "Failed to toggle favorite: \(error.localizedDescription)")
        }
    }
    
    private func updateCard(_ card: Card) {
        if let existing = state.editingCard {
            // Сохраняем старые значения для корректировки
            let oldBalance = existing.balance
            let newCardType = card.cardType
            let balanceChanged = abs(card.balance - oldBalance) > 0.01

            if existing.uniqueID.isEmpty {
                _ = existing.cardUniqueID
            }
            if !existing.hasInitialBalance {
                existing.initialBalance = existing.balance
                existing.hasInitialBalance = true
            }
            // Обновляем существующую карту
            existing.name = card.name
            existing.cardNumber = card.cardNumber
            existing.bank = card.bank
            existing.cardType = card.cardType
            existing.priority = card.priority
            existing.currency = card.currency
            existing.balance = card.balance
            existing.creditLimit = card.creditLimit
            existing.expiryDate = card.expiryDate
            existing.cardholderName = card.cardholderName
            existing.cardColor = card.cardColor
            existing.isFavorite = card.isFavorite
            existing.includeInTotal = card.includeInTotal
            existing.updatedAt = Date()

            // Корректировка баланса через форму редактирования = транзакция
            if balanceChanged {
                let balanceDelta = card.balance - oldBalance
                let transactionType: CashflowTransactionType
                let transactionAmount: Double
                let transactionNote: String

                if newCardType == .credit {
                    transactionType = .creditDebtAdjustment
                    transactionAmount = balanceDelta
                    transactionNote = "Редактирование задолженности кредитной карты"
                } else {
                    transactionType = .cardBalanceAdjustment
                    transactionAmount = balanceDelta
                    transactionNote = "Редактирование баланса карты"
                }

                let transaction = CashflowTransaction(
                    transactionType: transactionType,
                    amount: transactionAmount,
                    currency: existing.currency,
                    transactionDate: Date(),
                    cardID: existing.cardUniqueID,
                    note: transactionNote
                )
                modelContext.insert(transaction)
            }
        } else {
            // Создаем новую карту
            let newCard = Card(
                name: card.name,
                cardNumber: card.cardNumber,
                bank: card.bank,
                cardType: card.cardType,
                priority: card.priority,
                currency: card.currency,
                balance: card.balance,
                creditLimit: card.creditLimit,
                expiryDate: card.expiryDate,
                cardholderName: card.cardholderName,
                cardColor: card.cardColor,
                isFavorite: card.isFavorite,
                includeInTotal: card.includeInTotal
            )
            modelContext.insert(newCard)
        }
        
        do {
            try modelContext.save()
            loadCards()
            state.showCardEditor = false
            state.editingCard = nil
            EventBus.shared.publish(FinanceEvent.cardsUpdated)
        } catch {
            AppLogger.log(.error, category: "Card", "Failed to save card: \(error.localizedDescription)")
        }
    }
}
