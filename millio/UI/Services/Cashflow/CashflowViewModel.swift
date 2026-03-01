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

    /// Пользовательские категории операций
    var customCategories: [CashflowCustomCategory] = []
    
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
    case movePeriodBackward
    case movePeriodForward
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
    private let now: () -> Date
    private let assetsSnapshotProvider: ((Date, Date, String) async -> (start: Double, end: Double)?)?
    
    private let defaults = UserDefaults.standard
    private var eventSubscriptionID: UUID?
    private var isRecurringGenerationInProgress: Bool = false
    
    private var storedDisplayCurrency: String {
        get { defaults.string(forKey: "cashflow_display_currency") ?? SettingsManager.shared.primaryCurrencyCode }
        set { defaults.set(newValue, forKey: "cashflow_display_currency") }
    }
    
    init(
        modelContext: ModelContext,
        now: @escaping () -> Date = Date.init,
        assetsSnapshotProvider: ((Date, Date, String) async -> (start: Double, end: Double)?)? = nil
    ) {
        self.modelContext = modelContext
        self.historicalRateStore = HistoricalRateStore(modelContext: modelContext)
        self.now = now
        self.assetsSnapshotProvider = assetsSnapshotProvider
        state.displayCurrency = storedDisplayCurrency
        state.selectedMonth = now()
        state.selectedQuarter = now()
        state.selectedYear = now()
        loadCards()
        loadTransactions()
        loadCustomCategories()
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

        case .movePeriodBackward:
            moveSelectedMonth(by: -1)

        case .movePeriodForward:
            moveSelectedMonth(by: 1)
            
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
        loadTransactionsSnapshot()
        scheduleRecurringGeneration()
    }

    private func loadTransactionsSnapshot() {
        let descriptor = FetchDescriptor<CashflowTransaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        state.transactions = (try? modelContext.fetch(descriptor)) ?? []
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
    
    private func loadCards() {
        let descriptor = FetchDescriptor<Card>()
        let allCards = (try? modelContext.fetch(descriptor)) ?? []
        state.allCards = allCards
        state.availableCards = allCards.filter { $0.archivedAt == nil }
    }

    private func loadCustomCategories() {
        let descriptor = FetchDescriptor<CashflowCustomCategory>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        state.customCategories = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func subscribeToFinanceEvents() {
        eventSubscriptionID = EventBus.shared.subscribe { [weak self] event in
            guard let self else { return }
            switch event {
            case FinanceEvent.cardsUpdated:
                self.loadCards()
            case FinanceEvent.transactionsUpdated:
                self.loadTransactions()
            case BackupEvent.restoreCompleted:
                self.loadTransactions()
                self.loadCards()
                self.loadCustomCategories()
            default:
                break
            }
        }
    }
    
    private func loadAvailableCurrencies() {
        Task { @MainActor [weak self] in
            guard let self else { return }
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.updateChartDataAsync()
        }
    }
    
    private func updateChartDataAsync() async {
        let (startDate, endDate) = getDateRange()
        
        // Рассчитываем общие суммы за период и детализацию по категориям
        var totalIncome: Double = 0.0
        var totalExpense: Double = 0.0
        var incomeByCategory: [String: Double] = [:]
        var expenseByCategory: [String: Double] = [:]
        
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
                let title = incomeCategoryDisplayName(for: transaction.incomeCategoryRaw)
                incomeByCategory[title, default: 0.0] += converted
                
            case .expense:
                let converted = await convertAmountForTransaction(
                    transaction,
                    to: state.displayCurrency
                )
                totalExpense += converted
                let title = expenseCategoryDisplayName(for: transaction.expenseCategoryRaw)
                expenseByCategory[title, default: 0.0] += converted
                
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

        await updateAssetsBreakdown(startDate: startDate, endDate: endDate)
    }
    
    func currentDateRange() -> (Date, Date) {
        getDateRange()
    }

    func currentPeriodHeaderTitle() -> String {
        if state.chartPeriod == .custom {
            let start = min(state.customStartDate, state.customEndDate)
            let end = max(state.customStartDate, state.customEndDate)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU")
            formatter.dateFormat = "d MMM yyyy"
            return "\(formatter.string(from: start)) — \(formatter.string(from: end))"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy 'г.'"
        return formatter.string(from: state.selectedMonth).capitalized
    }

    func canMovePeriodForward() -> Bool {
        let calendar = Calendar.current
        let selectedStart = calendar.date(from: calendar.dateComponents([.year, .month], from: state.selectedMonth)) ?? state.selectedMonth
        let currentStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now())) ?? now()
        return selectedStart < currentStart
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
        guard let raw else { return "Без категории" }
        return categoryOption(for: raw, kind: .income).displayName
    }

    func expenseCategoryDisplayName(for raw: String?) -> String {
        guard let raw else { return "Без категории" }
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

    private func getDateRange() -> (Date, Date) {
        let calendar = Calendar.current
        
        switch state.chartPeriod {
        case .month:
            let endDate = now()
            let startDate = calendar.date(byAdding: .day, value: -30, to: endDate) ?? endDate
            return (startDate, endDate)
            
        case .quarter:
            let endDate = now()
            let startDate = calendar.date(byAdding: .day, value: -90, to: endDate) ?? endDate
            return (startDate, endDate)
            
        case .year:
            let endDate = now()
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

    private func moveSelectedMonth(by value: Int) {
        let calendar = Calendar.current
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now())) ?? now()
        let selectedMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: state.selectedMonth)) ?? state.selectedMonth
        let candidateMonth = calendar.date(byAdding: .month, value: value, to: selectedMonthStart) ?? selectedMonthStart

        if candidateMonth > currentMonth {
            state.selectedMonth = currentMonth
        } else {
            state.selectedMonth = candidateMonth
        }
        state.chartPeriod = .specificMonth
        updateChartData()
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

        let start = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: accounts,
            date: startDate,
            accountCardIDs: accountCardIDs,
            debtAsNegative: true,
            includeInitialBeforeCreation: true
        )
        let end = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: accounts,
            date: endDate,
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
                        recurrenceSeriesID: templateSeriesID
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
        guard let cardID = transaction.cardID else {
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

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
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
            existing.recurrenceRuleRaw = transaction.recurrenceRuleRaw
            existing.recurrenceSeriesID = transaction.recurrenceSeriesID
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
                incomeCategoryRaw: transaction.incomeCategoryRaw,
                expenseCategoryRaw: transaction.expenseCategoryRaw,
                note: transaction.note,
                recurrenceRule: transaction.recurrenceRule,
                recurrenceSeriesID: transaction.recurrenceSeriesID
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
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.updateCardBalancesAsync(for: transaction)
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
                    do {
                        try modelContext.save()
                    } catch {
                        AppLogger.log(.error, category: "Cashflow", "Failed to save card balance: \(error.localizedDescription)")
                    }
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
                    do {
                        try modelContext.save()
                    } catch {
                        AppLogger.log(.error, category: "Cashflow", "Failed to save card balance: \(error.localizedDescription)")
                    }
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
                    do {
                        try modelContext.save()
                    } catch {
                        AppLogger.log(.error, category: "Cashflow", "Failed to save card balances: \(error.localizedDescription)")
                    }
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
            loadTransactions()
            return true
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to save custom categories: \(error.localizedDescription)")
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
        switch kind {
        case .income:
            return CashflowCategoryOption(
                rawValue: IncomeCategory.other.rawValue,
                displayName: IncomeCategory.other.displayName,
                icon: IncomeCategory.other.icon,
                isCustom: false
            )
        case .expense:
            return CashflowCategoryOption(
                rawValue: ExpenseCategory.other.rawValue,
                displayName: ExpenseCategory.other.displayName,
                icon: ExpenseCategory.other.icon,
                isCustom: false
            )
        }
    }

    private func systemCategoryOption(for raw: String, kind: CashflowCategoryKind) -> CashflowCategoryOption? {
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

    private func systemCategoryOptions(for kind: CashflowCategoryKind) -> [CashflowCategoryOption] {
        switch kind {
        case .income:
            return IncomeCategory.allCases.map {
                CashflowCategoryOption(
                    rawValue: $0.rawValue,
                    displayName: $0.displayName,
                    icon: $0.icon,
                    isCustom: false
                )
            }
        case .expense:
            return ExpenseCategory.allCases.map {
                CashflowCategoryOption(
                    rawValue: $0.rawValue,
                    displayName: $0.displayName,
                    icon: $0.icon,
                    isCustom: false
                )
            }
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
}
