//
//  InvestmentViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Investment State

struct InvestmentState {
    /// Все инвестиции
    var investments: [Investment] = []
    
    /// Отфильтрованные инвестиции
    var filteredInvestments: [Investment] = []
    
    /// Показывать ли экран добавления/редактирования
    var showInvestmentEditor: Bool = false
    
    /// Редактируемая инвестиция (nil = новая инвестиция)
    var editingInvestment: Investment? = nil
    
    /// Показывать ли sheet выбора валюты для отображения
    var showDisplayCurrencySheet: Bool = false
    
    /// Валюта для отображения
    var displayCurrency: String = "RUB"
    
    /// Общая стоимость плюсовых инвестиций (в выбранной валюте)
    var totalPositive: Double = 0.0
    
    /// Общая стоимость минусовых инвестиций (в выбранной валюте)
    var totalNegative: Double = 0.0
    
    /// Общий баланс (плюсовые - минусовые)
    var balance: Double = 0.0
    
    /// Общая стоимость инвестиций, учитываемых в общих финансах
    var totalIncluded: Double = 0.0
    
    /// Флаг загрузки курсов
    var isLoadingRates: Bool = false
}

// MARK: - Market Data Draft

struct InvestmentMarketData: Equatable {
    var symbol: String?
    var exchange: String?
    var currency: String?
    var quantity: Double?
    var unitPrice: Double?
    var priceUpdatedAt: Date?
    var providerRaw: String?
}

// MARK: - Investment Actions

enum InvestmentAction {
    case loadInvestments
    case addInvestment
    case editInvestment(Investment)
    case deleteInvestment(Investment)
    case toggleFavorite(Investment)
    case updateInvestment(
        name: String,
        investmentType: InvestmentType,
        category: InvestmentCategory,
        amount: Double,
        currency: String,
        includeInTotal: Bool,
        priority: InvestmentPriority,
        isFavorite: Bool,
        marketData: InvestmentMarketData?,
        createCashflowTransaction: Bool,
        uniqueID: String?
    )
    case showInvestmentEditor
    case hideInvestmentEditor
    case showDisplayCurrencySheet
    case hideDisplayCurrencySheet
    case setDisplayCurrency(String)
}

// MARK: - Investment ViewModel

@MainActor
final class InvestmentViewModel: ViewModelProtocol {
    @Published var state = InvestmentState()
    
    let modelContext: ModelContext
    
    private let defaults = UserDefaults.standard
    
    private var storedDisplayCurrency: String {
        get { defaults.string(forKey: "investment_display_currency") ?? SettingsManager.shared.primaryCurrencyCode }
        set { defaults.set(newValue, forKey: "investment_display_currency") }
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        state.displayCurrency = storedDisplayCurrency
        loadInvestments()
    }
    
