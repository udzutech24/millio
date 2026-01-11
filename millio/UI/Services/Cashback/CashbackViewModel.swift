//
//  CashbackViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Cashback State

struct CashbackState {
    /// Все кешбэки
    var cashbacks: [Cashback] = []
    
    /// Показывать ли экран добавления/редактирования
    var showCashbackEditor: Bool = false
    
    /// Редактируемый кешбэк (nil = новый)
    var editingCashback: Cashback? = nil
    
    /// Показывать ли экран выбора карты
    var showCardPicker: Bool = false
    
    /// Все доступные карты
    var availableCards: [Card] = []
    
}

// MARK: - Cashback Actions

enum CashbackAction {
    case loadCashbacks
    case loadCards
    case addCashback
    case editCashback(Cashback)
    case deleteCashback(Cashback)
    case updateCashback(category: CashbackCategory, percentage: Double, cardIDs: [String])
    case updateCashbacksForCard(cardID: String, cashbacks: [(category: CashbackCategory, percentage: Double)])
    case showCashbackEditor
    case hideCashbackEditor
    case showCardPicker
    case hideCardPicker
}

// MARK: - Cashback ViewModel

@MainActor
final class CashbackViewModel: ViewModelProtocol {
    @Published var state = CashbackState()
    
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Инициализируем CardManager
        CardManager.shared.setup(modelContext: modelContext)
        // Сначала загружаем карты, потом кешбэки, чтобы правильно проверить связи
        loadCards()
        loadCashbacks()
        
        // Логирование для отладки
        AppLogger.log(.info, category: "Cashback", "Loaded \(state.availableCards.count) cards, \(state.cashbacks.count) cashbacks")
        for cashback in state.cashbacks {
            AppLogger.log(.info, category: "Cashback", "Cashback '\(cashback.category.displayName)' has \(cashback.cardIDs.count) cardIDs")
            for cardID in cashback.cardIDs {
                let cardExists = state.availableCards.contains { $0.cardUniqueID == cardID }
                AppLogger.log(.info, category: "Cashback", "  CardID '\(cardID)' exists: \(cardExists)")
            }
        }
        
        // Автоматически проверяем и очищаем невалидные связи при первом запуске
        cleanInvalidCardIDs(in: state.cashbacks)
        
