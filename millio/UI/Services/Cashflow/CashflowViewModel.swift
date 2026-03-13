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

enum CashflowScheduledEntryKind: String {
    case recurringMonthly
    case oneTimePlanned

    var sortPriority: Int {
        switch self {
        case .recurringMonthly:
            return 0
        case .oneTimePlanned:
            return 1
        }
    }
}

struct CashflowScheduledEntry: Identifiable {
    let transaction: CashflowTransaction
    let scheduledDate: Date
    let kind: CashflowScheduledEntryKind

    var id: String {
        let stamp = Int(scheduledDate.timeIntervalSince1970)
        let createdStamp = Int(transaction.createdAt.timeIntervalSince1970)
        return "\(transaction.recurrenceSeriesID ?? "one-time")-\(stamp)-\(kind.rawValue)-\(createdStamp)"
    }
}

enum ConversionError: Error {
    case rateUnavailable(from: String, to: String, date: Date)
}

extension ConversionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .rateUnavailable(let from, let to, let date):
            return "Rate unavailable: \(from) -> \(to) on \(date)"
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

    /// Доступные счета из инвестиций для выбора в доходах.
    var availableInvestments: [Investment] = []

    /// Пользовательские категории операций
    var customCategories: [CashflowCustomCategory] = []

    /// Переопределения системных категорий (rename/icon/hidden)
    var systemCategoryOverrides: [CashflowSystemCategoryOverride] = []
    
    /// Период для графика
    var chartPeriod: ChartPeriod = .specificMonth
    
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

    /// Активы на начало периода (как в Динамике/Финансах)
    var assetsAtPeriodStart: Double = 0.0

    /// Активы на конец периода (как в Динамике/Финансах)
    var assetsAtPeriodEnd: Double = 0.0

    /// Расходы внесенные (абсолютное значение)
    var contributedExpense: Double = 0.0

    /// Изменение стоимости активов по формуле
    var assetValueChange: Double = 0.0

    /// Итого за период (end-start)
    var periodTotalChange: Double = 0.0

    /// Предупреждение о конвертации валют в истории
    var currencyConversionWarning: String? = nil

    /// Детализация доходов по категориям за период (по убыванию суммы)
    var incomeBreakdown: [CashflowCategoryBreakdownEntry] = []

    /// Детализация расходов по категориям за период (по убыванию суммы)
    var expenseBreakdown: [CashflowCategoryBreakdownEntry] = []

    /// Точки графика cashflow (по дням за период)
    var chartPoints: [CashflowChartPoint] = []

    /// Конвертированные доходы/расходы по операциям для агрегированного графика
    var convertedTransactions: [CashflowConvertedTransaction] = []
    
    /// Флаг загрузки данных
    var isLoading: Bool = false
}

// MARK: - Cashflow Category Breakdown Entry

struct CashflowCategoryBreakdownEntry: Identifiable {
    let id: String
    let title: String
    let convertedAmount: Double

    init(title: String, convertedAmount: Double) {
        self.id = title
        self.title = title
        self.convertedAmount = convertedAmount
    }
}

// MARK: - Cashflow Chart Point

struct CashflowChartPoint: Identifiable {
    let id: Date
    let date: Date
    let income: Double
    let expense: Double
    let balance: Double
}

// MARK: - Chart Period

enum ChartPeriod: String, CaseIterable {
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"
    case specificMonth = "Specific month"
    case specificQuarter = "Specific quarter"
    case specificYear = "Specific year"
    case custom = "Custom period"
    
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
        case .month: return String(localized: "Month")
        case .quarter: return String(localized: "Quarter")
        case .year: return String(localized: "Year")
        case .specificMonth: return String(localized: "Month")
        case .specificQuarter: return String(localized: "Quarter")
        case .specificYear: return String(localized: "Year")
        case .custom: return String(localized: "Custom period")
        }
    }
}

// MARK: - History Query

enum CashflowHistoryTypeFilter: CaseIterable {
    case all
    case income
    case expense
    case transfer
    case assetBalanceChange
    case accountBalanceCorrection

    var title: String {
        switch self {
        case .all: return String(localized: "cashflow.history.filter.all")
        case .income: return String(localized: "cashflow.history.filter.income")
        case .expense: return String(localized: "cashflow.history.filter.expense")
        case .transfer: return String(localized: "cashflow.history.filter.transfer")
        case .assetBalanceChange: return String(localized: "cashflow.history.filter.asset_change")
        case .accountBalanceCorrection: return String(localized: "cashflow.history.filter.account_correction")
        }
    }

    func matches(_ type: CashflowTransactionType) -> Bool {
        switch self {
        case .all:
            return true
        case .income:
            return type == .income
        case .expense:
            return type == .expense
        case .transfer:
            return type == .transfer
        case .assetBalanceChange:
            return type == .balanceAdjustment
        case .accountBalanceCorrection:
            return type == .cardBalanceAdjustment || type == .creditDebtAdjustment
        }
    }
}

struct CashflowHistoryQuery {
    var typeFilter: CashflowHistoryTypeFilter = .all
    var searchText: String = ""
    var startDate: Date?
    var endDate: Date?
}

// MARK: - Cashflow Actions

enum CashflowAction {
    case loadTransactions
    case addTransaction(CashflowTransactionType)
    case editTransaction(CashflowTransaction)
    case deleteTransaction(CashflowTransaction, recalculate: Bool)
    case updateTransaction(CashflowTransaction)
    case hideTransactionEditor
    case setChartPeriod(ChartPeriod)
    case resetToDefaultPeriod
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
    case syncPrimaryCurrencyChange(old: String, new: String)
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
    private let notificationManager: NotificationManagerProtocol
    private let now: () -> Date
    private let assetsSnapshotProvider: ((Date, Date, String) async -> (start: Double, end: Double)?)?
    private let defaults = UserDefaults.standard
    
    private var eventSubscriptionID: UUID?
    private var isRecurringGenerationInProgress: Bool = false
    private var isDueAutoApplyInProgress: Bool = false
    private let dueAutoApplyCheckpointKey = "cashflow_due_auto_apply_checkpoint_v1"
    
