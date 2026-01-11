//
//  CashflowViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Cashflow State

struct CashflowState {
    /// Все транзакции
    var transactions: [CashflowTransaction] = []
    
    /// Отфильтрованные транзакции
    var filteredTransactions: [CashflowTransaction] = []
    
    /// Показывать ли редактор транзакции
    var showTransactionEditor: Bool = false
    
    /// Редактируемая транзакция (nil = новая транзакция)
    var editingTransaction: CashflowTransaction? = nil
    
    /// Тип создаваемой транзакции
    var creatingTransactionType: CashflowTransactionType? = nil
    
    /// Доступные карты
    var availableCards: [Card] = []
    
    /// Период для графика
    var chartPeriod: ChartPeriod = .month
    
    /// Начальная дата для custom периода
    var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    
    /// Конечная дата для custom периода
    var customEndDate: Date = Date()
    
    /// Выбранный месяц для конкретного месяца
    var selectedMonth: Date = Date()
    
    /// Выбранный квартал для конкретного квартала
    var selectedQuarter: Date = Date()
    
    /// Выбранный год для конкретного года
    var selectedYear: Date = Date()
    
    /// Показывать ли селектор периода
    var showPeriodSelector: Bool = false
    
    /// Показывать ли историю операций
    var showTransactionsHistory: Bool = false
    
    /// Данные для графика доходов
    var incomeChartData: [CashflowChartDataPoint] = []
    
    /// Данные для графика расходов
    var expenseChartData: [CashflowChartDataPoint] = []
    
    /// Флаг загрузки данных
    var isLoading: Bool = false
}

// MARK: - Cashflow Chart Data Point

struct CashflowChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String
}

// MARK: - Chart Period

enum ChartPeriod: String, CaseIterable {
    case month = "Месяц"
    case quarter = "Квартал"
    case year = "Год"
    case specificMonth = "Конкретный месяц"
    case specificQuarter = "Конкретный квартал"
    case specificYear = "Конкретный год"
    case custom = "Свой период"
    
    var days: Int {
        switch self {
        case .month, .specificMonth: return 30
        case .quarter, .specificQuarter: return 90
        case .year, .specificYear: return 365
        case .custom: return 365 // По умолчанию, будет переопределено
        }
    }
    
    var displayName: String {
        switch self {
        case .month: return "Месяц"
        case .quarter: return "Квартал"
        case .year: return "Год"
        case .specificMonth: return "Месяц"
        case .specificQuarter: return "Квартал"
        case .specificYear: return "Год"
        case .custom: return "Свой период"
        }
    }
}

// MARK: - Cashflow Actions

enum CashflowAction {
    case loadTransactions
    case addTransaction(CashflowTransactionType)
    case editTransaction(CashflowTransaction)
    case deleteTransaction(CashflowTransaction)
    case updateTransaction(CashflowTransaction)
    case hideTransactionEditor
    case setChartPeriod(ChartPeriod)
    case setCustomPeriod(start: Date, end: Date)
    case setSelectedMonth(Date)
    case setSelectedQuarter(Date)
    case setSelectedYear(Date)
    case showPeriodSelector
    case hidePeriodSelector
    case showTransactionsHistory
    case hideTransactionsHistory
    case loadCards
}

// MARK: - Cashflow ViewModel

@MainActor
final class CashflowViewModel: ViewModelProtocol {
    typealias State = CashflowState
    typealias Action = CashflowAction
    
