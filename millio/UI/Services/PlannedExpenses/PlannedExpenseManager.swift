//
//  PlannedExpenseManager.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData

/// Менеджер для глобального доступа к планируемым расходам
@MainActor
final class PlannedExpenseManager {
    static let shared = PlannedExpenseManager()
    
    private init() {}
    
    /// Получить все планируемые расходы
    func getAllExpenses(modelContext: ModelContext) -> [PlannedExpense] {
        let descriptor = FetchDescriptor<PlannedExpense>(
            sortBy: [SortDescriptor(\.plannedDate, order: .forward)]
        )
        let expenses = (try? modelContext.fetch(descriptor)) ?? []
        return expenses.sorted { expense1, expense2 in
            if expense1.isFavorite != expense2.isFavorite {
                return expense1.isFavorite
            }
            if expense1.priority.sortOrder != expense2.priority.sortOrder {
                return expense1.priority.sortOrder < expense2.priority.sortOrder
            }
            return expense1.plannedDate < expense2.plannedDate
        }
    }
    
    /// Получить неоплаченные расходы
    func getUnpaidExpenses(modelContext: ModelContext) -> [PlannedExpense] {
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                !expense.isPaid
            },
            sortBy: [SortDescriptor(\.plannedDate, order: .forward)]
        )
        let expenses = (try? modelContext.fetch(descriptor)) ?? []
        return expenses.sorted { expense1, expense2 in
            if expense1.isFavorite != expense2.isFavorite {
                return expense1.isFavorite
            }
            if expense1.priority.sortOrder != expense2.priority.sortOrder {
                return expense1.priority.sortOrder < expense2.priority.sortOrder
            }
            return expense1.plannedDate < expense2.plannedDate
        }
    }
    
    /// Получить оплаченные расходы
    func getPaidExpenses(modelContext: ModelContext) -> [PlannedExpense] {
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.isPaid
            },
            sortBy: [
                SortDescriptor(\.plannedDate, order: .reverse)
            ]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    /// Получить просроченные расходы
    func getOverdueExpenses(modelContext: ModelContext) -> [PlannedExpense] {
        let now = Date()
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                !expense.isPaid && expense.plannedDate < now
            },
            sortBy: [SortDescriptor(\.plannedDate, order: .forward)]
        )
        let expenses = (try? modelContext.fetch(descriptor)) ?? []
        return expenses.sorted { expense1, expense2 in
            if expense1.priority.sortOrder != expense2.priority.sortOrder {
                return expense1.priority.sortOrder < expense2.priority.sortOrder
            }
            return expense1.plannedDate < expense2.plannedDate
        }
    }
    
    /// Получить расходы по категории
    func getExpenses(by category: PlannedExpenseCategory, modelContext: ModelContext) -> [PlannedExpense] {
        let categoryRaw = category.rawValue
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.categoryRaw == categoryRaw
            },
            sortBy: [SortDescriptor(\.plannedDate, order: .forward)]
        )
        let expenses = (try? modelContext.fetch(descriptor)) ?? []
        return expenses.sorted { expense1, expense2 in
            if expense1.isFavorite != expense2.isFavorite {
                return expense1.isFavorite
            }
            if expense1.priority.sortOrder != expense2.priority.sortOrder {
                return expense1.priority.sortOrder < expense2.priority.sortOrder
            }
            return expense1.plannedDate < expense2.plannedDate
        }
    }
    
    /// Получить избранные расходы
    func getFavoriteExpenses(modelContext: ModelContext) -> [PlannedExpense] {
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.isFavorite
            },
            sortBy: [SortDescriptor(\.plannedDate, order: .forward)]
        )
        let expenses = (try? modelContext.fetch(descriptor)) ?? []
        return expenses.sorted { expense1, expense2 in
            if expense1.priority.sortOrder != expense2.priority.sortOrder {
                return expense1.priority.sortOrder < expense2.priority.sortOrder
            }
            return expense1.plannedDate < expense2.plannedDate
        }
    }
    
    /// Получить расходы на определенный период
    func getExpenses(from startDate: Date, to endDate: Date, modelContext: ModelContext) -> [PlannedExpense] {
        let startTimestamp = startDate.timeIntervalSince1970
        let endTimestamp = endDate.timeIntervalSince1970
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.plannedDate.timeIntervalSince1970 >= startTimestamp &&
                expense.plannedDate.timeIntervalSince1970 <= endTimestamp
            },
            sortBy: [SortDescriptor(\.plannedDate, order: .forward)]
        )
        let expenses = (try? modelContext.fetch(descriptor)) ?? []
        return expenses.sorted { expense1, expense2 in
            if expense1.isFavorite != expense2.isFavorite {
                return expense1.isFavorite
            }
            if expense1.priority.sortOrder != expense2.priority.sortOrder {
                return expense1.priority.sortOrder < expense2.priority.sortOrder
            }
            return expense1.plannedDate < expense2.plannedDate
        }
    }
    
    /// Подсчитать общую сумму неоплаченных расходов (с конвертацией валют)
    func calculateTotalUnpaidAmount(in currency: String, modelContext: ModelContext) async -> Double {
        let expenses = getUnpaidExpenses(modelContext: modelContext)
        guard !expenses.isEmpty else { return 0.0 }
        
        var total: Double = 0.0
        
        for expense in expenses {
            if expense.currency == currency {
                total += expense.amount
            } else {
                // Конвертируем через CurrencyRateService
                if let converted = await CurrencyRateService.shared.convert(
                    amount: expense.amount,
                    from: expense.currency,
                    to: currency
                ) {
                    total += converted
                } else {
                    // Если конвертация не удалась, просто добавляем исходную сумму
                    total += expense.amount
                }
            }
        }
        
        return total
    }
}