    init(
        modelContext: ModelContext,
        notificationManager: NotificationManagerProtocol? = nil,
        now: @escaping () -> Date = Date.init,
        assetsSnapshotProvider: ((Date, Date, String) async -> (start: Double, end: Double)?)? = nil
    ) {
        self.modelContext = modelContext
        self.historicalRateStore = HistoricalRateStore(modelContext: modelContext)
        self.notificationManager = notificationManager ?? NotificationManager.shared
        self.now = now
        self.assetsSnapshotProvider = assetsSnapshotProvider
        state.displayCurrency = SettingsManager.shared.primaryCurrencyCode
        let nowDate = now()
        state.selectedMonth = nowDate
        state.selectedQuarter = nowDate
        state.selectedYear = nowDate
        resetToDefaultPeriodInternal(referenceDate: nowDate)
        loadCards()
        loadInvestments()
        loadTransactions()
        loadCustomCategories()
        loadSystemCategoryOverrides()
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
            loadInvestments()
            state.creatingTransactionType = type
            state.editingTransaction = nil
            state.showTransactionEditor = true
            
        case .editTransaction(let transaction):
            // Обновляем список карт перед редактированием на случай изменений в финансах
            loadCards()
            loadInvestments()
            state.editingTransaction = transaction
            state.creatingTransactionType = nil
            state.showTransactionEditor = true
            
        case .deleteTransaction(let transaction, let recalculate):
            state.transactions.removeAll(where: { $0.persistentModelID == transaction.persistentModelID })
            state.filteredTransactions.removeAll(where: { $0.persistentModelID == transaction.persistentModelID })
            if recalculate {
                Task { @MainActor in
                    await deleteTransactionAsync(transaction, recalculate: true)
                }
            } else {
                deleteTransactionWithoutRecalculation(transaction)
            }
            
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

        case .resetToDefaultPeriod:
            resetToDefaultPeriodInternal(referenceDate: now())
            updateChartData()

        case .setCustomPeriod(let start, let end):
            let calendar = Calendar.current
            state.customStartDate = calendar.startOfDay(for: start)
            state.customEndDate = calendar.startOfDay(for: end)
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
            state.displayCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            updateChartData()

        case .syncPrimaryCurrencyChange(let old, let new):
            let oldNormalized = old.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let newNormalized = new.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !oldNormalized.isEmpty, !newNormalized.isEmpty else { return }
            state.displayCurrency = newNormalized
            updateChartData()
            
        case .loadCards:
            loadCards()
        }
    }
    
    private func loadTransactions() {
        loadTransactionsSnapshot()
        scheduleDueAutoApplyIfNeeded()
        scheduleRecurringGeneration()
    }

    private func loadTransactionsSnapshot() {
        let descriptor = FetchDescriptor<CashflowTransaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        state.transactions = (try? modelContext.fetch(descriptor)) ?? []
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.notificationManager.scheduleCashflowScheduledReminders(for: self.state.transactions)
        }
        applyFilters()
        loadAvailableCurrencies()
        updateChartData()
    }

    private func scheduleRecurringGeneration() {
        guard !isRecurringGenerationInProgress else { return }
        isRecurringGenerationInProgress = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isRecurringGenerationInProgress = false }

            let didGenerate = await self.generateRecurringTransactionsIfNeeded()
            if didGenerate {
                self.loadTransactionsSnapshot()
            }
        }
    }

    private func scheduleDueAutoApplyIfNeeded() {
        guard !isDueAutoApplyInProgress else { return }
        isDueAutoApplyInProgress = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isDueAutoApplyInProgress = false }

            let didApply = await self.applyDuePlannedTransactionsIfNeeded()
            if didApply {
                self.loadTransactionsSnapshot()
            }
        }
    }
    
    private func loadCards() {
        let descriptor = FetchDescriptor<Card>()
        let allCards = (try? modelContext.fetch(descriptor)) ?? []
        state.allCards = allCards
        state.availableCards = allCards.filter { $0.archivedAt == nil }
    }

    private func loadInvestments() {
        let descriptor = FetchDescriptor<Investment>()
        let allInvestments = (try? modelContext.fetch(descriptor)) ?? []
        state.availableInvestments = allInvestments.filter { $0.archivedAt == nil }
    }

    private func loadCustomCategories() {
        let descriptor = FetchDescriptor<CashflowCustomCategory>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        state.customCategories = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func loadSystemCategoryOverrides() {
        let descriptor = FetchDescriptor<CashflowSystemCategoryOverride>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        state.systemCategoryOverrides = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func subscribeToFinanceEvents() {
        eventSubscriptionID = EventBus.shared.subscribe { [weak self] event in
            guard let self else { return }
            switch event {
            case FinanceEvent.cardsUpdated:
                self.loadCards()
            case FinanceEvent.investmentsUpdated:
                self.loadInvestments()
            case FinanceEvent.transactionsUpdated:
                self.loadTransactions()
            case BackupEvent.restoreCompleted:
                self.loadTransactions()
                self.loadCards()
                self.loadInvestments()
                self.loadCustomCategories()
                self.loadSystemCategoryOverrides()
            default:
                break
            }
        }
    }
    
    private func loadAvailableCurrencies() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            var extraCodes = Set<String>()
            for transaction in state.transactions {
                extraCodes.insert(transaction.currency)
            }
            extraCodes.insert(state.displayCurrency)
            state.availableCurrencies = CurrencySelectionSupport.pickerCodes(extraCodes: Array(extraCodes))
        }
    }
    
    private func applyFilters() {
        state.filteredTransactions = state.transactions
    }

    // MARK: - History

    func historyTransactions(matching query: CashflowHistoryQuery) -> [CashflowTransaction] {
        let normalizedQuery = query.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let cardsByID = Dictionary(uniqueKeysWithValues: state.allCards.map { ($0.cardUniqueID, $0.name.lowercased()) })
        let dateRange = normalizedHistoryDateRange(start: query.startDate, end: query.endDate)

        return state.filteredTransactions.filter { transaction in
            guard query.typeFilter.matches(transaction.transactionType) else {
                return false
            }

            if let dateRange {
                let transactionDate = Calendar.current.startOfDay(for: transaction.transactionDate)
                guard transactionDate >= dateRange.start && transactionDate <= dateRange.end else {
                    return false
                }
            }

            guard !normalizedQuery.isEmpty else {
                return true
            }
            return historyTransactionMatchesSearch(
                transaction,
                query: normalizedQuery,
                cardsByID: cardsByID
            )
        }
    }

    private func normalizedHistoryDateRange(start: Date?, end: Date?) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        switch (start, end) {
        case let (startDate?, endDate?):
            let normalizedStart = calendar.startOfDay(for: min(startDate, endDate))
            let normalizedEnd = calendar.startOfDay(for: max(startDate, endDate))
            return (start: normalizedStart, end: normalizedEnd)
        case let (startDate?, nil):
            let normalized = calendar.startOfDay(for: startDate)
            return (start: normalized, end: normalized)
        case let (nil, endDate?):
            let normalized = calendar.startOfDay(for: endDate)
            return (start: normalized, end: normalized)
        case (nil, nil):
            return nil
        }
    }

    private func historyTransactionMatchesSearch(
        _ transaction: CashflowTransaction,
        query: String,
        cardsByID: [String: String]
    ) -> Bool {
        if let note = transaction.note?.lowercased(), note.contains(query) {
            return true
        }

        let incomeCategory = incomeCategoryDisplayName(for: transaction.incomeCategoryRaw).lowercased()
        if incomeCategory.contains(query) {
            return true
        }

        let expenseCategory = expenseCategoryDisplayName(for: transaction.expenseCategoryRaw).lowercased()
        if expenseCategory.contains(query) {
            return true
        }

        if transaction.transactionType.displayName.lowercased().contains(query) {
            return true
        }

        let amountWithoutFraction = String(format: "%.0f", transaction.amount)
        if amountWithoutFraction.contains(query) {
            return true
        }

        let fromCardName = cardsByID[transaction.cardID ?? ""]
        if let fromCardName, fromCardName.contains(query) {
            return true
        }

        let toCardName = cardsByID[transaction.toCardID ?? ""]
        if let toCardName, toCardName.contains(query) {
            return true
        }

        return false
    }
    
    private func updateChartData() {
        state.currencyConversionWarning = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.updateChartDataAsync()
        }
    }
    
    private func updateChartDataAsync() async {
        let (startDate, endDate) = getDateRange()
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        
        // Рассчитываем общие суммы за период и детализацию по категориям
        var totalIncome: Double = 0.0
        var totalExpense: Double = 0.0
        var incomeByCategory: [String: Double] = [:]
        var expenseByCategory: [String: Double] = [:]
        var incomeByDay: [Date: Double] = [:]
        var expenseByDay: [Date: Double] = [:]
        var convertedTransactions: [CashflowConvertedTransaction] = []
        
        for transaction in state.transactions {
            switch transaction.transactionType {
            case .income:
                let converted = await convertAmountForTransaction(
                    transaction,
                    to: state.displayCurrency
                )
                convertedTransactions.append(
                    CashflowConvertedTransaction(
                        id: transaction.transactionUniqueID,
                        date: transaction.transactionDate,
                        income: converted,
                        expense: 0
                    )
                )
                if transaction.transactionDate >= startDay && transaction.transactionDate < endExclusive {
                    totalIncome += converted
                    let day = calendar.startOfDay(for: transaction.transactionDate)
                    incomeByDay[day, default: 0.0] += converted
                    let title = incomeCategoryDisplayName(for: transaction.incomeCategoryRaw)
                    incomeByCategory[title, default: 0.0] += converted
                }
                
            case .expense:
                let converted = await convertAmountForTransaction(
                    transaction,
                    to: state.displayCurrency
                )
                convertedTransactions.append(
                    CashflowConvertedTransaction(
                        id: transaction.transactionUniqueID,
                        date: transaction.transactionDate,
                        income: 0,
                        expense: converted
                    )
                )
                if transaction.transactionDate >= startDay && transaction.transactionDate < endExclusive {
                    totalExpense += converted
                    let day = calendar.startOfDay(for: transaction.transactionDate)
                    expenseByDay[day, default: 0.0] += converted
                    let title = expenseCategoryDisplayName(for: transaction.expenseCategoryRaw)
                    expenseByCategory[title, default: 0.0] += converted
                }
                
            case .transfer, .balanceAdjustment:
                break
            case .cardBalanceAdjustment, .creditDebtAdjustment:
                break
            }
        }
        
        state.totalIncome = totalIncome
        state.totalExpense = totalExpense
        state.periodBalance = totalIncome - totalExpense
        state.incomeBreakdown = incomeByCategory
            .map { CashflowCategoryBreakdownEntry(title: $0.key, convertedAmount: $0.value) }
            .sorted { $0.convertedAmount > $1.convertedAmount }
        state.expenseBreakdown = expenseByCategory
            .map { CashflowCategoryBreakdownEntry(title: $0.key, convertedAmount: $0.value) }
            .sorted { $0.convertedAmount > $1.convertedAmount }

        let normalizedStart = startDay
        let normalizedEnd = endDay
        var points: [CashflowChartPoint] = []
        var cursor = normalizedStart
        while cursor <= normalizedEnd {
            let income = incomeByDay[cursor, default: 0.0]
            let expense = expenseByDay[cursor, default: 0.0]
            let balance = income - expense
            points.append(
                CashflowChartPoint(
                    id: cursor,
                    date: cursor,
                    income: income,
                    expense: expense,
                    balance: balance
                )
            )
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }
        state.chartPoints = points
        state.convertedTransactions = convertedTransactions.sorted { $0.date < $1.date }

        let snapshotEndDate = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: endDay
        ) ?? endDay
        await updateAssetsBreakdown(startDate: startDay, endDate: snapshotEndDate)
    }
    
    func currentDateRange() -> (Date, Date) {
        getDateRange()
    }

    func currentPeriodHeaderTitle() -> String {
        Self.makePeriodHeaderTitle(
            chartPeriod: state.chartPeriod,
            selectedMonth: state.selectedMonth,
            selectedQuarter: state.selectedQuarter,
            selectedYear: state.selectedYear,
            customStartDate: state.customStartDate,
            customEndDate: state.customEndDate,
            calendar: .current,
            locale: .autoupdatingCurrent
        )
    }

    static func makePeriodHeaderTitle(
        chartPeriod: ChartPeriod,
        selectedMonth: Date,
        selectedQuarter: Date,
        selectedYear: Date,
        customStartDate: Date,
        customEndDate: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale

        switch chartPeriod {
        case .custom:
            let start = min(customStartDate, customEndDate)
            let end = max(customStartDate, customEndDate)
            formatter.setLocalizedDateFormatFromTemplate("dMMM y")
            return "\(formatter.string(from: start)) — \(formatter.string(from: end))"

        case .year, .specificYear:
            formatter.setLocalizedDateFormatFromTemplate("y")
            return formatter.string(from: selectedYear)

        case .quarter, .specificQuarter:
            let components = calendar.dateComponents([.year, .month], from: selectedQuarter)
            let month = components.month ?? calendar.component(.month, from: selectedQuarter)
            let year = components.year ?? calendar.component(.year, from: selectedQuarter)
            let quarter = max(1, min(4, (month - 1) / 3 + 1))
            let format = AppLocalization.string("cashflow.period.quarter_title_format", locale: locale)
            return String(format: format, quarter, year)

        case .month, .specificMonth:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
            formatter.setLocalizedDateFormatFromTemplate("LLLL y")
            return formatter.string(from: monthStart)
        }
    }

    func monthlyIncomeTotal(for month: Date, in currency: String? = nil) async -> Double {
        await monthlyTotal(for: .income, month: month, in: currency)
    }

    func monthlyExpenseTotal(for month: Date, in currency: String? = nil) async -> Double {
        await monthlyTotal(for: .expense, month: month, in: currency)
    }

    func persistBulkExpenseImport(_ request: CashflowBulkExpensePersistRequest) async throws -> Int {
        guard !request.entries.isEmpty else {
            throw CashflowBulkExpenseImportError.noRowsToSave
        }
        guard let card = state.availableCards.first(where: { $0.cardUniqueID == request.cardID }) else {
            throw CashflowBulkExpenseImportError.cardNotFound
        }

        let sortedEntries = request.entries.sorted { $0.sourceOrderIndex < $1.sourceOrderIndex }
        let existingTransactions = bulkExpenseImportTransactions(
            cardID: request.cardID,
            month: request.month
        )
        let transactionDates = Self.bulkExpenseTransactionDates(
            for: request.month,
            count: sortedEntries.count,
            referenceDate: now(),
            calendar: Calendar.current
        )

        let existingAffectingTotal = existingTransactions
            .filter(\.affectsCardBalance)
            .reduce(0) { $0 + $1.amount }
        let newAffectingTotal = request.shouldAffectCardBalance
            ? sortedEntries.reduce(0) { $0 + $1.amount }
            : 0
        let availableBalanceBeforeImport = card.balance + existingAffectingTotal

        if newAffectingTotal - availableBalanceBeforeImport > 0.0000001 {
            throw CashflowBulkExpenseImportError.insufficientFunds(
                required: newAffectingTotal,
                available: availableBalanceBeforeImport,
                currency: card.currency
            )
        }

        var existingByReferenceKey: [String: CashflowTransaction] = [:]
        for transaction in existingTransactions {
            if let key = transaction.importReferenceKey {
                existingByReferenceKey[key] = transaction
            }
        }

        var seenReferenceKeys = Set<String>()
        for (index, entry) in sortedEntries.enumerated() {
            let referenceKey = Self.bulkExpenseImportReferenceKey(
                cardID: request.cardID,
                month: request.month,
                categoryRaw: entry.expenseCategoryRaw
            )
            seenReferenceKeys.insert(referenceKey)

            let transaction = existingByReferenceKey[referenceKey] ?? CashflowTransaction(
                transactionType: .expense,
                amount: entry.amount,
                currency: card.currency,
                transactionDate: transactionDates[index],
                cardID: request.cardID,
                expenseCategoryRaw: entry.expenseCategoryRaw,
                note: entry.note,
                importSourceRaw: CashflowBulkExpenseImportTransactionSource.monthlyCategoryRollup.rawValue,
                importReferenceKey: referenceKey,
                affectsCardBalance: request.shouldAffectCardBalance
            )
            transaction.amount = entry.amount
            transaction.currency = card.currency
            transaction.transactionDate = transactionDates[index]
            transaction.cardID = request.cardID
            transaction.expenseCategoryRaw = entry.expenseCategoryRaw
            transaction.note = entry.note
            transaction.importSourceRaw = CashflowBulkExpenseImportTransactionSource.monthlyCategoryRollup.rawValue
            transaction.importReferenceKey = referenceKey
            transaction.affectsCardBalance = request.shouldAffectCardBalance
            transaction.updatedAt = Date()

            let exchangeInfo = await resolveExchangeInfo(for: transaction)
            transaction.exchangeRate = exchangeInfo.rate
            transaction.exchangeRateDate = exchangeInfo.rateDate
            transaction.exchangeRateCurrency = exchangeInfo.rateCurrency
            if existingByReferenceKey[referenceKey] == nil {
                modelContext.insert(transaction)
            }
        }

        for transaction in existingTransactions where !seenReferenceKeys.contains(transaction.importReferenceKey ?? "") {
            modelContext.delete(transaction)
        }

        let adjustedBalance = max(0, availableBalanceBeforeImport - newAffectingTotal)
        if abs(adjustedBalance - card.balance) > 0.0000001 {
            card.balance = adjustedBalance
            card.updatedAt = Date()
        }

        do {
            try modelContext.save()
            loadCards()
            loadTransactions()
            return sortedEntries.count
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to save bulk expenses: \(error.localizedDescription)")
            throw error
        }
    }

    func bulkExpenseImportStoredEntries(
        cardID: String,
        month: Date
    ) -> [CashflowBulkExpenseStoredCategoryEntry] {
        bulkExpenseImportTransactions(cardID: cardID, month: month)
            .compactMap { transaction in
                guard let categoryRaw = transaction.expenseCategoryRaw else { return nil }
                return CashflowBulkExpenseStoredCategoryEntry(
                    categoryRaw: categoryRaw,
                    amount: transaction.amount,
                    note: transaction.note,
                    affectsCardBalance: transaction.affectsCardBalance
                )
            }
            .sorted { lhs, rhs in
                if lhs.categoryRaw == rhs.categoryRaw {
                    return lhs.amount > rhs.amount
                }
                return lhs.categoryRaw < rhs.categoryRaw
            }
    }

    /// Возвращает суммы по категориям за выбранный месяц для типа операции.
    /// Ключ словаря — `rawValue` категории (`IncomeCategory` / `ExpenseCategory` / `custom:*`).
    func monthlyCategoryTotals(
        for kind: CashflowCategoryKind,
        month: Date,
        in currency: String? = nil
    ) async -> [String: Double] {
        let targetType: CashflowTransactionType = kind == .income ? .income : .expense
        let targetCurrency = currency ?? state.displayCurrency
        let filtered = monthlyTransactions(for: targetType, month: month)

        let previousWarning = state.currencyConversionWarning
        defer { state.currencyConversionWarning = previousWarning }

        var totals: [String: Double] = [:]
        for transaction in filtered {
            let categoryRaw: String = {
                switch kind {
                case .income:
                    return transaction.incomeCategoryRaw ?? IncomeCategory.other.rawValue
                case .expense:
                    return transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue
                }
            }()
            let convertedAmount = await convertAmountForTransaction(transaction, to: targetCurrency)
            totals[categoryRaw, default: 0] += convertedAmount
        }

        return totals
    }

    // MARK: - Scheduled Transactions

    func recurringTemplates(
        for kind: CashflowCategoryKind,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowTransaction] {
        let baseline = referenceDate ?? now()
        let targetType: CashflowTransactionType = {
            switch kind {
            case .income: return .income
            case .expense: return .expense
            }
        }()

        return state.transactions
            .filter { transaction in
                transaction.transactionType == targetType
                && transaction.isRecurringTemplate
            }
            .sorted { lhs, rhs in
                let leftDate = nextOccurrenceDate(for: lhs, relativeTo: baseline) ?? lhs.transactionDate
                let rightDate = nextOccurrenceDate(for: rhs, relativeTo: baseline) ?? rhs.transactionDate

                if leftDate == rightDate {
                    return lhs.createdAt < rhs.createdAt
                }
                return leftDate < rightDate
            }
    }

    func plannedOneTimeTransactions(
        for kind: CashflowCategoryKind,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowTransaction] {
        let baseline = referenceDate ?? now()
        let targetType: CashflowTransactionType = {
            switch kind {
            case .income: return .income
            case .expense: return .expense
            }
        }()

        return state.transactions
            .filter { transaction in
                guard transaction.transactionType == targetType else { return false }
                guard transaction.recurrenceRule == .none else { return false }
                return transaction.transactionDate > baseline
            }
            .sorted { $0.transactionDate < $1.transactionDate }
    }

    func scheduledPlannerEntries(
        for kind: CashflowCategoryKind,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowScheduledEntry] {
        let baseline = Calendar.current.startOfDay(for: referenceDate ?? now())
        let targetType = scheduledTransactionType(for: kind)

        return state.transactions
            .compactMap { transaction -> CashflowScheduledEntry? in
                guard transaction.transactionType == targetType else { return nil }

                if transaction.isRecurringTemplate,
                   let nextDate = nextOccurrenceDate(for: transaction, relativeTo: baseline) {
                    return CashflowScheduledEntry(
                        transaction: transaction,
                        scheduledDate: nextDate,
                        kind: .recurringMonthly
                    )
                }

                guard transaction.recurrenceRule == .none, transaction.transactionDate > baseline else {
                    return nil
                }

                return CashflowScheduledEntry(
                    transaction: transaction,
                    scheduledDate: transaction.transactionDate,
                    kind: .oneTimePlanned
                )
            }
            .sorted(by: scheduledEntrySort)
    }

    func scheduledCalendarEntries(
        for kind: CashflowCategoryKind,
        month: Date,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowScheduledEntry] {
        let calendar = Calendar.current
        let baseline = calendar.startOfDay(for: referenceDate ?? now())
        let targetType = scheduledTransactionType(for: kind)
        let monthStart = Self.monthStart(for: month, calendar: calendar)

        return state.transactions
            .compactMap { transaction -> CashflowScheduledEntry? in
                guard transaction.transactionType == targetType else { return nil }

                if transaction.isRecurringTemplate {
                    let anchorDay = calendar.component(.day, from: transaction.transactionDate)
                    let scheduledDate = Self.makeMonthlyDate(
                        monthStart: monthStart,
                        day: anchorDay,
                        calendar: calendar
                    )

                    guard scheduledDate >= baseline else { return nil }
                    return CashflowScheduledEntry(
                        transaction: transaction,
                        scheduledDate: scheduledDate,
                        kind: .recurringMonthly
                    )
                }

                guard transaction.recurrenceRule == .none else { return nil }
                guard calendar.isDate(transaction.transactionDate, equalTo: monthStart, toGranularity: .month) else {
                    return nil
                }
                guard transaction.transactionDate > baseline else { return nil }

                return CashflowScheduledEntry(
                    transaction: transaction,
                    scheduledDate: transaction.transactionDate,
                    kind: .oneTimePlanned
                )
            }
            .sorted(by: scheduledEntrySort)
    }

    func nextOccurrenceDate(
        for template: CashflowTransaction,
        relativeTo referenceDate: Date? = nil
    ) -> Date? {
        guard template.isRecurringTemplate else { return nil }

        let calendar = Calendar.current
        let baseline = calendar.startOfDay(for: referenceDate ?? now())
        let baselineMonthStart = Self.monthStart(for: baseline, calendar: calendar)
        let anchorDay = calendar.component(.day, from: template.transactionDate)
        var candidate = Self.makeMonthlyDate(
            monthStart: baselineMonthStart,
            day: anchorDay,
            calendar: calendar
        )

        if candidate < baseline,
           let nextMonth = calendar.date(byAdding: .month, value: 1, to: baselineMonthStart) {
            candidate = Self.makeMonthlyDate(
                monthStart: nextMonth,
                day: anchorDay,
                calendar: calendar
            )
        }

        return candidate
    }

    private func scheduledTransactionType(for kind: CashflowCategoryKind) -> CashflowTransactionType {
        switch kind {
        case .income:
            return .income
        case .expense:
            return .expense
        }
    }

    private func scheduledEntrySort(lhs: CashflowScheduledEntry, rhs: CashflowScheduledEntry) -> Bool {
        if lhs.scheduledDate != rhs.scheduledDate {
            return lhs.scheduledDate < rhs.scheduledDate
        }
        if lhs.kind.sortPriority != rhs.kind.sortPriority {
            return lhs.kind.sortPriority < rhs.kind.sortPriority
        }
        return lhs.transaction.createdAt < rhs.transaction.createdAt
    }

    private func monthlyTotal(
        for type: CashflowTransactionType,
        month: Date,
        in currency: String? = nil
    ) async -> Double {
        let targetCurrency = currency ?? state.displayCurrency
        let filtered = monthlyTransactions(for: type, month: month)

        let previousWarning = state.currencyConversionWarning
        defer { state.currencyConversionWarning = previousWarning }

        var total: Double = 0
        for transaction in filtered {
            total += await convertAmountForTransaction(transaction, to: targetCurrency)
        }
        return total
    }

    private func monthlyTransactions(for type: CashflowTransactionType, month: Date) -> [CashflowTransaction] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) ?? monthStart

        return state.transactions.filter { transaction in
            transaction.transactionType == type
            && transaction.transactionDate >= monthStart
            && transaction.transactionDate <= monthEnd
        }
    }

    static func bulkExpenseTransactionDates(
        for month: Date,
        count: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> [Date] {
        guard count > 0 else { return [] }

        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) ?? monthStart
        let isCurrentMonth = calendar.isDate(monthStart, equalTo: referenceDate, toGranularity: .month)
        let anchor = isCurrentMonth ? min(referenceDate, monthEnd) : monthEnd

        return (0..<count).map { offset in
            calendar.date(byAdding: .minute, value: -offset, to: anchor) ?? anchor
        }.sorted()
    }

    static func bulkExpenseImportReferenceKey(
        cardID: String,
        month: Date,
        categoryRaw: String,
        calendar: Calendar = .current
    ) -> String {
        let monthStart = monthStart(for: month, calendar: calendar)
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return "bulk-expense|\(cardID)|\(year)-\(String(format: "%02d", month))|\(categoryRaw)"
    }

    // MARK: - Categories

    func categoryOptions(for kind: CashflowCategoryKind, matching query: String = "") -> [CashflowCategoryOption] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = systemCategoryOptions(for: kind) + customCategoryOptions(for: kind)

        guard !trimmedQuery.isEmpty else { return options }
        return options.filter { $0.displayName.localizedCaseInsensitiveContains(trimmedQuery) }
    }

    func categoryOption(for raw: String, kind: CashflowCategoryKind, fallbackName: String = "") -> CashflowCategoryOption {
        if let system = systemCategoryOption(for: raw, kind: kind) {
            return system
        }
        if let customID = Self.customCategoryID(from: raw),
           let custom = state.customCategories.first(where: { $0.categoryID == customID && $0.kind == kind }) {
            return CashflowCategoryOption(
                rawValue: raw,
                displayName: custom.name,
                icon: custom.icon,
                isCustom: true
            )
        }

        let fallback = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultOption = defaultCategoryOption(for: kind)
        return CashflowCategoryOption(
            rawValue: defaultOption.rawValue,
            displayName: fallback.isEmpty ? defaultOption.displayName : fallback,
            icon: defaultOption.icon,
            isCustom: false
        )
    }

    func incomeCategoryDisplayName(for raw: String?) -> String {
        guard let raw else { return String(localized: "Uncategorized") }
        return categoryOption(for: raw, kind: .income).displayName
    }

    func expenseCategoryDisplayName(for raw: String?) -> String {
        guard let raw else { return String(localized: "Uncategorized") }
        return categoryOption(for: raw, kind: .expense).displayName
    }

    @discardableResult
    func createCustomCategory(
        kind: CashflowCategoryKind,
        name: String,
        icon: String = CashflowCustomCategory.defaultIcon
    ) -> CashflowCategoryOption? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let system = systemCategoryOptions(for: kind).first(where: {
            $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return system
        }

        let normalized = CashflowCustomCategory.normalize(trimmed)
        if let existing = state.customCategories.first(where: {
            $0.kind == kind && $0.normalizedName == normalized
        }) {
            return CashflowCategoryOption(
                rawValue: Self.customRawValue(from: existing.categoryID),
                displayName: existing.name,
                icon: existing.icon,
                isCustom: true
            )
        }

        let customCategory = CashflowCustomCategory(
            kind: kind,
            name: trimmed,
            icon: CashflowCustomCategory.normalizeIcon(icon)
        )
        modelContext.insert(customCategory)

        do {
            try modelContext.save()
            loadCustomCategories()
            return CashflowCategoryOption(
                rawValue: Self.customRawValue(from: customCategory.categoryID),
                displayName: customCategory.name,
                icon: customCategory.icon,
                isCustom: true
            )
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to create custom category: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func renameCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        newName: String,
        newIcon: String? = nil
    ) -> Bool {
        if Self.customCategoryID(from: rawValue) != nil {
            return renameCustomCategory(
                rawValue: rawValue,
                kind: kind,
                newName: newName,
                newIcon: newIcon
            )
        }
        return renameSystemCategory(
            rawValue: rawValue,
            kind: kind,
            newName: newName,
            newIcon: newIcon
        )
    }

    @discardableResult
    func deleteCategory(rawValue: String, kind: CashflowCategoryKind) -> Bool {
        if Self.customCategoryID(from: rawValue) != nil {
            return deleteCustomCategory(rawValue: rawValue, kind: kind)
        }
        return deleteSystemCategory(rawValue: rawValue, kind: kind)
    }

    func canDeleteCategory(rawValue: String, kind: CashflowCategoryKind) -> Bool {
        if Self.customCategoryID(from: rawValue) != nil {
            return state.customCategories.contains {
                Self.customRawValue(from: $0.categoryID) == rawValue && $0.kind == kind
            }
        }

        let fallbackRaw = fallbackCategoryRaw(for: kind)
        if rawValue == fallbackRaw {
            return false
        }
        return baseSystemCategoryOption(for: rawValue, kind: kind) != nil
    }

    @discardableResult
    func renameCustomCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        newName: String,
        newIcon: String? = nil
    ) -> Bool {
        guard let sourceID = Self.customCategoryID(from: rawValue),
              let sourceCategory = state.customCategories.first(where: { $0.categoryID == sourceID && $0.kind == kind }) else {
            return false
        }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = CashflowCustomCategory.normalize(trimmed)
        let normalizedIcon = CashflowCustomCategory.normalizeIcon(newIcon ?? sourceCategory.icon)
        let nowDate = Date()

        if let system = systemCategoryOptions(for: kind).first(where: {
            $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            migrateTransactions(fromRaw: rawValue, toRaw: system.rawValue, kind: kind, nowDate: nowDate)
            modelContext.delete(sourceCategory)
            return saveCategoriesAndTransactions()
        }

        if let duplicate = state.customCategories.first(where: {
            $0.kind == kind && $0.normalizedName == normalized && $0.categoryID != sourceID
        }) {
            let duplicateRaw = Self.customRawValue(from: duplicate.categoryID)
            migrateTransactions(fromRaw: rawValue, toRaw: duplicateRaw, kind: kind, nowDate: nowDate)
            modelContext.delete(sourceCategory)
            return saveCategoriesAndTransactions()
        }

        sourceCategory.name = trimmed
        sourceCategory.normalizedName = normalized
        sourceCategory.icon = normalizedIcon
        sourceCategory.updatedAt = nowDate

        return saveCategoriesAndTransactions()
    }

    @discardableResult
    func deleteCustomCategory(rawValue: String, kind: CashflowCategoryKind) -> Bool {
        guard let sourceID = Self.customCategoryID(from: rawValue),
              let sourceCategory = state.customCategories.first(where: { $0.categoryID == sourceID && $0.kind == kind }) else {
            return false
        }

        let fallback = defaultCategoryOption(for: kind)
        let nowDate = Date()
        migrateTransactions(fromRaw: rawValue, toRaw: fallback.rawValue, kind: kind, nowDate: nowDate)
        modelContext.delete(sourceCategory)

        return saveCategoriesAndTransactions()
    }

    @discardableResult
    private func renameSystemCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        newName: String,
        newIcon: String? = nil
    ) -> Bool {
        guard let base = baseSystemCategoryOption(for: rawValue, kind: kind) else {
            return false
        }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalizedIcon = CashflowCustomCategory.normalizeIcon(newIcon ?? base.icon)
        let nowDate = Date()

        if let duplicateSystem = systemCategoryOptions(for: kind).first(where: {
            $0.rawValue != rawValue && $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            migrateTransactions(
                fromRaw: rawValue,
                toRaw: duplicateSystem.rawValue,
                kind: kind,
                nowDate: nowDate
            )
            setSystemCategoryOverride(
                kind: kind,
                categoryRaw: rawValue,
                name: base.displayName,
                icon: base.icon,
                isHidden: true,
                nowDate: nowDate
            )
            return saveCategoriesAndTransactions()
        }

        let isResetToBase = trimmed.caseInsensitiveCompare(base.displayName) == .orderedSame
            && normalizedIcon == base.icon

        if isResetToBase {
            removeSystemCategoryOverride(kind: kind, categoryRaw: rawValue)
        } else {
            setSystemCategoryOverride(
                kind: kind,
                categoryRaw: rawValue,
                name: trimmed,
                icon: normalizedIcon,
                isHidden: false,
                nowDate: nowDate
            )
        }

        return saveCategoriesAndTransactions()
    }

    @discardableResult
    private func deleteSystemCategory(rawValue: String, kind: CashflowCategoryKind) -> Bool {
        guard canDeleteCategory(rawValue: rawValue, kind: kind) else {
            return false
        }

        guard let base = baseSystemCategoryOption(for: rawValue, kind: kind) else {
            return false
        }

        let fallback = defaultCategoryOption(for: kind)
        let nowDate = Date()
        migrateTransactions(fromRaw: rawValue, toRaw: fallback.rawValue, kind: kind, nowDate: nowDate)
        setSystemCategoryOverride(
            kind: kind,
            categoryRaw: rawValue,
            name: base.displayName,
            icon: base.icon,
            isHidden: true,
            nowDate: nowDate
        )

        return saveCategoriesAndTransactions()
    }

    private func getDateRange() -> (Date, Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        
        switch state.chartPeriod {
        case .month:
            let reference = now()
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: reference)) ?? reference
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? reference
            return (startOfMonth, min(endOfMonth, today))
            
        case .quarter:
            let reference = now()
            let components = calendar.dateComponents([.year, .month], from: reference)
            let month = components.month ?? calendar.component(.month, from: reference)
            let year = components.year ?? calendar.component(.year, from: reference)
            let quarter = (month - 1) / 3
            let startMonth = quarter * 3 + 1
            let startOfQuarter = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? reference
            let endOfQuarter = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: startOfQuarter) ?? reference
            return (startOfQuarter, endOfQuarter)
            
        case .year:
            let reference = now()
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: reference)) ?? reference
            let endOfYear = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: startOfYear) ?? reference
            return (startOfYear, endOfYear)
            
        case .specificMonth:
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: state.selectedMonth)) ?? state.selectedMonth
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? state.selectedMonth
            if calendar.isDate(startOfMonth, equalTo: today, toGranularity: .month) {
                return (startOfMonth, today)
            }
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
            let start = min(state.customStartDate, state.customEndDate)
            let end = max(state.customStartDate, state.customEndDate)
            return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
        }
    }

    /// Дефолтный период Cashflow: текущий календарный месяц до сегодняшнего дня.
    ///
    /// Пример: для 09.03.2026 вернет 01.03.2026—09.03.2026.
    nonisolated static func defaultPeriodRange(
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let end = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: end)) ?? end
        return (calendar.startOfDay(for: start), end)
    }

    /// Нормализует и ограничивает пользовательский диапазон дат:
    /// - `start <= end`
    /// - обе даты приведены к `startOfDay`
    /// - `end` не выходит за `referenceDate` (обычно "сегодня")
    nonisolated static func clampCustomPeriodRange(
        start: Date,
        end: Date,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let normalizedStart = min(start, end)
        let normalizedEnd = max(start, end)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let clampedEnd = min(calendar.startOfDay(for: normalizedEnd), referenceDay)
        let clampedStart = min(calendar.startOfDay(for: normalizedStart), clampedEnd)
        return (clampedStart, clampedEnd)
    }

    private func resetToDefaultPeriodInternal(referenceDate: Date) {
        let range = Self.defaultPeriodRange(referenceDate: referenceDate, calendar: .current)
        state.selectedMonth = range.end
        state.customStartDate = range.start
        state.customEndDate = range.end
        state.chartPeriod = .specificMonth
    }

    private func updateAssetsBreakdown(startDate: Date, endDate: Date) async {
        let snapshot: (start: Double, end: Double)?
        if let assetsSnapshotProvider {
            snapshot = await assetsSnapshotProvider(startDate, endDate, state.displayCurrency)
        } else {
            snapshot = await resolveAssetsSnapshotFromFinance(startDate: startDate, endDate: endDate)
        }

        let startAssets = snapshot?.start ?? 0.0
        let endAssets = snapshot?.end ?? 0.0
        let periodTotalChange = endAssets - startAssets
        let income = state.totalIncome
        let expense = state.totalExpense
        let valueChange = periodTotalChange - income + expense

        state.assetsAtPeriodStart = startAssets
        state.assetsAtPeriodEnd = endAssets
        state.contributedExpense = expense
        state.assetValueChange = valueChange
        state.periodTotalChange = periodTotalChange
    }

    private func resolveAssetsSnapshotFromFinance(startDate: Date, endDate: Date) async -> (start: Double, end: Double)? {
        do {
            _ = try modelContext.fetch(FetchDescriptor<FinanceGroup>())
        } catch {
            return nil
        }

        let financeViewModel = FinanceViewModel(modelContext: modelContext, skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel
        )
        dynamicsViewModel.state.displayCurrency = state.displayCurrency
        dynamicsViewModel.loadData()

        let accounts = dynamicsViewModel.getAccountsForCalculation()
        let accountCardIDs = Set(accounts.compactMap { $0.accountType == .card ? $0.accountID : nil })
        let calendar = Calendar.current
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedEndDate = Self.endOfDay(for: endDate, calendar: calendar)

        let start = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: accounts,
            date: normalizedStartDate,
            accountCardIDs: accountCardIDs,
            debtAsNegative: true,
            includeInitialBeforeCreation: false
        )
        let end = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: accounts,
            date: normalizedEndDate,
            accountCardIDs: accountCardIDs,
            debtAsNegative: true,
            includeInitialBeforeCreation: false
        )
        return (start, end)
    }

    private func generateRecurringTransactionsIfNeeded() async -> Bool {
        let descriptor = FetchDescriptor<CashflowTransaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .forward)]
        )
        guard var allTransactions = try? modelContext.fetch(descriptor),
              !allTransactions.isEmpty else {
            return false
        }

        let templates = allTransactions.filter(\.isRecurringTemplate)
        guard !templates.isEmpty else { return false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())
        let currentMonthStart = Self.monthStart(for: today, calendar: calendar)
        var didInsert = false
        let seriesKey = { (transaction: CashflowTransaction) -> String? in
            guard let recurrenceSeriesID = transaction.recurrenceSeriesID else { return nil }
            return "\(recurrenceSeriesID)|\(transaction.transactionTypeRaw)"
        }

        for template in templates {
            guard let templateSeriesID = template.recurrenceSeriesID,
                  template.transactionType == .income || template.transactionType == .expense else {
                continue
            }

            switch template.recurrenceRule {
            case .none:
                continue
            case .monthly:
                break
            }

            let templateDate = calendar.startOfDay(for: template.transactionDate)
            let templateMonthStart = Self.monthStart(for: templateDate, calendar: calendar)
            guard templateMonthStart < currentMonthStart else { continue }

            let anchorDay = calendar.component(.day, from: templateDate)
            let expectedSeriesKey = "\(templateSeriesID)|\(template.transactionTypeRaw)"
            var monthCursor = calendar.date(byAdding: .month, value: 1, to: templateMonthStart) ?? templateMonthStart

            while monthCursor <= currentMonthStart {
                let expectedDate = Self.makeMonthlyDate(
                    monthStart: monthCursor,
                    day: anchorDay,
                    calendar: calendar
                )
                if expectedDate > today {
                    break
                }

                let existsInMonth = allTransactions.contains {
                    guard seriesKey($0) == expectedSeriesKey else { return false }
                    return Self.isSameMonth($0.transactionDate, expectedDate, calendar: calendar)
                }

                if !existsInMonth {
                    let generated = CashflowTransaction(
                        transactionType: template.transactionType,
                        amount: template.amount,
                        currency: template.currency,
                        transactionDate: expectedDate,
                        cardID: template.cardID,
                        toCardID: template.toCardID,
                        creditID: template.creditID,
                        investmentID: template.investmentID,
                        incomeCategoryRaw: template.incomeCategoryRaw,
                        expenseCategoryRaw: template.expenseCategoryRaw,
                        note: template.note,
                        recurrenceRule: .none,
                        recurrenceSeriesID: templateSeriesID,
                        affectsCardBalance: template.affectsCardBalance
                    )
                    let exchangeInfo = await resolveExchangeInfo(for: generated)
                    generated.exchangeRate = exchangeInfo.rate
                    generated.exchangeRateDate = exchangeInfo.rateDate
                    generated.exchangeRateCurrency = exchangeInfo.rateCurrency
                    modelContext.insert(generated)
                    await applyRecurringTransactionToCardBalance(generated)
                    allTransactions.append(generated)
                    didInsert = true
                }

                guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthCursor),
                      nextMonth > monthCursor else {
                    break
                }
                monthCursor = nextMonth
            }
        }

        guard didInsert else { return false }
        do {
            try modelContext.save()
            return true
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to save recurring transactions: \(error.localizedDescription)")
            return false
        }
    }

    private func applyRecurringTransactionToCardBalance(_ transaction: CashflowTransaction) async {
        guard transaction.affectsCardBalance, let cardID = transaction.cardID else {
            return
        }

        let card: Card? = {
            if let cached = state.availableCards.first(where: { $0.cardUniqueID == cardID }) {
                return cached
            }
            let descriptor = FetchDescriptor<Card>()
            let allCards = (try? modelContext.fetch(descriptor)) ?? []
            return allCards.first(where: { $0.archivedAt == nil && $0.cardUniqueID == cardID })
        }()
        guard let card else { return }

        let converted = await convertAmount(
            value: transaction.amount,
            from: transaction.currency,
            to: card.currency
        )

        switch transaction.transactionType {
        case .income:
            card.balance += converted
        case .expense:
            card.balance = max(0, card.balance - converted)
        default:
            return
        }
        card.updatedAt = now()
    }

    private func shouldAffectCardBalance(_ transaction: CashflowTransaction?) -> Bool {
        guard let transaction else { return false }
        switch transaction.transactionType {
        case .income, .expense:
            return transaction.affectsCardBalance
        case .transfer, .balanceAdjustment, .cardBalanceAdjustment:
            return true
        case .creditDebtAdjustment:
            return false
        }
    }

    private func balanceDelta(
        for transaction: CashflowTransaction?,
        onCardID cardID: String,
        in cardCurrency: String,
        direction: CardBalanceEffectDirection
    ) async throws -> Double {
        guard let transaction, shouldAffectCardBalance(transaction) else {
            return 0
        }

        let amountInCardCurrency = try await convertAmountForValidation(
            amount: transaction.amount,
            from: transaction.currency,
            to: cardCurrency,
            on: transaction.transactionDate
        )

        let appliedDelta: Double
        switch transaction.transactionType {
        case .income:
            appliedDelta = transaction.cardID == cardID ? amountInCardCurrency : 0
        case .expense:
            appliedDelta = transaction.cardID == cardID ? -amountInCardCurrency : 0
        case .transfer:
            if transaction.cardID == cardID {
                appliedDelta = -amountInCardCurrency
            } else if transaction.toCardID == cardID {
                appliedDelta = amountInCardCurrency
            } else {
                appliedDelta = 0
            }
        case .balanceAdjustment, .cardBalanceAdjustment:
            appliedDelta = transaction.cardID == cardID ? amountInCardCurrency : 0
        case .creditDebtAdjustment:
            appliedDelta = 0
        }

        switch direction {
        case .apply:
            return appliedDelta
        case .revert:
            return -appliedDelta
        }
    }

    private func card(for cardID: String) -> Card? {
        if let cached = state.availableCards.first(where: { $0.cardUniqueID == cardID }) {
            return cached
        }
        let descriptor = FetchDescriptor<Card>()
        let allCards = (try? modelContext.fetch(descriptor)) ?? []
        return allCards.first(where: { $0.cardUniqueID == cardID })
    }

    private func investment(for investmentID: String) -> Investment? {
        if let cached = state.availableInvestments.first(where: { $0.investmentUniqueID == investmentID }) {
            return cached
        }
        let descriptor = FetchDescriptor<Investment>()
        let allInvestments = (try? modelContext.fetch(descriptor)) ?? []
        return allInvestments.first(where: { $0.investmentUniqueID == investmentID })
    }

    private func investmentBalanceDelta(
        for transaction: CashflowTransaction?,
        investmentCurrency: String,
        direction: CardBalanceEffectDirection
    ) async throws -> Double {
        guard let transaction, shouldAffectCardBalance(transaction), transaction.investmentID != nil else {
            return 0
        }

        let amountInInvestmentCurrency = try await convertAmountForValidation(
            amount: transaction.amount,
            from: transaction.currency,
            to: investmentCurrency,
            on: transaction.transactionDate
        )

        let appliedDelta: Double
        switch transaction.transactionType {
        case .income, .balanceAdjustment, .cardBalanceAdjustment:
            appliedDelta = amountInInvestmentCurrency
        case .expense:
            appliedDelta = -amountInInvestmentCurrency
        case .transfer, .creditDebtAdjustment:
            appliedDelta = 0
        }

        switch direction {
        case .apply:
            return appliedDelta
        case .revert:
            return -appliedDelta
        }
    }

    private func applyAccountBalanceEffect(
        for transaction: CashflowTransaction,
        direction: CardBalanceEffectDirection
    ) async throws {
        guard shouldApplyCardBalanceImmediately(for: transaction) else { return }

        if let investmentID = transaction.investmentID,
           let investment = investment(for: investmentID) {
            let delta = try await investmentBalanceDelta(
                for: transaction,
                investmentCurrency: investment.currency,
                direction: direction
            )
            guard abs(delta) > 0.0000001 else { return }
            investment.amount = max(0, investment.amount + delta)
            investment.updatedAt = now()
            return
        }

        let impactedCardIDs = Set([transaction.cardID, transaction.toCardID].compactMap { $0 })
        guard !impactedCardIDs.isEmpty else { return }

        let resolvedCards = impactedCardIDs.compactMap { cardID -> (String, Card)? in
            guard let card = card(for: cardID) else { return nil }
            return (cardID, card)
        }

        for (cardID, card) in resolvedCards {
            let delta = try await balanceDelta(
                for: transaction,
                onCardID: cardID,
                in: card.currency,
                direction: direction
            )
            guard abs(delta) > 0.0000001 else { continue }
            card.balance = max(0, card.balance + delta)
            card.updatedAt = now()
        }
    }

    private func canPersistTransaction(
        _ transaction: CashflowTransaction,
        replacing existingTransaction: CashflowTransaction?
    ) async throws -> Bool {
        switch transaction.transactionType {
        case .expense:
            guard shouldApplyCardBalanceImmediately(for: transaction) else {
                return true
            }
            guard transaction.affectsCardBalance,
                  let fromCardID = transaction.cardID else {
                return true
            }
            return try await isAmountAvailable(
                amount: transaction.amount,
                currency: transaction.currency,
                fromCardID: fromCardID,
                on: transaction.transactionDate,
                replacing: existingTransaction
            )
        case .transfer:
            guard shouldApplyCardBalanceImmediately(for: transaction) else {
                return true
            }
            guard let fromCardID = transaction.cardID else {
                return false
            }
            return try await isAmountAvailable(
                amount: transaction.amount,
                currency: transaction.currency,
                fromCardID: fromCardID,
                on: transaction.transactionDate,
                replacing: existingTransaction
            )
        case .income, .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            return true
        }
    }

    private func shouldApplyCardBalanceImmediately(for transaction: CashflowTransaction) -> Bool {
        switch transaction.transactionType {
        case .income, .expense:
            guard transaction.affectsCardBalance else { return false }
            guard !transaction.isRecurringTemplate else { return false }
            return transaction.transactionDate <= now()
        case .transfer:
            return transaction.transactionDate <= now()
        case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            return true
        }
    }

    private func applyDuePlannedTransactionsIfNeeded() async -> Bool {
        let referenceNow = now()
        guard let previousCheckpoint = defaults.object(forKey: dueAutoApplyCheckpointKey) as? Date else {
            defaults.set(referenceNow, forKey: dueAutoApplyCheckpointKey)
            return false
        }

        let dueTransactions = state.transactions
            .filter { transaction in
                guard transaction.transactionType == .income || transaction.transactionType == .expense else {
                    return false
                }
                guard transaction.recurrenceRule == .none else { return false }
                guard transaction.affectsCardBalance else { return false }
                return transaction.transactionDate > previousCheckpoint
                    && transaction.transactionDate <= referenceNow
            }
            .sorted { $0.transactionDate < $1.transactionDate }

        guard !dueTransactions.isEmpty else {
            defaults.set(referenceNow, forKey: dueAutoApplyCheckpointKey)
            return false
        }

        for transaction in dueTransactions {
            do {
                try await applyAccountBalanceEffect(for: transaction, direction: .apply)
                transaction.updatedAt = referenceNow
            } catch {
                AppLogger.log(
                    .error,
                    category: "Cashflow",
                    "Failed to auto-apply due planned transaction: \(error.localizedDescription)"
                )
            }
        }

        do {
            try modelContext.save()
            defaults.set(referenceNow, forKey: dueAutoApplyCheckpointKey)
            return true
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to save due planned auto-apply: \(error.localizedDescription)")
            return false
        }
    }

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func bulkExpenseImportTransactions(cardID: String, month: Date) -> [CashflowTransaction] {
        let calendar = Calendar.current
        let monthStart = Self.monthStart(for: month, calendar: calendar)
        let descriptor = FetchDescriptor<CashflowTransaction>()
        let allTransactions = (try? modelContext.fetch(descriptor)) ?? []
        return allTransactions.filter { transaction in
            transaction.transactionType == .expense
            && transaction.cardID == cardID
            && transaction.importSourceRaw == CashflowBulkExpenseImportTransactionSource.monthlyCategoryRollup.rawValue
            && Self.isSameMonth(transaction.transactionDate, monthStart, calendar: calendar)
        }
    }

    private static func endOfDay(for date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return date
        }
        return nextDay.addingTimeInterval(-0.001)
    }

    private static func isSameMonth(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        let left = calendar.dateComponents([.year, .month], from: lhs)
        let right = calendar.dateComponents([.year, .month], from: rhs)
        return left.year == right.year && left.month == right.month
    }

    private static func makeMonthlyDate(monthStart: Date, day: Int, calendar: Calendar) -> Date {
        let maxDay = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? day
        let clampedDay = min(max(day, 1), maxDay)
        return calendar.date(byAdding: .day, value: clampedDay - 1, to: monthStart) ?? monthStart
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

    private enum CardBalanceEffectDirection {
        case apply
        case revert
    }

    func isAmountAvailable(
        amount: Double,
        currency: String,
        fromCardID: String,
        on date: Date,
        replacing existingTransaction: CashflowTransaction? = nil
    ) async throws -> Bool {
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

        let restoredBalance = card.balance + (try await balanceDelta(
            for: existingTransaction,
            onCardID: fromCardID,
            in: card.currency,
            direction: .revert
        ))

        return convertedAmount <= restoredBalance + 0.0001
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
                state.currencyConversionWarning = "Some values were calculated using an estimated exchange rate."
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
                state.currencyConversionWarning = "Some values were calculated using an estimated exchange rate."
            }
            return converted
        }

        return transaction.amount
    }
    
    private func deleteTransactionAsync(_ transaction: CashflowTransaction, recalculate: Bool) async {
        if recalculate {
            do {
                try await applyAccountBalanceEffect(for: transaction, direction: .revert)
            } catch {
                AppLogger.log(.error, category: "Cashflow", "Failed to revert card balance on delete: \(error.localizedDescription)")
                return
            }
        }

        modelContext.delete(transaction)
        
        do {
            try modelContext.save()
            if recalculate {
                loadTransactions()
            }
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to delete transaction: \(error.localizedDescription)")
        }
    }

    private func deleteTransactionWithoutRecalculation(_ transaction: CashflowTransaction) {
        modelContext.delete(transaction)

        do {
            try modelContext.save()
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to delete transaction without recalculation: \(error.localizedDescription)")
        }
    }
    
    private func updateTransactionAsync(_ transaction: CashflowTransaction) async {
        let exchangeInfo = await resolveExchangeInfo(for: transaction)

        do {
            let isAvailable = try await canPersistTransaction(transaction, replacing: state.editingTransaction)
            if !isAvailable {
                AppLogger.log(.warning, category: "Cashflow", "Insufficient funds for transaction")
                return
            }
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Balance validation failed: \(error.localizedDescription)")
            return
        }
        
        if let existing = state.editingTransaction {
            do {
                if shouldApplyCardBalanceImmediately(for: existing) {
                    try await applyAccountBalanceEffect(for: existing, direction: .revert)
                }
                if shouldApplyCardBalanceImmediately(for: transaction) {
                    try await applyAccountBalanceEffect(for: transaction, direction: .apply)
                }
            } catch {
                AppLogger.log(.error, category: "Cashflow", "Failed to update card balance effect: \(error.localizedDescription)")
                return
            }

            // Обновляем существующую транзакцию
            existing.transactionTypeRaw = transaction.transactionTypeRaw
            existing.amount = transaction.amount
            existing.currency = transaction.currency
            existing.transactionDate = transaction.transactionDate
            existing.cardID = transaction.cardID
            existing.toCardID = transaction.toCardID
            existing.creditID = transaction.creditID
            existing.investmentID = transaction.investmentID
            existing.incomeCategoryRaw = transaction.incomeCategoryRaw
            existing.expenseCategoryRaw = transaction.expenseCategoryRaw
            existing.note = transaction.note
            existing.recurrenceRuleRaw = transaction.recurrenceRuleRaw
            existing.recurrenceSeriesID = transaction.recurrenceSeriesID
            existing.affectsCardBalance = transaction.affectsCardBalance
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
                creditID: transaction.creditID,
                investmentID: transaction.investmentID,
                incomeCategoryRaw: transaction.incomeCategoryRaw,
                expenseCategoryRaw: transaction.expenseCategoryRaw,
                note: transaction.note,
                recurrenceRule: transaction.recurrenceRule,
                recurrenceSeriesID: transaction.recurrenceSeriesID,
                affectsCardBalance: transaction.affectsCardBalance
            )
            newTransaction.exchangeRate = exchangeInfo.rate
            newTransaction.exchangeRateDate = exchangeInfo.rateDate
            newTransaction.exchangeRateCurrency = exchangeInfo.rateCurrency
            modelContext.insert(newTransaction)
            do {
                if shouldApplyCardBalanceImmediately(for: newTransaction) {
                    try await applyAccountBalanceEffect(for: newTransaction, direction: .apply)
                }
            } catch {
                AppLogger.log(.error, category: "Cashflow", "Failed to apply card balance effect: \(error.localizedDescription)")
                modelContext.delete(newTransaction)
                return
            }
        }
        
        do {
            try modelContext.save()
            loadTransactions()
            state.showTransactionEditor = false
            state.editingTransaction = nil
            state.creatingTransactionType = nil
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to save transaction: \(error.localizedDescription)")
        }
    }
    
    private func migrateTransactions(
        fromRaw sourceRaw: String,
        toRaw targetRaw: String,
        kind: CashflowCategoryKind,
        nowDate: Date
    ) {
        let linkedTransactions = state.transactions.filter {
            switch kind {
            case .income: return $0.incomeCategoryRaw == sourceRaw
            case .expense: return $0.expenseCategoryRaw == sourceRaw
            }
        }

        for transaction in linkedTransactions {
            switch kind {
            case .income:
                transaction.incomeCategoryRaw = targetRaw
            case .expense:
                transaction.expenseCategoryRaw = targetRaw
            }
            transaction.updatedAt = nowDate
        }
    }

    @discardableResult
    private func saveCategoriesAndTransactions() -> Bool {
        do {
            try modelContext.save()
            loadCustomCategories()
            loadSystemCategoryOverrides()
            loadTransactions()
            return true
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to save category changes: \(error.localizedDescription)")
            return false
        }
    }

    private static func customRawValue(from categoryID: String) -> String {
        "\(CashflowTransaction.customCategoryPrefix)\(categoryID)"
    }

    private static func customCategoryID(from rawValue: String) -> String? {
        guard rawValue.hasPrefix(CashflowTransaction.customCategoryPrefix) else { return nil }
        return String(rawValue.dropFirst(CashflowTransaction.customCategoryPrefix.count))
    }

    private func defaultCategoryOption(for kind: CashflowCategoryKind) -> CashflowCategoryOption {
        let fallbackRaw = fallbackCategoryRaw(for: kind)
        return systemCategoryOption(for: fallbackRaw, kind: kind) ?? CashflowCategoryOption(
            rawValue: fallbackRaw,
            displayName: "Other",
            icon: "ellipsis.circle.fill",
            isCustom: false
        )
    }

    private func systemCategoryOption(for raw: String, kind: CashflowCategoryKind) -> CashflowCategoryOption? {
        guard let base = baseSystemCategoryOption(for: raw, kind: kind) else {
            return nil
        }
        if let override = systemCategoryOverride(for: raw, kind: kind) {
            if override.isHidden {
                return nil
            }
            return CashflowCategoryOption(
                rawValue: raw,
                displayName: override.name,
                icon: override.icon,
                isCustom: false
            )
        }
        return base
    }

    private func systemCategoryOptions(for kind: CashflowCategoryKind) -> [CashflowCategoryOption] {
        systemCategoryRaws(for: kind).compactMap { raw in
            systemCategoryOption(for: raw, kind: kind)
        }
    }

    private func customCategoryOptions(for kind: CashflowCategoryKind) -> [CashflowCategoryOption] {
        state.customCategories
            .filter { $0.kind == kind }
            .map {
                CashflowCategoryOption(
                    rawValue: Self.customRawValue(from: $0.categoryID),
                    displayName: $0.name,
                    icon: $0.icon,
                    isCustom: true
                )
            }
    }

    private func fallbackCategoryRaw(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .income: return IncomeCategory.other.rawValue
        case .expense: return ExpenseCategory.other.rawValue
        }
    }

    private func systemCategoryRaws(for kind: CashflowCategoryKind) -> [String] {
        switch kind {
        case .income:
            return IncomeCategory.allCases.map(\.rawValue)
        case .expense:
            return ExpenseCategory.allCases.map(\.rawValue)
        }
    }

    private func systemCategoryOverride(for raw: String, kind: CashflowCategoryKind) -> CashflowSystemCategoryOverride? {
        state.systemCategoryOverrides.first {
            $0.kind == kind && $0.categoryRaw == raw
        }
    }

    private func baseSystemCategoryOption(for raw: String, kind: CashflowCategoryKind) -> CashflowCategoryOption? {
        switch kind {
        case .income:
            guard let category = IncomeCategory(rawValue: raw) else { return nil }
            return CashflowCategoryOption(
                rawValue: raw,
                displayName: category.displayName,
                icon: category.icon,
                isCustom: false
            )
        case .expense:
            guard let category = ExpenseCategory(rawValue: raw) else { return nil }
            return CashflowCategoryOption(
                rawValue: raw,
                displayName: category.displayName,
                icon: category.icon,
                isCustom: false
            )
        }
    }

    private func setSystemCategoryOverride(
        kind: CashflowCategoryKind,
        categoryRaw: String,
        name: String,
        icon: String,
        isHidden: Bool,
        nowDate: Date
    ) {
        let normalizedName = CashflowCustomCategory.normalize(name)
        let normalizedIcon = CashflowCustomCategory.normalizeIcon(icon)

        if let existing = systemCategoryOverride(for: categoryRaw, kind: kind) {
            existing.name = name
            existing.normalizedName = normalizedName
            existing.icon = normalizedIcon
            existing.isHidden = isHidden
            existing.updatedAt = nowDate
            return
        }

        let newOverride = CashflowSystemCategoryOverride(
            kind: kind,
            categoryRaw: categoryRaw,
            name: name,
            icon: normalizedIcon,
            isHidden: isHidden
        )
        newOverride.updatedAt = nowDate
        modelContext.insert(newOverride)
    }

    private func removeSystemCategoryOverride(kind: CashflowCategoryKind, categoryRaw: String) {
        guard let existing = systemCategoryOverride(for: categoryRaw, kind: kind) else {
            return
        }
        modelContext.delete(existing)
    }
}
