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
    
    /// Текст поиска
    var searchText: String = ""
}

// MARK: - Cashback Actions

enum CashbackAction {
    case loadCashbacks
    case loadCards
    case addCashback
    case editCashback(Cashback)
    case deleteCashback(Cashback)
    case updateCashback(name: String, category: CashbackCategory, percentage: Double, cardIDs: [String])
    case showCashbackEditor
    case hideCashbackEditor
    case showCardPicker
    case hideCardPicker
    case search(String)
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
        loadCashbacks()
        loadCards()
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
            
        case .updateCashback(let name, let category, let percentage, let cardIDs):
            updateCashback(name: name, category: category, percentage: percentage, cardIDs: cardIDs)
            
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
            
        case .search(let text):
            state.searchText = text
            applyFilters()
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
    
    private func loadCards() {
        state.availableCards = CardManager.shared.getAllCards()
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
    
    private func updateCashback(name: String, category: CashbackCategory, percentage: Double, cardIDs: [String]) {
        if let existing = state.editingCashback {
            // Обновляем существующий кешбэк
            existing.name = name
            existing.category = category
            existing.percentage = percentage
            existing.cardIDs = cardIDs
            existing.updatedAt = Date()
        } else {
            // Создаем новый кешбэк
            let newCashback = Cashback(
                name: name,
                category: category,
                percentage: percentage,
                cardIDs: cardIDs
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
        // Ищем карту по persistentModelID
        return state.availableCards.first { card in
            let cardIDString = String(describing: card.persistentModelID)
            return cardIDString == cardID
        }
    }
    
    /// Получить карты, которые можно использовать для получения кешбэка
    func getCardsForCashback(_ cashback: Cashback) -> [Card] {
        // Если у кешбэка привязаны карты, показываем только их
        if !cashback.cardIDs.isEmpty {
            return cashback.cardIDs.compactMap { cardID in
                getCard(byID: cardID)
            }
        }
        // Иначе показываем все доступные карты
        return state.availableCards
    }
}
