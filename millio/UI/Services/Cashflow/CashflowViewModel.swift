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

// MARK: - Conversion Error

enum ConversionError: Error {
    case rateUnavailable(from: String, to: String, date: Date)
}

extension ConversionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .rateUnavailable(let from, let to, let date):
            return "Курс недоступен: \(from) → \(to) на \(date)"
        }
    }
}

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
    
    /// Все карты (включая архивные) для истории
    var allCards: [Card] = []
    
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
    
    /// Валюта для отображения
    var displayCurrency: String = "RUB"
    
    /// Доступные валюты для отображения
    var availableCurrencies: [String] = []
    
    /// Показывать ли sheet выбора валюты
    var showCurrencySelector: Bool = false
    
    /// Сумма доходов за выбранный период
    var totalIncome: Double = 0.0
    
    /// Сумма расходов за выбранный период
    var totalExpense: Double = 0.0
    
    /// Баланс за выбранный период (доходы - расходы)
    var periodBalance: Double = 0.0

    /// Предупреждение о конвертации валют в истории
    var currencyConversionWarning: String? = nil
    
    /// Флаг загрузки данных
    var isLoading: Bool = false
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
    case showCurrencySelector
    case hideCurrencySelector
    case setDisplayCurrency(String)
    case loadCards
}

// MARK: - Cashflow ViewModel

@MainActor
final class CashflowViewModel: ViewModelProtocol {
    typealias State = CashflowState
    typealias Action = CashflowAction
    
    @Published var state = CashflowState()
    
    let modelContext: ModelContext
    private let historicalRateStore: HistoricalRateStore
    
    private let defaults = UserDefaults.standard
    private var eventSubscriptionID: UUID?
    
    private var storedDisplayCurrency: String {
        get { defaults.string(forKey: "cashflow_display_currency") ?? "RUB" }
        set { defaults.set(newValue, forKey: "cashflow_display_currency") }
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.historicalRateStore = HistoricalRateStore(modelContext: modelContext)
        state.displayCurrency = storedDisplayCurrency
        loadTransactions()
        loadCards()
        loadAvailableCurrencies()
        subscribeToFinanceEvents()
    }

    deinit {
        if let id = eventSubscriptionID {
            Task { @MainActor in
                EventBus.shared.unsubscribe(id)
            }
        }
    }
    
