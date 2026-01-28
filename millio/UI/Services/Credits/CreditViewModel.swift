//
//  CreditViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 11.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Credit State

struct CreditState {
    /// Все кредиты
    var credits: [Credit] = []
    
    /// Отфильтрованные кредиты (для поиска)
    var filteredCredits: [Credit] = []
    
    /// Текст поиска
    var searchText: String = ""
    
    /// Выбранный фильтр банка
    var selectedBank: Bank? = nil
    
    /// Выбранный фильтр типа кредита
    var selectedCreditType: CreditType? = nil
    
    /// Выбранный фильтр валюты
    var selectedCurrency: String? = nil
    
    /// Показывать ли экран добавления/редактирования
    var showCreditEditor: Bool = false
    
    /// Редактируемый кредит (nil = новый кредит)
    var editingCredit: Credit? = nil
    
    /// Показывать ли статистику
    var showStats: Bool = false
    
    /// Показывать ли sheet выбора банка
    var showBankFilterSheet: Bool = false
    
    /// Показывать ли sheet выбора типа кредита
    var showCreditTypeFilterSheet: Bool = false
    
    /// Показывать ли sheet выбора валюты
    var showCurrencyFilterSheet: Bool = false
    
    /// Показывать ли sheet выбора валюты для отображения общего долга
    var showDisplayCurrencySheet: Bool = false
    
    /// Валюта для отображения общего долга
    var displayCurrency: String = "RUB"
    
    /// Общий долг по всем кредитам (в выбранной валюте)
    var totalDebt: Double = 0.0
    
    /// Долг по валютам (оригинальные значения)
    var debtByCurrency: [String: Double] = [:]
    
    /// Общая сумма ежемесячных платежей (в выбранной валюте)
    var totalMonthlyPayments: Double = 0.0
    
    /// Ежемесячные платежи по валютам (оригинальные значения)
    var monthlyPaymentsByCurrency: [String: Double] = [:]
    
    /// Флаг загрузки курсов
    var isLoadingRates: Bool = false
}

// MARK: - Credit Actions

enum CreditAction {
    case loadCredits
    case addCredit
    case editCredit(Credit)
    case deleteCredit(Credit)
    case toggleFavorite(Credit)
    case updateCredit(
        name: String,
        amount: Double,
        monthlyPayment: Double,
        endDate: Date,
        remainingAmount: Double,
        currency: String,
        bank: Bank,
        creditType: CreditType,
        isFavorite: Bool,
        includeInTotal: Bool
    )
    case search(String)
    case filterByBank(Bank?)
    case filterByCreditType(CreditType?)
    case filterByCurrency(String?)
    case clearFilters
    case showCreditEditor
    case hideCreditEditor
    case showStats
    case hideStats
    case showBankFilterSheet
    case hideBankFilterSheet
    case showCreditTypeFilterSheet
    case hideCreditTypeFilterSheet
    case showCurrencyFilterSheet
    case hideCurrencyFilterSheet
    case showDisplayCurrencySheet
    case hideDisplayCurrencySheet
    case setDisplayCurrency(String)
}

// MARK: - Credit ViewModel

