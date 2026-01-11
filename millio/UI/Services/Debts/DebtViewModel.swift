//
//  DebtViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Debt State

struct DebtState {
    /// Все долги
    var debts: [Debt] = []
    
    /// Отфильтрованные долги
    var filteredDebts: [Debt] = []
    
    /// Показывать ли экран добавления/редактирования
    var showDebtEditor: Bool = false
    
    /// Редактируемый долг (nil = новый долг)
    var editingDebt: Debt? = nil
    
    /// Показывать ли sheet выбора валюты для отображения
    var showDisplayCurrencySheet: Bool = false
    
    /// Валюта для отображения
    var displayCurrency: String = "RUB"
    
    /// Общая сумма долгов мне (в выбранной валюте)
    var totalOwedToMe: Double = 0.0
    
    /// Общая сумма моих долгов (в выбранной валюте)
    var totalIOwe: Double = 0.0
    
    /// Баланс (мне должны - я должен)
    var balance: Double = 0.0
    
    /// Флаг загрузки курсов
    var isLoadingRates: Bool = false
}

// MARK: - Debt Actions

enum DebtAction {
    case loadDebts
    case addDebt
    case editDebt(Debt)
    case deleteDebt(Debt)
    case toggleFavorite(Debt)
    case updateDebt(
        name: String,
        debtType: DebtType,
        amount: Double,
        currency: String,
        contactName: String,
        dueDate: Date?,
        priority: DebtPriority,
        isFavorite: Bool
    )
    case showDebtEditor
    case hideDebtEditor
    case showDisplayCurrencySheet
    case hideDisplayCurrencySheet
    case setDisplayCurrency(String)
}

// MARK: - Debt ViewModel

@MainActor
final class DebtViewModel: ViewModelProtocol {
    @Published var state = DebtState()
    
    let modelContext: ModelContext
    
    private let defaults = UserDefaults.standard
    
    private var storedDisplayCurrency: String {
        get { defaults.string(forKey: "debt_display_currency") ?? "RUB" }
        set { defaults.set(newValue, forKey: "debt_display_currency") }
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        state.displayCurrency = storedDisplayCurrency
        loadDebts()
    }
    
    func handle(_ action: DebtAction) {
        switch action {
        case .loadDebts:
            loadDebts()
            
        case .addDebt:
            state.editingDebt = nil
            state.showDebtEditor = true
            
        case .editDebt(let debt):
            state.editingDebt = debt
            state.showDebtEditor = true
            
        case .deleteDebt(let debt):
            deleteDebt(debt)
            
        case .toggleFavorite(let debt):
            toggleFavorite(debt)
            
        case .updateDebt(let name, let debtType, let amount, let currency, let contactName, let dueDate, let priority, let isFavorite):
            updateDebt(
                name: name,
                debtType: debtType,
                amount: amount,
                currency: currency,
                contactName: contactName,
                dueDate: dueDate,
                priority: priority,
                isFavorite: isFavorite
            )
            
        case .showDebtEditor:
            state.showDebtEditor = true
            
        case .hideDebtEditor:
            state.showDebtEditor = false
            state.editingDebt = nil
            
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
    
    private func loadDebts() {
        let descriptor = FetchDescriptor<Debt>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let debts = try? modelContext.fetch(descriptor) {
            // Сортируем: сначала избранные, потом по приоритету, потом по дате
            state.debts = debts.sorted { debt1, debt2 in
                if debt1.isFavorite != debt2.isFavorite {
                    return debt1.isFavorite
                }
                if debt1.priority.sortOrder != debt2.priority.sortOrder {
                    return debt1.priority.sortOrder < debt2.priority.sortOrder
                }
                return debt1.updatedAt > debt2.updatedAt
            }
            state.filteredDebts = state.debts
            calculateStats()
            
            // Обновляем DebtManager
            DebtManager.shared.setup(modelContext: modelContext)
        }
    }
    
    private func calculateStats() {
        Task {
            await calculateTotalAmounts()
        }
    }
    
    private func calculateTotalAmounts() async {
        let displayCurrency = state.displayCurrency
        var totalOwedToMe: Double = 0.0
        var totalIOwe: Double = 0.0
        
        for debt in state.debts {
            let amount = debt.amount
            if debt.debtType == .owedToMe {
                if debt.currency == displayCurrency {
                    totalOwedToMe += amount
                } else {
                    if let converted = await CurrencyRateService.shared.convert(
                        amount: amount,
                        from: debt.currency,
                        to: displayCurrency
                    ) {
                        totalOwedToMe += converted
                    } else {
                        totalOwedToMe += amount
                    }
                }
            } else {
                if debt.currency == displayCurrency {
                    totalIOwe += amount
                } else {
                    if let converted = await CurrencyRateService.shared.convert(
                        amount: amount,
                        from: debt.currency,
                        to: displayCurrency
                    ) {
                        totalIOwe += converted
                    } else {
                        totalIOwe += amount
                    }
                }
            }
        }
        
        state.totalOwedToMe = totalOwedToMe
        state.totalIOwe = totalIOwe
        state.balance = totalOwedToMe - totalIOwe
    }
    
    func refreshRates() async {
        state.isLoadingRates = true
        defer { state.isLoadingRates = false }
        
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        await calculateTotalAmounts()
    }
    
    private func deleteDebt(_ debt: Debt) {
        modelContext.delete(debt)
        
        do {
            try modelContext.save()
            loadDebts()
        } catch {
            AppLogger.log(.error, category: "Debt", "Failed to delete debt: \(error.localizedDescription)")
        }
    }
    
    private func toggleFavorite(_ debt: Debt) {
        debt.isFavorite.toggle()
        debt.updatedAt = Date()
        
        do {
            try modelContext.save()
            loadDebts()
        } catch {
            AppLogger.log(.error, category: "Debt", "Failed to toggle favorite: \(error.localizedDescription)")
        }
    }
    
    private func updateDebt(
        name: String,
        debtType: DebtType,
        amount: Double,
        currency: String,
        contactName: String,
        dueDate: Date?,
        priority: DebtPriority,
        isFavorite: Bool
    ) {
        if let existing = state.editingDebt {
            // Обновляем существующий долг
            existing.name = name
            existing.debtType = debtType
            existing.amount = amount
            existing.currency = currency
            existing.contactName = contactName
            existing.dueDate = dueDate
            existing.priority = priority
            existing.isFavorite = isFavorite
            existing.updatedAt = Date()
        } else {
            // Создаем новый долг
            let newDebt = Debt(
                name: name,
                debtType: debtType,
                amount: amount,
                currency: currency,
                contactName: contactName,
                dueDate: dueDate,
                priority: priority,
                isFavorite: isFavorite
            )
            modelContext.insert(newDebt)
        }
        
        do {
            try modelContext.save()
            loadDebts()
            state.showDebtEditor = false
            state.editingDebt = nil
        } catch {
            AppLogger.log(.error, category: "Debt", "Failed to save debt: \(error.localizedDescription)")
        }
    }
}
