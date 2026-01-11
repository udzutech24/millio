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
    /// Выбранная карта для кешбэка
    var selectedCard: Card? = nil
    
    /// Показывать ли экран выбора карты
    var showCardPicker: Bool = false
    
    /// Все доступные карты
    var availableCards: [Card] = []
}

// MARK: - Cashback Actions

enum CashbackAction {
    case loadCards
    case selectCard(Card?)
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
        loadCards()
    }
    
    func handle(_ action: CashbackAction) {
        switch action {
        case .loadCards:
            loadCards()
            
        case .selectCard(let card):
            state.selectedCard = card
            state.showCardPicker = false
            
        case .showCardPicker:
            loadCards() // Обновляем список перед показом
            state.showCardPicker = true
            
        case .hideCardPicker:
            state.showCardPicker = false
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCards() {
        state.availableCards = CardManager.shared.getAllCards()
    }
}