@MainActor
final class CreditViewModel: ViewModelProtocol {
    @Published var state = CreditState()
    
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        // Инициализируем CreditManager
        CreditManager.shared.setup(modelContext: modelContext)
        loadCredits()
    }
    
    func handle(_ action: CreditAction) {
        switch action {
        case .loadCredits:
            loadCredits()
            
        case .addCredit:
            state.editingCredit = nil
            state.showCreditEditor = true
            
        case .editCredit(let credit):
            state.editingCredit = credit
            state.showCreditEditor = true
            
        case .deleteCredit(let credit):
            deleteCredit(credit)
            
        case .toggleFavorite(let credit):
            toggleFavorite(credit)
            
        case .updateCredit(let name, let amount, let monthlyPayment, let endDate, let remainingAmount, let currency, let bank, let creditType, let isFavorite, let includeInTotal):
            updateCredit(
                name: name,
                amount: amount,
                monthlyPayment: monthlyPayment,
                endDate: endDate,
                remainingAmount: remainingAmount,
                currency: currency,
                bank: bank,
                creditType: creditType,
                isFavorite: isFavorite,
                includeInTotal: includeInTotal
            )
            
        case .search(let text):
            state.searchText = text
            applyFilters()
            
        case .filterByBank(let bank):
            state.selectedBank = bank
            applyFilters()
            
        case .filterByCreditType(let type):
            state.selectedCreditType = type
            applyFilters()
            
        case .filterByCurrency(let currency):
            state.selectedCurrency = currency
            applyFilters()
            
        case .clearFilters:
            state.selectedBank = nil
            state.selectedCreditType = nil
            state.selectedCurrency = nil
            state.searchText = ""
            applyFilters()
            
        case .showCreditEditor:
            state.showCreditEditor = true
            
        case .hideCreditEditor:
            state.showCreditEditor = false
            state.editingCredit = nil
            
        case .showStats:
            state.showStats = true
            
        case .hideStats:
            state.showStats = false
            
        case .showBankFilterSheet:
            state.showBankFilterSheet = true
            
        case .hideBankFilterSheet:
            state.showBankFilterSheet = false
            
        case .showCreditTypeFilterSheet:
            state.showCreditTypeFilterSheet = true
            
        case .hideCreditTypeFilterSheet:
            state.showCreditTypeFilterSheet = false
            
        case .showCurrencyFilterSheet:
            state.showCurrencyFilterSheet = true
            
        case .hideCurrencyFilterSheet:
            state.showCurrencyFilterSheet = false
            
        case .showDisplayCurrencySheet:
            state.showDisplayCurrencySheet = true
            
        case .hideDisplayCurrencySheet:
            state.showDisplayCurrencySheet = false
            
        case .setDisplayCurrency(let currency):
            state.displayCurrency = currency
            calculateStats()
        }
    }
    
    // MARK: - Private Methods
    
    private func loadCredits() {
        let descriptor = FetchDescriptor<Credit>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let credits = try? modelContext.fetch(descriptor) {
            // Обновляем остатки долга только для незакрытых кредитов
            for credit in credits {
                // Не пересчитываем остаток для закрытых кредитов (где остаток был установлен вручную = 0)
                if !credit.isClosed {
                    credit.updateRemainingAmount()
                }
            }
            try? modelContext.save()
            
            state.credits = credits
            applyFilters()
            calculateStats()
        }
    }
    
    private func applyFilters() {
        // Показываем все кредиты без фильтрации
        state.filteredCredits = state.credits
    }
    
    private func calculateStats() {
        // Считаем долг по валютам
        var debtByCurrency: [String: Double] = [:]
        var monthlyPaymentsByCurrency: [String: Double] = [:]
        
        for credit in state.credits {
            debtByCurrency[credit.currency, default: 0] += credit.remainingAmount
            monthlyPaymentsByCurrency[credit.currency, default: 0] += credit.monthlyPayment
        }
        
        state.debtByCurrency = debtByCurrency
        state.monthlyPaymentsByCurrency = monthlyPaymentsByCurrency
        
        // Конвертируем общий долг и платежи в выбранную валюту
        Task {
            await calculateTotalDebt()
            await calculateTotalMonthlyPayments()
        }
    }
    
    private func calculateTotalDebt() async {
        let displayCurrency = state.displayCurrency
        var total: Double = 0.0
        
        for (currency, amount) in state.debtByCurrency {
            if currency == displayCurrency {
                total += amount
            } else {
                // Конвертируем через CurrencyRateService
                if let converted = await CurrencyRateService.shared.convert(
                    amount: amount,
                    from: currency,
                    to: displayCurrency
                ) {
                    total += converted
                } else {
                    // Если курс недоступен, просто суммируем (fallback)
                    total += amount
                }
            }
        }
        
        state.totalDebt = total
    }
    
    private func calculateTotalMonthlyPayments() async {
        let displayCurrency = state.displayCurrency
        var total: Double = 0.0
        
        for (currency, amount) in state.monthlyPaymentsByCurrency {
            if currency == displayCurrency {
                total += amount
            } else {
                // Конвертируем через CurrencyRateService
                if let converted = await CurrencyRateService.shared.convert(
                    amount: amount,
                    from: currency,
                    to: displayCurrency
                ) {
                    total += converted
                } else {
                    // Если курс недоступен, просто суммируем (fallback)
                    total += amount
                }
            }
        }
        
        state.totalMonthlyPayments = total
    }
    
    func refreshRates() async {
        state.isLoadingRates = true
        // CurrencyRateService автоматически обновит курсы при следующем запросе
        await calculateTotalDebt()
        await calculateTotalMonthlyPayments()
        state.isLoadingRates = false
    }
    
    private func deleteCredit(_ credit: Credit) {
        modelContext.delete(credit)
        
        do {
            try modelContext.save()
            loadCredits()
        } catch {
            AppLogger.log(.error, category: "Credit", "Failed to delete credit: \(error.localizedDescription)")
        }
    }
    
    private func toggleFavorite(_ credit: Credit) {
        credit.isFavorite.toggle()
        credit.updatedAt = Date()
        
        do {
            try modelContext.save()
            loadCredits()
        } catch {
            AppLogger.log(.error, category: "Credit", "Failed to toggle favorite: \(error.localizedDescription)")
        }
    }
    
    private func updateCredit(
        name: String,
        amount: Double,
        monthlyPayment: Double,
        endDate: Date,
        remainingAmount: Double,
        currency: String,
        bank: Bank,
        creditType: CreditType,
        isFavorite: Bool,
        includeInTotal: Bool
    ) {
        // Вычисляем startDate и termMonths для внутреннего использования
        // Устанавливаем startDate примерно за год до endDate (или используем существующую дату)
        let calendar = Calendar.current
        let startDate = state.editingCredit?.startDate ?? calendar.date(byAdding: .year, value: -1, to: endDate) ?? Date()
        let termMonths = Credit.calculateTermMonths(from: startDate, to: endDate)
        
        // Вычисляем процентную ставку из остальных параметров (приблизительно)
        // Если не получается вычислить, используем 0
        let interestRate = state.editingCredit?.interestRate ?? 0.0
        
        if let existing = state.editingCredit {
            let oldRemainingAmount = existing.remainingAmount
            let remainingAmountChanged = abs(remainingAmount - oldRemainingAmount) > 0.01

            if existing.uniqueID.isEmpty {
                _ = existing.creditUniqueID
            }
            if !existing.hasInitialRemainingAmount {
                existing.initialRemainingAmount = existing.remainingAmount
                existing.hasInitialRemainingAmount = true
            }
            // Обновляем существующий кредит
            existing.name = name
            existing.amount = amount
            existing.monthlyPayment = monthlyPayment
            existing.endDate = endDate
            existing.remainingAmount = remainingAmount
            existing.currency = currency
            existing.bank = bank
            existing.creditType = creditType
            existing.isFavorite = isFavorite
            existing.includeInTotal = includeInTotal
            existing.termMonths = termMonths
            // Если остаток = 0, помечаем кредит как закрытый
            if remainingAmount <= 0 {
                existing.isClosed = true
                existing.remainingAmount = 0
            } else {
                existing.isClosed = false
            }
            // startDate и interestRate оставляем как есть (не меняем при редактировании)
            existing.updatedAt = Date()

            // Корректировка остатка долга через форму редактирования = транзакция
            if remainingAmountChanged {
                let balanceChange = -(remainingAmount - oldRemainingAmount)
                let transaction = CashflowTransaction(
                    transactionType: .creditDebtAdjustment,
                    amount: balanceChange,
                    currency: existing.currency,
                    transactionDate: Date(),
                    creditID: existing.creditUniqueID,
                    note: "Редактирование остатка долга"
                )
                modelContext.insert(transaction)
            }
        } else {
            // Создаем новый кредит
            let newCredit = Credit(
                name: name,
                amount: amount,
                interestRate: interestRate,
                monthlyPayment: monthlyPayment,
                startDate: startDate,
                termMonths: termMonths,
                currency: currency,
                bank: bank,
                creditType: creditType,
                includeInTotal: includeInTotal
            )
            newCredit.endDate = endDate
            newCredit.remainingAmount = remainingAmount
            newCredit.isFavorite = isFavorite
            // Если остаток = 0, помечаем кредит как закрытый
            if remainingAmount <= 0 {
                newCredit.isClosed = true
                newCredit.remainingAmount = 0
            }
            modelContext.insert(newCredit)
        }
        
        do {
            try modelContext.save()
            loadCredits()
            state.showCreditEditor = false
            state.editingCredit = nil
        } catch {
            AppLogger.log(.error, category: "Credit", "Failed to save credit: \(error.localizedDescription)")
        }
    }
}