    @Published var state = CashflowState()
    
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadTransactions()
        loadCards()
    }
    
    func handle(_ action: CashflowAction) {
        switch action {
        case .loadTransactions:
            loadTransactions()
            
        case .addTransaction(let type):
            state.creatingTransactionType = type
            state.editingTransaction = nil
            state.showTransactionEditor = true
            
        case .editTransaction(let transaction):
            state.editingTransaction = transaction
            state.creatingTransactionType = nil
            state.showTransactionEditor = true
            
        case .deleteTransaction(let transaction):
            deleteTransaction(transaction)
            
        case .updateTransaction(let transaction):
            updateTransaction(transaction)
            
        case .hideTransactionEditor:
            state.showTransactionEditor = false
            state.editingTransaction = nil
            state.creatingTransactionType = nil
            
        case .setChartPeriod(let period):
            state.chartPeriod = period
            updateChartData()
            
        case .setCustomPeriod(let start, let end):
            state.customStartDate = start
            state.customEndDate = end
            state.chartPeriod = .custom
            updateChartData()
            
        case .setSelectedMonth(let date):
            state.selectedMonth = date
            state.chartPeriod = .specificMonth
            updateChartData()
            
        case .setSelectedQuarter(let date):
            state.selectedQuarter = date
            state.chartPeriod = .specificQuarter
            updateChartData()
            
        case .setSelectedYear(let date):
            state.selectedYear = date
            state.chartPeriod = .specificYear
            updateChartData()
            
        case .showPeriodSelector:
            state.showPeriodSelector = true
            
        case .hidePeriodSelector:
            state.showPeriodSelector = false
            
        case .showTransactionsHistory:
            state.showTransactionsHistory = true
            
        case .hideTransactionsHistory:
            state.showTransactionsHistory = false
            
        case .loadCards:
            loadCards()
        }
    }
    
    private func loadTransactions() {
        let descriptor = FetchDescriptor<CashflowTransaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        state.transactions = (try? modelContext.fetch(descriptor)) ?? []
        applyFilters()
        updateChartData()
    }
    
    private func loadCards() {
        let descriptor = FetchDescriptor<Card>()
        state.availableCards = (try? modelContext.fetch(descriptor)) ?? []
    }
    
    private func applyFilters() {
        state.filteredTransactions = state.transactions
    }
    
    private func updateChartData() {
        Task {
            await updateChartDataAsync()
        }
    }
    
    private func updateChartDataAsync() async {
        let calendar = Calendar.current
        let (startDate, endDate) = getDateRange()
        
        // Группируем транзакции по датам
        var incomeByDate: [Date: Double] = [:]
        var expenseByDate: [Date: Double] = [:]
        
        for transaction in state.transactions {
            guard transaction.transactionDate >= startDate && transaction.transactionDate <= endDate else {
                continue
            }
            
            let dateKey = calendar.startOfDay(for: transaction.transactionDate)
            
            switch transaction.transactionType {
            case .income:
                let converted = await convertAmount(
                    value: transaction.amount,
                    from: transaction.currency,
                    to: "RUB"
                )
                incomeByDate[dateKey, default: 0.0] += converted
                
            case .expense:
                let converted = await convertAmount(
                    value: transaction.amount,
                    from: transaction.currency,
                    to: "RUB"
                )
                expenseByDate[dateKey, default: 0.0] += converted
                
            case .transfer:
                break // Переводы не учитываем в графике
            }
        }
        
        // Создаем точки данных для графика
        var incomePoints: [CashflowChartDataPoint] = []
        var expensePoints: [CashflowChartDataPoint] = []
        
        // Сортируем даты
        let sortedDates = Array(Set(incomeByDate.keys).union(Set(expenseByDate.keys))).sorted()
        
        for date in sortedDates {
            if let income = incomeByDate[date], income > 0 {
                incomePoints.append(CashflowChartDataPoint(
                    date: date,
                    value: income,
                    label: "Доходы"
                ))
            }
            
            if let expense = expenseByDate[date], expense > 0 {
                expensePoints.append(CashflowChartDataPoint(
                    date: date,
                    value: expense,
                    label: "Расходы"
                ))
            }
        }
        
        state.incomeChartData = incomePoints.sorted { $0.date < $1.date }
        state.expenseChartData = expensePoints.sorted { $0.date < $1.date }
    }
    
    private func getDateRange() -> (Date, Date) {
        let calendar = Calendar.current
        
        switch state.chartPeriod {
        case .month:
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -30, to: endDate) ?? endDate
            return (startDate, endDate)
            
        case .quarter:
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -90, to: endDate) ?? endDate
            return (startDate, endDate)
            
        case .year:
            let endDate = Date()
            let startDate = calendar.date(byAdding: .day, value: -365, to: endDate) ?? endDate
            return (startDate, endDate)
            
        case .specificMonth:
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: state.selectedMonth)) ?? state.selectedMonth
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? state.selectedMonth
            return (startOfMonth, endOfMonth)
            
        case .specificQuarter:
            let month = calendar.component(.month, from: state.selectedQuarter)
            let quarter = (month - 1) / 3
            let startMonth = quarter * 3 + 1
            let startOfQuarter = calendar.date(from: DateComponents(year: calendar.component(.year, from: state.selectedQuarter), month: startMonth, day: 1)) ?? state.selectedQuarter
            let endOfQuarter = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: startOfQuarter) ?? state.selectedQuarter
            return (startOfQuarter, endOfQuarter)
            
        case .specificYear:
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: state.selectedYear)) ?? state.selectedYear
            let endOfYear = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: startOfYear) ?? state.selectedYear
            return (startOfYear, endOfYear)
            
        case .custom:
            return (state.customStartDate, state.customEndDate)
        }
    }
    
    private func convertAmount(value: Double, from: String, to: String) async -> Double {
        if from == to {
            return value
        }
        
        if let converted = await CurrencyRateService.shared.convert(
            amount: value,
            from: from,
            to: to
        ) {
            return converted
        }
        
        return value
    }
    
    private func deleteTransaction(_ transaction: CashflowTransaction) {
        modelContext.delete(transaction)
        
        do {
            try modelContext.save()
            loadTransactions()
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to delete transaction: \(error.localizedDescription)")
        }
    }
    
    private func updateTransaction(_ transaction: CashflowTransaction) {
        let isNewTransaction = state.editingTransaction == nil
        
        if let existing = state.editingTransaction {
            // Обновляем существующую транзакцию
            existing.transactionTypeRaw = transaction.transactionTypeRaw
            existing.amount = transaction.amount
            existing.currency = transaction.currency
            existing.transactionDate = transaction.transactionDate
            existing.cardID = transaction.cardID
            existing.toCardID = transaction.toCardID
            existing.incomeCategoryRaw = transaction.incomeCategoryRaw
            existing.expenseCategoryRaw = transaction.expenseCategoryRaw
            existing.note = transaction.note
            existing.updatedAt = Date()
        } else {
            // Создаем новую транзакцию
            let newTransaction = CashflowTransaction(
                transactionType: transaction.transactionType,
                amount: transaction.amount,
                currency: transaction.currency,
                transactionDate: transaction.transactionDate,
                cardID: transaction.cardID,
                toCardID: transaction.toCardID,
                incomeCategory: transaction.incomeCategory,
                expenseCategory: transaction.expenseCategory,
                note: transaction.note
            )
            modelContext.insert(newTransaction)
        }
        
        do {
            try modelContext.save()
            
            // Обновляем баланс карт только для новых транзакций
            if isNewTransaction {
                Task {
                    await updateCardBalancesAsync(for: transaction)
                }
            }
            
            loadTransactions()
            state.showTransactionEditor = false
            state.editingTransaction = nil
            state.creatingTransactionType = nil
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to save transaction: \(error.localizedDescription)")
        }
    }
    
    private func updateCardBalancesAsync(for transaction: CashflowTransaction) async {
        switch transaction.transactionType {
        case .income:
            // Увеличиваем баланс карты
            if let cardID = transaction.cardID,
               let card = state.availableCards.first(where: { $0.cardUniqueID == cardID }) {
                let converted = await convertAmount(
                    value: transaction.amount,
                    from: transaction.currency,
                    to: card.currency
                )
                await MainActor.run {
                    card.balance += converted
                    card.updatedAt = Date()
                    try? modelContext.save()
                }
            }
            
        case .expense:
            // Уменьшаем баланс карты
            if let cardID = transaction.cardID,
               let card = state.availableCards.first(where: { $0.cardUniqueID == cardID }) {
                let converted = await convertAmount(
                    value: transaction.amount,
                    from: transaction.currency,
                    to: card.currency
                )
                await MainActor.run {
                    card.balance = max(0, card.balance - converted)
                    card.updatedAt = Date()
                    try? modelContext.save()
                }
            }
            
        case .transfer:
            // Переводим с одной карты на другую
            if let fromCardID = transaction.cardID,
               let toCardID = transaction.toCardID,
               let fromCard = state.availableCards.first(where: { $0.cardUniqueID == fromCardID }),
               let toCard = state.availableCards.first(where: { $0.cardUniqueID == toCardID }) {
                // Конвертируем сумму в валюту карты-источника
                let fromConverted = await convertAmount(
                    value: transaction.amount,
                    from: transaction.currency,
                    to: fromCard.currency
                )
                // Конвертируем сумму в валюту карты-получателя
                let toConverted = await convertAmount(
                    value: transaction.amount,
                    from: transaction.currency,
                    to: toCard.currency
                )
                
                await MainActor.run {
                    fromCard.balance = max(0, fromCard.balance - fromConverted)
                    toCard.balance += toConverted
                    fromCard.updatedAt = Date()
                    toCard.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        }
    }
}
