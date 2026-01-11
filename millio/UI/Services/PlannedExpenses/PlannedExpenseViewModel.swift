//
//  PlannedExpenseViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - PlannedExpense State

struct PlannedExpenseState {
    /// Все планируемые расходы
    var expenses: [PlannedExpense] = []
    
    /// Отфильтрованные расходы
    var filteredExpenses: [PlannedExpense] = []
    
    /// Показывать ли экран добавления/редактирования
    var showExpenseEditor: Bool = false
    
    /// Редактируемый расход (nil = новый расход)
    var editingExpense: PlannedExpense? = nil
    
    /// Показывать ли sheet выбора валюты для отображения
    var showDisplayCurrencySheet: Bool = false
    
    /// Валюта для отображения
    var displayCurrency: String = "RUB"
    
    /// Общая сумма неоплаченных расходов (в выбранной валюте)
    var totalUnpaid: Double = 0.0
    
    /// Количество просроченных расходов
    var overdueCount: Int = 0
    
    /// Флаг загрузки курсов
    var isLoadingRates: Bool = false
}

// MARK: - PlannedExpense Actions

enum PlannedExpenseAction {
    case loadExpenses
    case addExpense
    case editExpense(PlannedExpense)
    case deleteExpense(PlannedExpense)
    case toggleFavorite(PlannedExpense)
    case togglePaid(PlannedExpense)
    case updateExpense(
        name: String,
        amount: Double,
        currency: String,
        plannedDate: Date,
        category: PlannedExpenseCategory,
        priority: PlannedExpensePriority,
        isFavorite: Bool
    )
    case showExpenseEditor
    case hideExpenseEditor
    case showDisplayCurrencySheet
    case hideDisplayCurrencySheet
    case setDisplayCurrency(String)
}

// MARK: - PlannedExpense ViewModel

@MainActor
final class PlannedExpenseViewModel: ViewModelProtocol {
    @Published var state = PlannedExpenseState()
    
    let modelContext: ModelContext
    
    private let defaults = UserDefaults.standard
    
    private var storedDisplayCurrency: String {
        get { defaults.string(forKey: "planned_expense_display_currency") ?? "RUB" }
        set { defaults.set(newValue, forKey: "planned_expense_display_currency") }
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        state.displayCurrency = storedDisplayCurrency
        loadExpenses()
    }
    
    func handle(_ action: PlannedExpenseAction) {
        switch action {
        case .loadExpenses:
            loadExpenses()
            
        case .addExpense:
            state.editingExpense = nil
            state.showExpenseEditor = true
            
        case .editExpense(let expense):
            state.editingExpense = expense
            state.showExpenseEditor = true
            
        case .deleteExpense(let expense):
            deleteExpense(expense)
            
        case .toggleFavorite(let expense):
            toggleFavorite(expense)
            
        case .togglePaid(let expense):
            togglePaid(expense)
            
        case .updateExpense(let name, let amount, let currency, let plannedDate, let category, let priority, let isFavorite):
            updateExpense(
                name: name,
                amount: amount,
                currency: currency,
                plannedDate: plannedDate,
                category: category,
                priority: priority,
                isFavorite: isFavorite
            )
            
        case .showExpenseEditor:
            state.showExpenseEditor = true
            
        case .hideExpenseEditor:
            state.showExpenseEditor = false
            state.editingExpense = nil
            
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
    
    private func loadExpenses() {
        let descriptor = FetchDescriptor<PlannedExpense>(
            sortBy: [SortDescriptor(\.plannedDate, order: .forward)]
        )
        if let expenses = try? modelContext.fetch(descriptor) {
            // Сортируем: сначала избранные, потом по приоритету, потом по дате
            state.expenses = expenses.sorted { expense1, expense2 in
                if expense1.isFavorite != expense2.isFavorite {
                    return expense1.isFavorite
                }
                if expense1.priority.sortOrder != expense2.priority.sortOrder {
                    return expense1.priority.sortOrder < expense2.priority.sortOrder
                }
                return expense1.plannedDate < expense2.plannedDate
            }
            state.filteredExpenses = state.expenses
            calculateStats()
        }
    }
    
    private func calculateStats() {
        Task {
            await calculateTotalUnpaid()
            calculateOverdueCount()
        }
    }
    
    private func calculateTotalUnpaid() async {
        let displayCurrency = state.displayCurrency
        var total: Double = 0.0
        
        for expense in state.expenses where !expense.isPaid {
            let amount = expense.amount
            if expense.currency == displayCurrency {
                total += amount
            } else {
                if let converted = await CurrencyRateService.shared.convert(
                    amount: amount,
                    from: expense.currency,
                    to: displayCurrency
                ) {
                    total += converted
                } else {
                    total += amount
                }
            }
        }
        
        state.totalUnpaid = total
    }
    
    private func calculateOverdueCount() {
        state.overdueCount = state.expenses.filter { $0.isOverdue }.count
    }
    
    func refreshRates() async {
        state.isLoadingRates = true
        defer { state.isLoadingRates = false }
        
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        await calculateTotalUnpaid()
    }
    
    private func deleteExpense(_ expense: PlannedExpense) {
        modelContext.delete(expense)
        
        do {
            try modelContext.save()
            loadExpenses()
        } catch {
            AppLogger.log(.error, category: "PlannedExpense", "Failed to delete expense: \(error.localizedDescription)")
        }
    }
    
    private func toggleFavorite(_ expense: PlannedExpense) {
        expense.isFavorite.toggle()
        expense.updatedAt = Date()
        
        do {
            try modelContext.save()
            loadExpenses()
        } catch {
            AppLogger.log(.error, category: "PlannedExpense", "Failed to toggle favorite: \(error.localizedDescription)")
        }
    }
    
    private func togglePaid(_ expense: PlannedExpense) {
        expense.isPaid.toggle()
        expense.updatedAt = Date()
        
        do {
            try modelContext.save()
            loadExpenses()
        } catch {
            AppLogger.log(.error, category: "PlannedExpense", "Failed to toggle paid: \(error.localizedDescription)")
        }
    }
    
    private func updateExpense(
        name: String,
        amount: Double,
        currency: String,
        plannedDate: Date,
        category: PlannedExpenseCategory,
        priority: PlannedExpensePriority,
        isFavorite: Bool
    ) {
        if let existing = state.editingExpense {
            // Обновляем существующий расход
            existing.name = name
            existing.amount = amount
            existing.currency = currency
            existing.plannedDate = plannedDate
            existing.category = category
            existing.priority = priority
            existing.isFavorite = isFavorite
            existing.updatedAt = Date()
        } else {
            // Создаем новый расход
            let newExpense = PlannedExpense(
                name: name,
                amount: amount,
                currency: currency,
                plannedDate: plannedDate,
                category: category,
                priority: priority,
                isFavorite: isFavorite
            )
            modelContext.insert(newExpense)
        }
        
        do {
            try modelContext.save()
            loadExpenses()
            state.showExpenseEditor = false
            state.editingExpense = nil
        } catch {
            AppLogger.log(.error, category: "PlannedExpense", "Failed to save expense: \(error.localizedDescription)")
        }
    }
}
