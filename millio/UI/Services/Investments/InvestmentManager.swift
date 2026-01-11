//
//  InvestmentManager.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Глобальный менеджер для доступа к инвестициям из других сервисов
@MainActor
final class InvestmentManager {
    static let shared = InvestmentManager()
    
    private var modelContext: ModelContext?
    
    private init() {}
    
    /// Инициализация с ModelContext
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Получить все инвестиции
    func getAllInvestments() -> [Investment] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Investment>()
        let investments = (try? modelContext.fetch(descriptor)) ?? []
        
        return investments.sorted { inv1, inv2 in
            if inv1.isFavorite != inv2.isFavorite {
                return inv1.isFavorite
            }
            if inv1.priority.sortOrder != inv2.priority.sortOrder {
                return inv1.priority.sortOrder < inv2.priority.sortOrder
            }
            return inv1.updatedAt > inv2.updatedAt
        }
    }
    
    /// Получить инвестиции по типу
    func getInvestments(by type: InvestmentType) -> [Investment] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Investment>(
            predicate: #Predicate<Investment> { $0.investmentTypeRaw == type.rawValue }
        )
        let investments = (try? modelContext.fetch(descriptor)) ?? []
        
        return investments.sorted { inv1, inv2 in
            if inv1.isFavorite != inv2.isFavorite {
                return inv1.isFavorite
            }
            if inv1.priority.sortOrder != inv2.priority.sortOrder {
                return inv1.priority.sortOrder < inv2.priority.sortOrder
            }
            return inv1.updatedAt > inv2.updatedAt
        }
    }
    
    /// Получить инвестиции по категории
    func getInvestments(by category: InvestmentCategory) -> [Investment] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Investment>(
            predicate: #Predicate<Investment> { $0.categoryRaw == category.rawValue }
        )
        let investments = (try? modelContext.fetch(descriptor)) ?? []
        
        return investments.sorted { inv1, inv2 in
            if inv1.isFavorite != inv2.isFavorite {
                return inv1.isFavorite
            }
            if inv1.priority.sortOrder != inv2.priority.sortOrder {
                return inv1.priority.sortOrder < inv2.priority.sortOrder
            }
            return inv1.updatedAt > inv2.updatedAt
        }
    }
    
    /// Получить инвестиции, учитываемые в общих финансах
    func getInvestmentsIncludedInTotal() -> [Investment] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Investment>(
            predicate: #Predicate<Investment> { $0.includeInTotal == true }
        )
        let investments = (try? modelContext.fetch(descriptor)) ?? []
        
        return investments.sorted { inv1, inv2 in
            if inv1.isFavorite != inv2.isFavorite {
                return inv1.isFavorite
            }
            if inv1.priority.sortOrder != inv2.priority.sortOrder {
                return inv1.priority.sortOrder < inv2.priority.sortOrder
            }
            return inv1.updatedAt > inv2.updatedAt
        }
    }
    
    /// Получить избранные инвестиции
    func getFavoriteInvestments() -> [Investment] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Investment>(
            predicate: #Predicate<Investment> { $0.isFavorite == true }
        )
        let investments = (try? modelContext.fetch(descriptor)) ?? []
        
        return investments.sorted { inv1, inv2 in
            if inv1.priority.sortOrder != inv2.priority.sortOrder {
                return inv1.priority.sortOrder < inv2.priority.sortOrder
            }
            return inv1.updatedAt > inv2.updatedAt
        }
    }
    
    /// Общая стоимость плюсовых инвестиций
    func getTotalPositiveInvestments() -> Double {
        getInvestments(by: .positive).reduce(0) { $0 + $1.amount }
    }
    
    /// Общая стоимость минусовых инвестиций
    func getTotalNegativeInvestments() -> Double {
        getInvestments(by: .negative).reduce(0) { $0 + $1.amount }
    }
    
    /// Общая стоимость инвестиций, учитываемых в общих финансах
    func getTotalInvestmentsIncluded() -> Double {
        getInvestmentsIncludedInTotal().reduce(0) { total, investment in
            let amount = investment.amount
            // Плюсовые добавляем, минусовые вычитаем
            return total + (investment.investmentType == .positive ? amount : -amount)
        }
    }
}