    func handle(_ action: InvestmentAction) {
        switch action {
        case .loadInvestments:
            loadInvestments()
            
        case .addInvestment:
            state.editingInvestment = nil
            state.showInvestmentEditor = true
            
        case .editInvestment(let investment):
            state.editingInvestment = investment
            state.showInvestmentEditor = true
            
        case .deleteInvestment(let investment):
            deleteInvestment(investment)
            
        case .toggleFavorite(let investment):
            toggleFavorite(investment)
            
        case .updateInvestment(
            let name,
            let investmentType,
            let category,
            let amount,
            let currency,
            let includeInTotal,
            let priority,
            let isFavorite,
            let marketData,
            let createCashflowTransaction,
            let uniqueID
        ):
            updateInvestment(
                name: name,
                investmentType: investmentType,
                category: category,
                amount: amount,
                currency: currency,
                includeInTotal: includeInTotal,
                priority: priority,
                isFavorite: isFavorite,
                marketData: marketData,
                createCashflowTransaction: createCashflowTransaction,
                uniqueID: uniqueID
            )
            
        case .showInvestmentEditor:
            state.showInvestmentEditor = true
            
        case .hideInvestmentEditor:
            state.showInvestmentEditor = false
            state.editingInvestment = nil
            
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
    
    private func loadInvestments() {
        let descriptor = FetchDescriptor<Investment>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let investments = try? modelContext.fetch(descriptor) {
            let activeInvestments = investments.filter { $0.archivedAt == nil }
            // Сортируем: сначала избранные, потом по приоритету, потом по дате
            state.investments = activeInvestments.sorted { inv1, inv2 in
                if inv1.isFavorite != inv2.isFavorite {
                    return inv1.isFavorite
                }
                if inv1.priority.sortOrder != inv2.priority.sortOrder {
                    return inv1.priority.sortOrder < inv2.priority.sortOrder
                }
                return inv1.updatedAt > inv2.updatedAt
            }
            state.filteredInvestments = state.investments
            calculateStats()
            
            // Обновляем InvestmentManager
            InvestmentManager.shared.setup(modelContext: modelContext)
        }
    }
    
    private func calculateStats() {
        Task {
            await calculateTotalAmounts()
        }
    }
    
    private func calculateTotalAmounts() async {
        let displayCurrency = state.displayCurrency
        var totalPositive: Double = 0.0
        var totalNegative: Double = 0.0
        var totalIncluded: Double = 0.0
        
        for investment in state.investments {
            let amount = investment.amount
            
            // Конвертируем валюту если нужно
            var convertedAmount = amount
            if investment.currency != displayCurrency {
                if let converted = await CurrencyRateService.shared.convert(
                    amount: amount,
                    from: investment.currency,
                    to: displayCurrency
                ) {
                    convertedAmount = converted
                }
            }
            
            // Считаем по типам
            if investment.investmentType == .positive {
                totalPositive += convertedAmount
            } else {
                totalNegative += convertedAmount
            }
            
            // Считаем учитываемые в общих финансах
            if investment.includeInTotal {
                totalIncluded += (investment.investmentType == .positive ? convertedAmount : -convertedAmount)
            }
        }
        
        state.totalPositive = totalPositive
        state.totalNegative = totalNegative
        state.balance = totalPositive - totalNegative
        state.totalIncluded = totalIncluded
    }
    
    func refreshRates() async {
        state.isLoadingRates = true
        defer { state.isLoadingRates = false }
        
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        await calculateTotalAmounts()
    }
    
    private func deleteInvestment(_ investment: Investment) {
        investment.archivedAt = Date()
        investment.updatedAt = Date()
        
        do {
            try modelContext.save()
            loadInvestments()
        } catch {
            AppLogger.log(.error, category: "Investment", "Failed to delete investment: \(error.localizedDescription)")
        }
    }
    
    private func toggleFavorite(_ investment: Investment) {
        investment.isFavorite.toggle()
        investment.updatedAt = Date()
        
        do {
            try modelContext.save()
            loadInvestments()
        } catch {
            AppLogger.log(.error, category: "Investment", "Failed to toggle favorite: \(error.localizedDescription)")
        }
    }
    
    private func updateInvestment(
        name: String,
        investmentType: InvestmentType,
        category: InvestmentCategory,
        amount: Double,
        currency: String,
        includeInTotal: Bool,
        priority: InvestmentPriority,
        isFavorite: Bool,
        marketData: InvestmentMarketData?,
        createCashflowTransaction: Bool,
        uniqueID: String?
    ) {
        var editedInvestment: Investment? = nil
        var oldAmount: Double = 0.0
        
        if let existing = state.editingInvestment {
            if existing.uniqueID.isEmpty {
                existing.ensureUniqueID()
            }
            if !existing.hasInitialAmount {
                existing.initialAmount = existing.amount
                existing.hasInitialAmount = true
            }
            oldAmount = existing.amount
            editedInvestment = existing
            // Обновляем существующую инвестицию
            existing.name = name
            existing.investmentType = investmentType
            existing.category = category
            existing.amount = amount
            existing.currency = currency
            existing.includeInTotal = includeInTotal
            existing.priority = priority
            existing.isFavorite = isFavorite
            applyMarketData(
                marketData,
                to: existing,
                category: category
            )
            existing.recalculateAmountFromPosition()
            existing.updatedAt = Date()
        } else {
            // Создаем новую инвестицию
            let newInvestment = Investment(
                name: name,
                investmentType: investmentType,
                category: category,
                amount: amount,
                currency: currency,
                includeInTotal: includeInTotal,
                priority: priority,
                isFavorite: isFavorite
            )
            if let uniqueID, !uniqueID.isEmpty {
                newInvestment.uniqueID = uniqueID
            }
            applyMarketData(
                marketData,
                to: newInvestment,
                category: category
            )
            newInvestment.recalculateAmountFromPosition()
            modelContext.insert(newInvestment)
        }
        
        // Создание CashflowTransaction если нужно (перед save для атомарности)
        if createCashflowTransaction, let existing = editedInvestment {
            let delta = amount - oldAmount
            if abs(delta) > 0.01 {
                let transaction = CashflowTransaction(
                    transactionType: .balanceAdjustment,
                    amount: delta,
                    currency: existing.currency,
                    transactionDate: Date(),
                    investmentID: existing.investmentUniqueID,
                    note: "Ручное изменение стоимости актива"
                )
                modelContext.insert(transaction)
            }
        }
        
        // Атомарное сохранение всех изменений (Investment и CashflowTransaction)
        do {
            try modelContext.save()
            loadInvestments()
            state.showInvestmentEditor = false
            state.editingInvestment = nil
        } catch {
            AppLogger.log(.error, category: "Investment", "Failed to save investment: \(error.localizedDescription)")
        }
    }

    private func applyMarketData(
        _ marketData: InvestmentMarketData?,
        to investment: Investment,
        category: InvestmentCategory
    ) {
        let isMarketCategory = (category == .stocks || category == .crypto)

        if !isMarketCategory {
            investment.marketSymbol = nil
            investment.marketExchange = nil
            investment.marketCurrency = nil
            investment.marketQuantity = nil
            investment.lastKnownUnitPrice = nil
            investment.lastKnownPriceUpdatedAt = nil
            investment.marketProviderRaw = nil
            return
        }

        investment.marketSymbol = marketData?.symbol
        investment.marketExchange = marketData?.exchange
        investment.marketCurrency = marketData?.currency
        investment.marketQuantity = marketData?.quantity
        investment.lastKnownUnitPrice = marketData?.unitPrice
        investment.lastKnownPriceUpdatedAt = marketData?.priceUpdatedAt
        investment.marketProviderRaw = marketData?.providerRaw
    }
}