    func handle(_ action: CashflowAction) {
        switch action {
        case .loadTransactions:
            loadTransactions()
            
        case .addTransaction(let type):
            // Обновляем список карт перед открытием редактора, чтобы видеть актуальные данные
            loadCards()
            state.creatingTransactionType = type
            state.editingTransaction = nil
            state.showTransactionEditor = true
            
        case .editTransaction(let transaction):
            // Обновляем список карт перед редактированием на случай изменений в финансах
            loadCards()
            state.editingTransaction = transaction
            state.creatingTransactionType = nil
            state.showTransactionEditor = true
            
        case .deleteTransaction(let transaction):
            deleteTransaction(transaction)
            
        case .updateTransaction(let transaction):
            Task { @MainActor in
                await updateTransactionAsync(transaction)
            }
            
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
            
        case .showCurrencySelector:
            state.showCurrencySelector = true
            
        case .hideCurrencySelector:
            state.showCurrencySelector = false
            
        case .setDisplayCurrency(let currency):
            state.displayCurrency = currency
            storedDisplayCurrency = currency
            updateChartData()
            
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
        loadAvailableCurrencies()
        updateChartData()
    }
    
    private func loadCards() {
        let descriptor = FetchDescriptor<Card>()
        let allCards = (try? modelContext.fetch(descriptor)) ?? []
        state.allCards = allCards
        state.availableCards = allCards.filter { $0.archivedAt == nil }
    }

    private func subscribeToFinanceEvents() {
        eventSubscriptionID = EventBus.shared.subscribe { [weak self] event in
            guard let self else { return }
            if case FinanceEvent.cardsUpdated = event {
                self.loadCards()
            }
        }
    }
    
    private func loadAvailableCurrencies() {
        Task {
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            
            // Собираем валюты из всех транзакций
            var currencies = Set<String>()
            for transaction in state.transactions {
                currencies.insert(transaction.currency)
            }
            
            // Объединяем с валютами из источника курсов
            currencies = currencies.union(fromRateSource)
            
            // Добавляем текущую валюту отображения, если её нет
            if !currencies.contains(state.displayCurrency) {
                currencies.insert(state.displayCurrency)
            }
            
            state.availableCurrencies = Array(currencies).sorted()
        }
    }
    
    private func applyFilters() {
        state.filteredTransactions = state.transactions
    }
    
    private func updateChartData() {
        state.currencyConversionWarning = nil
        Task {
            await updateChartDataAsync()
        }
    }
    
    private func updateChartDataAsync() async {
        let (startDate, endDate) = getDateRange()
        
        // Рассчитываем общие суммы за период
        var totalIncome: Double = 0.0
        var totalExpense: Double = 0.0
        
        for transaction in state.transactions {
            guard transaction.transactionDate >= startDate && transaction.transactionDate <= endDate else {
                continue
            }
            
            switch transaction.transactionType {
            case .income:
                let converted = await convertAmountForTransaction(
                    transaction,
                    to: state.displayCurrency
                )
                totalIncome += converted
                
            case .expense:
                let converted = await convertAmountForTransaction(
                    transaction,
                    to: state.displayCurrency
                )
                totalExpense += converted
                
            case .transfer, .balanceAdjustment:
                break
            case .cardBalanceAdjustment, .creditDebtAdjustment:
                break
            }
        }
        
        state.totalIncome = totalIncome
        state.totalExpense = totalExpense
        state.periodBalance = totalIncome - totalExpense
    }
    
    func currentDateRange() -> (Date, Date) {
        getDateRange()
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

    private struct ExchangeInfo {
        let rate: Double?
        let rateDate: Date?
        let rateCurrency: String?
    }

    func isAmountAvailable(amount: Double, currency: String, fromCardID: String, on date: Date) async throws -> Bool {
        guard let card = state.availableCards.first(where: { $0.cardUniqueID == fromCardID }) else {
            AppLogger.log(.warning, category: "Cashflow", "isAmountAvailable: card not found for fromCardID: \(fromCardID)")
            return false
        }
        
        let convertedAmount = try await convertAmountForValidation(
            amount: amount,
            from: currency,
            to: card.currency,
            on: date
        )
        
        return convertedAmount <= card.balance + 0.0001
    }

    private func convertAmountForValidation(amount: Double, from: String, to: String, on date: Date) async throws -> Double {
        if from == to {
            return amount
        }
        
        let result = await historicalRateStore.getRate(on: date, from: from, to: to)
        if let rate = result.rate {
            return amount * rate
        }
        
        if let converted = await CurrencyRateService.shared.convert(
            amount: amount,
            from: from,
            to: to
        ) {
            return converted
        }
        
        AppLogger.log(.error, category: "Cashflow", "Currency conversion failed: from=\(from) to=\(to) date=\(date), no rate from historical store or rate service")
        throw ConversionError.rateUnavailable(from: from, to: to, date: date)
    }
    
    private func resolveExchangeInfo(for transaction: CashflowTransaction) async -> ExchangeInfo {
        let targetCurrency = state.displayCurrency
        
        guard transaction.currency != targetCurrency else {
            return ExchangeInfo(rate: 1.0, rateDate: Calendar.current.startOfDay(for: transaction.transactionDate), rateCurrency: targetCurrency)
        }
        
        let result = await historicalRateStore.getRate(
            on: transaction.transactionDate,
            from: transaction.currency,
            to: targetCurrency
        )
        
        return ExchangeInfo(
            rate: result.rate,
            rateDate: result.rateDate,
            rateCurrency: result.rate != nil ? targetCurrency : nil
        )
    }
    
    private func convertAmountForTransaction(_ transaction: CashflowTransaction, to currency: String) async -> Double {
        if transaction.currency == currency {
            return transaction.amount
        }
        
        if let rate = transaction.exchangeRate,
           let rateCurrency = transaction.exchangeRateCurrency,
           rateCurrency == currency {
            return transaction.amount * rate
        }
        
        let result = await historicalRateStore.getRate(
            on: transaction.transactionDate,
            from: transaction.currency,
            to: currency
        )

        if result.resolution != .exact {
            if state.currencyConversionWarning == nil {
                state.currencyConversionWarning = "Часть значений рассчитана по оценочному курсу."
            }
        }
        
        if let rate = result.rate {
            return transaction.amount * rate
        }
        
        if let converted = await CurrencyRateService.shared.convert(
            amount: transaction.amount,
            from: transaction.currency,
            to: currency
        ) {
            if state.currencyConversionWarning == nil {
                state.currencyConversionWarning = "Часть значений рассчитана по оценочному курсу."
            }
            return converted
        }

        return transaction.amount
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
    
    private func updateTransactionAsync(_ transaction: CashflowTransaction) async {
        let isNewTransaction = state.editingTransaction == nil
        let exchangeInfo = await resolveExchangeInfo(for: transaction)

        if isNewTransaction,
           (transaction.transactionType == .expense || transaction.transactionType == .transfer),
           let fromCardID = transaction.cardID {
            do {
                let isAvailable = try await isAmountAvailable(
                    amount: transaction.amount,
                    currency: transaction.currency,
                    fromCardID: fromCardID,
                    on: transaction.transactionDate
                )
                if !isAvailable {
                    AppLogger.log(.warning, category: "Cashflow", "Insufficient funds for transaction")
                    return
                }
            } catch {
                AppLogger.log(.error, category: "Cashflow", "Balance validation failed: \(error.localizedDescription)")
                return
            }
        }
        
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
            existing.exchangeRate = exchangeInfo.rate
            existing.exchangeRateDate = exchangeInfo.rateDate
            existing.exchangeRateCurrency = exchangeInfo.rateCurrency
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
            newTransaction.exchangeRate = exchangeInfo.rate
            newTransaction.exchangeRateDate = exchangeInfo.rateDate
            newTransaction.exchangeRateCurrency = exchangeInfo.rateCurrency
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
            
        case .balanceAdjustment:
            // Ручное изменение баланса уже было применено к карте
            // Не нужно обновлять баланс повторно
            break
        case .cardBalanceAdjustment, .creditDebtAdjustment:
            // Корректировки баланса/долга не изменяют баланс повторно
            break
        }
    }
}