        // НЕ вызываем cleanInvalidCardIDs здесь - это может удалить валидные связи
        // Очистка будет происходить только при реальном удалении карт в loadCards()
    }
    
    func handle(_ action: CashbackAction) {
        switch action {
        case .loadCashbacks:
            loadCashbacks()
            
        case .loadCards:
            loadCards()
            
        case .addCashback:
            state.editingCashback = nil
            state.showCashbackEditor = true
            
        case .editCashback(let cashback):
            state.editingCashback = cashback
            state.showCashbackEditor = true
            
        case .deleteCashback(let cashback):
            deleteCashback(cashback)
            
        case .updateCashback(let category, let percentage, let cardIDs):
            updateCashback(category: category, percentage: percentage, cardIDs: cardIDs)
            
        case .updateCashbacksForCard(let cardID, let cashbacks):
            updateCashbacksForCard(cardID: cardID, cashbacks: cashbacks)
            
        case .showCashbackEditor:
            state.showCashbackEditor = true
            
        case .hideCashbackEditor:
            state.showCashbackEditor = false
            state.editingCashback = nil
            
        case .showCardPicker:
            loadCards() // Обновляем список перед показом
            state.showCardPicker = true
            
        case .hideCardPicker:
            state.showCardPicker = false
            
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCashbacks() {
        let descriptor = FetchDescriptor<Cashback>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let cashbacks = try? modelContext.fetch(descriptor) {
            state.cashbacks = cashbacks
            applyFilters()
        }
    }
    
    /// Очищает несуществующие cardIDs из кешбэков
    private func cleanInvalidCardIDs(in cashbacks: [Cashback]) {
        // Создаем маппинг cardUniqueID -> Card для стабильной идентификации
        let cardUniqueIDMap: [String: Card] = Dictionary(uniqueKeysWithValues: state.availableCards.map { card in
            (card.cardUniqueID, card)
        })
        
        // Также создаем маппинг старых persistentModelID -> cardUniqueID для миграции
        var oldIDToUniqueID: [String: String] = [:]
        for card in state.availableCards {
            let oldID = String(describing: card.persistentModelID)
            oldIDToUniqueID[oldID] = card.cardUniqueID
        }
        
        AppLogger.log(.info, category: "Cashback", "Available \(state.availableCards.count) cards with unique IDs")
        
        var hasChanges = false
        
        for cashback in cashbacks {
            let originalCount = cashback.cardIDs.count
            let validCardIDs = cashback.cardIDs.compactMap { cardIDString -> String? in
                // Если это уже cardUniqueID, проверяем напрямую
                if let card = cardUniqueIDMap[cardIDString] {
                    return card.cardUniqueID
                }
                
                // Если это старый формат (persistentModelID), конвертируем в cardUniqueID
                if let uniqueID = oldIDToUniqueID[cardIDString] {
                    AppLogger.log(.info, category: "Cashback", "Migrating old cardID '\(cardIDString.prefix(50))...' to uniqueID '\(uniqueID)'")
                    return uniqueID
                }
                
                // Пробуем найти по прямому сравнению (на случай если формат немного отличается)
                if let card = state.availableCards.first(where: { String(describing: $0.persistentModelID) == cardIDString }) {
                    AppLogger.log(.info, category: "Cashback", "Found card by direct comparison, using uniqueID")
                    return card.cardUniqueID
                }
                
                AppLogger.log(.info, category: "Cashback", "Invalid cardID '\(cardIDString.prefix(50))...' in cashback '\(cashback.category.displayName)'")
                return nil
            }
            
            if validCardIDs.count != originalCount || validCardIDs != cashback.cardIDs {
                AppLogger.log(.info, category: "Cashback", "Updating cardIDs for cashback '\(cashback.category.displayName)'. Original count: \(originalCount), Valid count: \(validCardIDs.count)")
                cashback.cardIDs = validCardIDs
                cashback.updatedAt = Date()
                hasChanges = true
            }
        }
        
        if hasChanges {
            do {
                try modelContext.save()
                AppLogger.log(.info, category: "Cashback", "Cleaned invalid card IDs and saved")
            } catch {
                AppLogger.log(.error, category: "Cashback", "Failed to clean invalid card IDs: \(error.localizedDescription)")
            }
        } else {
            AppLogger.log(.info, category: "Cashback", "No invalid card IDs found")
        }
    }
    
    private func loadCards() {
        let oldCardIDs = Set(state.availableCards.map { String(describing: $0.persistentModelID) })
        state.availableCards = CardManager.shared.getAllCards()
        let newCardIDs = Set(state.availableCards.map { String(describing: $0.persistentModelID) })
        
        // Очищаем несуществующие cardIDs если:
        // 1. Карты действительно удалены (список уменьшился)
        // 2. Или это первый запуск и нужно проверить все связи
        let cardsWereDeleted = !oldCardIDs.isEmpty && oldCardIDs != newCardIDs && newCardIDs.isSubset(of: oldCardIDs)
        let isFirstLoad = oldCardIDs.isEmpty && !newCardIDs.isEmpty && !state.cashbacks.isEmpty
        
        if (cardsWereDeleted || isFirstLoad) && !state.cashbacks.isEmpty {
            // Карты были удалены или это первый запуск - очищаем несуществующие ссылки
            cleanInvalidCardIDs(in: state.cashbacks)
            // Обновляем список кешбэков после очистки
            let descriptor = FetchDescriptor<Cashback>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            if let cashbacks = try? modelContext.fetch(descriptor) {
                state.cashbacks = cashbacks
                applyFilters()
            }
        }
    }
    
    private func applyFilters() {
        // Фильтрация по поисковому запросу будет в View
        // Здесь можно добавить дополнительную логику фильтрации
    }
    
    private func deleteCashback(_ cashback: Cashback) {
        modelContext.delete(cashback)
        
        do {
            try modelContext.save()
            loadCashbacks()
        } catch {
            AppLogger.log(.error, category: "Cashback", "Failed to delete cashback: \(error.localizedDescription)")
        }
    }
    
    private func updateCashback(category: CashbackCategory, percentage: Double, cardIDs: [String]) {
        // Фильтруем только существующие карты перед сохранением
        // Используем cardUniqueID для стабильной идентификации
        let availableUniqueIDs = Set(state.availableCards.map { $0.cardUniqueID })
        let validCardIDs = cardIDs.compactMap { cardIDString -> String? in
            // Если это уже uniqueID, проверяем напрямую
            if availableUniqueIDs.contains(cardIDString) {
                return cardIDString
            }
            // Если это старый формат (persistentModelID), конвертируем
            if let card = state.availableCards.first(where: { String(describing: $0.persistentModelID) == cardIDString }) {
                return card.cardUniqueID
            }
            return nil
        }
        
        if let existing = state.editingCashback {
            // Обновляем существующий кешбэк
            existing.category = category
            existing.percentage = percentage
            existing.cardIDs = validCardIDs
            existing.updatedAt = Date()
        } else {
            // Создаем новый кешбэк (name будет пустым, используется только категория)
            let newCashback = Cashback(
                name: "",
                category: category,
                percentage: percentage,
                cardIDs: validCardIDs
            )
            modelContext.insert(newCashback)
        }
        
        do {
            try modelContext.save()
            loadCashbacks()
            state.showCashbackEditor = false
            state.editingCashback = nil
        } catch {
            AppLogger.log(.error, category: "Cashback", "Failed to save cashback: \(error.localizedDescription)")
        }
    }
    
    /// Получить карту по ID
    func getCard(byID cardID: String?) -> Card? {
        guard let cardID = cardID else { return nil }
        // Ищем карту по cardUniqueID (новый формат) или persistentModelID (старый формат)
        return state.availableCards.first { card in
            card.cardUniqueID == cardID || String(describing: card.persistentModelID) == cardID
        }
    }
    
    /// Получить карты, которые можно использовать для получения кешбэка
    func getCardsForCashback(_ cashback: Cashback) -> [Card] {
        // Всегда показываем только привязанные карты (если они есть)
        // Фильтруем несуществующие карты
        return cashback.cardIDs.compactMap { cardID in
            getCard(byID: cardID)
        }
    }
    
    private func updateCashbacksForCard(cardID: String, cashbacks: [(category: CashbackCategory, percentage: Double)]) {
        // Фильтруем только валидные кэшбеки (с процентом > 0)
        let validCashbacks = cashbacks.filter { $0.percentage > 0 }
        
        guard !validCashbacks.isEmpty else { return }
        
        // Проверяем, что карта существует
        guard let card = getCard(byID: cardID) else { return }
        let validCardID = card.cardUniqueID
        
        // Создаем кэшбеки для выбранной карты
        for (category, percentage) in validCashbacks {
            // Проверяем, не существует ли уже такой кэшбек для этой карты
            let existingCashback = state.cashbacks.first { cashback in
                cashback.category == category && cashback.cardIDs.contains(validCardID)
            }
            
            if let existing = existingCashback {
                // Обновляем существующий кэшбэк, добавляя карту если её нет
                if !existing.cardIDs.contains(validCardID) {
                    existing.cardIDs.append(validCardID)
                }
                existing.percentage = percentage
                existing.updatedAt = Date()
            } else {
                // Создаем новый кэшбэк
                let newCashback = Cashback(
                    name: "",
                    category: category,
                    percentage: percentage,
                    cardIDs: [validCardID]
                )
                modelContext.insert(newCashback)
            }
        }
        
        do {
            try modelContext.save()
            loadCashbacks()
            state.showCashbackEditor = false
            state.editingCashback = nil
        } catch {
            AppLogger.log(.error, category: "Cashback", "Failed to save cashbacks: \(error.localizedDescription)")
        }
    }
}
