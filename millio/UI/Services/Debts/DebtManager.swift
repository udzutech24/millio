//
//  DebtManager.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Глобальный менеджер для доступа к долгам из других сервисов
@MainActor
final class DebtManager {
    static let shared = DebtManager()
    
    private var modelContext: ModelContext?
    
    private init() {}
    
    /// Инициализация с ModelContext
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Получить все долги
    func getAllDebts() -> [Debt] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Debt>()
        let debts = (try? modelContext.fetch(descriptor)) ?? []
        
        return debts.sorted { debt1, debt2 in
            if debt1.isFavorite != debt2.isFavorite {
                return debt1.isFavorite
            }
            if debt1.priority.sortOrder != debt2.priority.sortOrder {
                return debt1.priority.sortOrder < debt2.priority.sortOrder
            }
            return debt1.updatedAt > debt2.updatedAt
        }
    }
    
    /// Получить долги по типу
    func getDebts(by type: DebtType) -> [Debt] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Debt>(
            predicate: #Predicate<Debt> { $0.debtTypeRaw == type.rawValue }
        )
        let debts = (try? modelContext.fetch(descriptor)) ?? []
        
        return debts.sorted { debt1, debt2 in
            if debt1.isFavorite != debt2.isFavorite {
                return debt1.isFavorite
            }
            if debt1.priority.sortOrder != debt2.priority.sortOrder {
                return debt1.priority.sortOrder < debt2.priority.sortOrder
            }
            return debt1.updatedAt > debt2.updatedAt
        }
    }
    
    /// Получить избранные долги
    func getFavoriteDebts() -> [Debt] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Debt>(
            predicate: #Predicate<Debt> { $0.isFavorite == true }
        )
        let debts = (try? modelContext.fetch(descriptor)) ?? []
        
        return debts.sorted { debt1, debt2 in
            if debt1.priority.sortOrder != debt2.priority.sortOrder {
                return debt1.priority.sortOrder < debt2.priority.sortOrder
            }
            return debt1.updatedAt > debt2.updatedAt
        }
    }
    
    /// Получить просроченные долги
    func getOverdueDebts() -> [Debt] {
        getAllDebts().filter { $0.isOverdue }
    }
    
    /// Общая сумма долгов мне
    func getTotalOwedToMe() -> Double {
        getDebts(by: .owedToMe).reduce(0) { $0 + $1.amount }
    }
    
    /// Общая сумма моих долгов
    func getTotalIOwe() -> Double {
        getDebts(by: .iOwe).reduce(0) { $0 + $1.amount }
    }
    
    /// Общая сумма долгов мне в указанной валюте (с конвертацией)
    func getTotalOwedToMe(currency: String) -> Double {
        // Будет использоваться CurrencyRateService для конвертации
        getDebts(by: .owedToMe).reduce(0) { $0 + $1.amount }
    }
    
    /// Общая сумма моих долгов в указанной валюте (с конвертацией)
    func getTotalIOwe(currency: String) -> Double {
        // Будет использоваться CurrencyRateService для конвертации
        getDebts(by: .iOwe).reduce(0) { $0 + $1.amount }
    }
}
