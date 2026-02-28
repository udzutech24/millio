//
//  CreditManager.swift
//  millio
//
//  Created by Александр Сидоркин on 11.01.2026.
//

import Foundation
import SwiftData

/// Глобальный менеджер для доступа к кредитам из других сервисов
@MainActor
final class CreditManager {
    static let shared = CreditManager()
    
    private var modelContext: ModelContext?
    
    private init() {}
    
    /// Инициализация с ModelContext
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    /// Получить все кредиты
    func getAllCredits() -> [Credit] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Credit>()
        let credits = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.archivedAt == nil }
        
        return credits.sorted { credit1, credit2 in
            if credit1.isFavorite != credit2.isFavorite {
                return credit1.isFavorite
            }
            return credit1.updatedAt > credit2.updatedAt
        }
    }
    
    /// Получить избранные кредиты
    func getFavoriteCredits() -> [Credit] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Credit>(
            predicate: #Predicate<Credit> { $0.isFavorite == true }
        )
        let credits = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.archivedAt == nil }
        
        return credits.sorted { $0.updatedAt > $1.updatedAt }
    }
    
    /// Получить кредиты по валюте
    func getCredits(by currency: String) -> [Credit] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Credit>(
            predicate: #Predicate<Credit> { $0.currency == currency }
        )
        let credits = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.archivedAt == nil }
        
        return credits.sorted { credit1, credit2 in
            if credit1.isFavorite != credit2.isFavorite {
                return credit1.isFavorite
            }
            return credit1.updatedAt > credit2.updatedAt
        }
    }
    
    /// Получить кредиты по банку
    func getCredits(by bank: Bank) -> [Credit] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Credit>(
            predicate: #Predicate<Credit> { $0.bankRaw == bank.rawValue }
        )
        let credits = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.archivedAt == nil }
        
        return credits.sorted { credit1, credit2 in
            if credit1.isFavorite != credit2.isFavorite {
                return credit1.isFavorite
            }
            return credit1.updatedAt > credit2.updatedAt
        }
    }
    
    /// Получить кредиты по типу
    func getCredits(by type: CreditType) -> [Credit] {
        guard let modelContext = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<Credit>(
            predicate: #Predicate<Credit> { $0.creditTypeRaw == type.rawValue }
        )
        let credits = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.archivedAt == nil }
        
        return credits.sorted { credit1, credit2 in
            if credit1.isFavorite != credit2.isFavorite {
                return credit1.isFavorite
            }
            return credit1.updatedAt > credit2.updatedAt
        }
    }
    
    /// Получить кредит по ID
    func getCredit(id: PersistentIdentifier) -> Credit? {
        guard let modelContext = modelContext else { return nil }
        return modelContext.model(for: id) as? Credit
    }
    
    /// Общая сумма всех кредитов (остаток долга)
    func getTotalDebt() -> Double {
        getAllCredits().reduce(0) { $0 + $1.remainingAmount }
    }
    
    /// Общая сумма долга по валюте
    func getTotalDebt(currency: String) -> Double {
        getCredits(by: currency).reduce(0) { $0 + $1.remainingAmount }
    }
    
    /// Общая сумма ежемесячных платежей
    func getTotalMonthlyPayments() -> Double {
        getAllCredits().reduce(0) { $0 + $1.monthlyPayment }
    }
    
    /// Общая сумма ежемесячных платежей по валюте
    func getTotalMonthlyPayments(currency: String) -> Double {
        getCredits(by: currency).reduce(0) { $0 + $1.monthlyPayment }
    }
}
