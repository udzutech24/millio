//
//  FinanceDynamicsViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Finance Dynamics State

struct FinanceDynamicsState {
    /// Выбранные группы для отображения (пусто = все группы)
    var selectedGroupIDs: Set<String> = []
    
    /// Выбранные счета для отображения (пусто = все счета выбранных групп)
    var selectedAccountIDs: Set<String> = []
    
    /// Валюта для отображения
    var displayCurrency: String = "RUB"
    
    /// Доступные валюты
    var availableCurrencies: [String] = []
    
    /// Период отображения
    var period: DynamicsPeriod = .week
    
    /// Кастомный период (если period == .custom)
    var customPeriod: (start: Date, end: Date)? = nil
    
    /// Данные для графика
    var chartData: [ChartDataPoint] = []
    
    /// Флаг загрузки данных
    var isLoading: Bool = false
    
    /// Все группы
    var groups: [FinanceGroup] = []
    
    /// Все доступные карты
    var availableCards: [Card] = []
    
    /// Все доступные кредиты
    var availableCredits: [Credit] = []
    
    /// Все доступные инвестиции
    var availableInvestments: [Investment] = []
    
    /// Режим просмотра одной группы (скрывает фильтры групп)
    var isSingleGroupMode: Bool = false
    
    /// Режим просмотра одного счета (скрывает фильтры групп и счетов)
    var isSingleAccountMode: Bool = false
    
    /// Все транзакции Cashflow для расчета динамики балансов
    var cashflowTransactions: [CashflowTransaction] = []
    
    // MARK: - Новые поля для переделанного экрана
    
    /// Выбранная дата на графике (nil = live значение)
    var selectedDate: Date? = nil
    
    /// Текущее значение баланса (из выбранной точки или live)
    var currentBalance: Double = 0.0
    
    /// Дельта за период (абсолютная и процентная)
    var periodDelta: (absolute: Double, percent: Double) = (0.0, 0.0)
    
    /// Начало периода
    var periodStartDate: Date = Date()
    
    /// Конец периода
    var periodEndDate: Date = Date()
    
    /// Режим отображения графика
    var dynamicsMode: DynamicsMode = .aggregated
    
    /// Данные для списка динамики
    var dynamicsBreakdown: [DynamicsBreakdownItem] = []

    /// Данные для графика распределения по валютам
    var currencyBreakdown: [CurrencyBreakdownItem] = []
    
    /// Режим просмотра списка (группы/счета)
    var viewMode: DynamicsViewMode = .groups
    
    /// Показывать ли sheet с фильтром
    var showFilterSheet: Bool = false
    
    /// Показывать ли sheet с выбором периода
    var showPeriodSelector: Bool = false

    /// Показывать ли архивные счета в динамике
    var showArchivedAccounts: Bool = false

    /// Предупреждение о конвертации валют в истории
    var currencyConversionWarning: String? = nil

    /// Тип отображаемого графика
    var selectedChartType: ChartViewType = .line
}

// MARK: - Dynamics Period

enum DynamicsPeriod: String, CaseIterable {
    case day = "1D"
    case week = "1W"
    case month = "1M"
    case year = "1Y"
    case all = "All"
    case custom = "Custom"
    
    var days: Int? {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .year: return 365
        case .all: return nil
        case .custom: return nil
        }
    }
}

// MARK: - Chart Data Point

struct ChartDataPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String
    
    static func == (lhs: ChartDataPoint, rhs: ChartDataPoint) -> Bool {
        lhs.id == rhs.id && lhs.date == rhs.date && lhs.value == rhs.value
    }
}

// MARK: - Dynamics Mode

enum DynamicsMode: Equatable {
    case aggregated // Все счета в одну линию
    case byAccounts // Каждый счет - отдельная линия
    case singleAccount(String) // Один выбранный счет (accountUniqueID)
}

// MARK: - Dynamics View Mode

enum DynamicsViewMode {
    case groups
    case accounts
}

// MARK: - Chart View Type

enum ChartViewType {
    case line
    case distribution
    case currencyDistribution
}

// MARK: - Dynamics Breakdown Item

struct DynamicsBreakdownItem: Identifiable {
    let id: String
    let name: String
    let startValue: Double
    let endValue: Double
    let delta: Double
    let deltaPercent: Double
    let icon: String?
    let accountType: FinanceAccountType?
    let isCreditCard: Bool
    let isArchived: Bool
}

// MARK: - Currency Breakdown Item

struct CurrencyBreakdownItem: Identifiable {
    let id: String          // код валюты
    let currency: String    // код валюты
    let convertedValue: Double  // сумма в валюте отображения
    let percentage: Double      // % от общего (0–100)
}

// MARK: - Finance Dynamics Actions

enum FinanceDynamicsAction {
    case loadData
    case selectGroups(Set<String>)
    case selectAccounts(Set<String>)
    case setDisplayCurrency(String)
    case setPeriod(DynamicsPeriod)
    case setCustomPeriod(start: Date, end: Date)
    case toggleGroup(String)
    case toggleAccount(String)
    case selectDateOnChart(Date?)
    case setDynamicsMode(DynamicsMode)
    case setViewMode(DynamicsViewMode)
    case showFilterSheet
    case hideFilterSheet
    case selectAllGroups
    case deselectAllGroups
    case selectAllAccounts
    case deselectAllAccounts
    case showPeriodSelector
    case hidePeriodSelector
    case setShowArchivedAccounts(Bool)
    case setChartViewType(ChartViewType)
}

// MARK: - Finance Dynamics ViewModel

@MainActor
final class FinanceDynamicsViewModel: ViewModelProtocol {
    typealias State = FinanceDynamicsState
    typealias Action = FinanceDynamicsAction
    /// Balance-scope contract for selecting finance accounts by calculation intent.
    typealias BalanceScope = FinanceBalanceScope
    
    @Published var state = FinanceDynamicsState()
    
    let modelContext: ModelContext
    let financeViewModel: FinanceViewModel
    let currencyService: CurrencyRateServiceProtocol
    private let historicalRateStore: HistoricalRateStore
    let defaults = UserDefaults.standard
    private var eventSubscriptionID: UUID?
    private var selectionUpdateTask: Task<Void, Never>?
    private var backgroundTasks: [UUID: Task<Void, Never>] = [:]
    private var chartUpdateRevision: Int = 0
    
    // Кэши для оптимизации производительности
    var cardsCache: [String: Card] = [:]
    var creditsCache: [String: Credit] = [:]
    var investmentsCache: [String: Investment] = [:]
    var transactionsByCardCache: [String: [CashflowTransaction]] = [:]
    var transactionsByCreditCache: [String: [CashflowTransaction]] = [:]
    var transactionsByInvestmentCache: [String: [CashflowTransaction]] = [:]
    var initialBalancesCache: [String: Double] = [:]
    var balanceCache: [String: Double] = [:] // Кэш для calculateBalanceAtDate: "accountID_date" -> balance
    
    init(
        modelContext: ModelContext,
        financeViewModel: FinanceViewModel,
        initialGroupID: String? = nil,
        initialGroupCurrency: String? = nil,
        initialAccountID: String? = nil,
        initialAccountCurrency: String? = nil,
        currencyService: CurrencyRateServiceProtocol
    ) {
        self.modelContext = modelContext
        self.financeViewModel = financeViewModel
        self.currencyService = currencyService
        self.historicalRateStore = HistoricalRateStore(modelContext: modelContext, currencyService: currencyService)
        
        // Если передан initialAccountID, устанавливаем его как выбранный счет и включаем режим одного счета
        if let accountID = initialAccountID {
            state.selectedAccountIDs = [accountID]
            state.isSingleAccountMode = true
            state.isSingleGroupMode = true // В режиме одного счета также скрываем фильтры групп
            state.dynamicsMode = .singleAccount(accountID)
            state.viewMode = .accounts
        } else if let groupID = initialGroupID {
            // Если передан initialGroupID, устанавливаем его как выбранную группу и включаем режим одной группы
            state.selectedGroupIDs = [groupID]
            state.isSingleGroupMode = true
            state.dynamicsMode = .aggregated
        }
        
        // Если у группы или счета есть своя валюта, используем её, иначе используем общую валюту
        if let accountCurrency = initialAccountCurrency {
            state.displayCurrency = accountCurrency
        } else if let groupCurrency = initialGroupCurrency {
            state.displayCurrency = groupCurrency
        } else {
            state.displayCurrency = financeViewModel.state.displayCurrency
        }
        
        // Устанавливаем период по умолчанию
        if state.period == .custom && state.customPeriod == nil {
            state.period = .month
        }
        
        subscribeToEvents()
    }

    convenience init(
        modelContext: ModelContext,
        financeViewModel: FinanceViewModel,
        initialGroupID: String? = nil,
        initialGroupCurrency: String? = nil,
        initialAccountID: String? = nil,
        initialAccountCurrency: String? = nil
    ) {
        self.init(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            initialGroupID: initialGroupID,
            initialGroupCurrency: initialGroupCurrency,
            initialAccountID: initialAccountID,
            initialAccountCurrency: initialAccountCurrency,
            currencyService: CurrencyRateService.shared
        )
    }
    
    deinit {
        MainActor.assumeIsolated {
            selectionUpdateTask?.cancel()
            cancelBackgroundTasks()
            if let id = eventSubscriptionID {
                EventBus.shared.unsubscribe(id)
            }
        }
    }

    private func scheduleBackgroundTask(_ operation: @escaping @MainActor (FinanceDynamicsViewModel) async -> Void) {
        let taskID = UUID()
        backgroundTasks[taskID] = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            await operation(self)
            self.finishBackgroundTask(taskID)
        }
    }

    private func finishBackgroundTask(_ taskID: UUID) {
        backgroundTasks.removeValue(forKey: taskID)
    }

    private func cancelBackgroundTasks() {
        let tasks = backgroundTasks.values
        backgroundTasks.removeAll()
        for task in tasks {
            task.cancel()
        }
    }

    private func nextChartUpdateRevision() -> Int {
        chartUpdateRevision += 1
        return chartUpdateRevision
    }

    private func isCurrentChartUpdateRevision(_ revision: Int) -> Bool {
        revision == chartUpdateRevision && !Task.isCancelled
    }
    
    private func subscribeToEvents() {
        eventSubscriptionID = EventBus.shared.subscribe { [weak self] event in
            guard let self else { return }
            switch event {
            case FinanceEvent.cardsUpdated,
                 FinanceEvent.investmentsUpdated,
                 FinanceEvent.creditsUpdated,
                 FinanceEvent.transactionsUpdated,
                 FinanceEvent.auditSnapshotsUpdated:
                self.loadData()
            case BackupEvent.restoreCompleted:
                self.loadData()
            default:
                break
            }
        }
    }
    
    func handle(_ action: FinanceDynamicsAction) {
        switch action {
        case .loadData:
            loadData()
            
        case .selectGroups(let groupIDs):
            // В режиме одной группы или одного счета запрещаем изменение групп
            if !state.isSingleGroupMode && !state.isSingleAccountMode {
                state.selectedGroupIDs = groupIDs
                state.selectedAccountIDs = [] // Сбрасываем выбор счетов при изменении групп
                updateChartData()
            }
            
        case .selectAccounts(let accountIDs):
            // В режиме одного счета запрещаем изменение счетов
            if !state.isSingleAccountMode {
                state.selectedAccountIDs = accountIDs
                updateChartData()
            }
            
        case .setDisplayCurrency(let currency):
            let normalizedNewCurrency = normalizedConversionCurrency(currency)
            let normalizedCurrentCurrency = normalizedConversionCurrency(state.displayCurrency)
            state.displayCurrency = currency
            if normalizedNewCurrency != normalizedCurrentCurrency {
                balanceCache.removeAll()
            }
            updateChartData()
            
        case .setPeriod(let period):
            state.period = period
            if period != .custom {
                state.customPeriod = nil
            }
            updateChartData()
            
        case .setCustomPeriod(let start, let end):
            state.period = .custom
            state.customPeriod = normalizedCustomPeriod(start: start, end: end)
            updateChartData()
            
        case .selectDateOnChart(let date):
            state.selectedDate = date
            selectionUpdateTask?.cancel()
            let selectedDateSnapshot = date
            selectionUpdateTask = Task(priority: .userInitiated) { [weak self] in
                guard let self else { return }
                await self.updateCurrentBalanceAndDelta(for: selectedDateSnapshot)
            }
            
        case .setDynamicsMode(let mode):
            state.dynamicsMode = mode
            updateChartData()
            
        case .setViewMode(let mode):
            state.viewMode = mode
            scheduleBackgroundTask { viewModel in
                await viewModel.updateCurrentBalanceAndDelta()
                await viewModel.updateDynamicsBreakdown()
            }
            
        case .showFilterSheet:
            state.showFilterSheet = true
            
        case .hideFilterSheet:
            state.showFilterSheet = false
            
        case .showPeriodSelector:
            state.showPeriodSelector = true
            
        case .hidePeriodSelector:
            state.showPeriodSelector = false

        case .setShowArchivedAccounts(let isOn):
            state.showArchivedAccounts = isOn
            updateChartData()

        case .setChartViewType(let type):
            state.selectedChartType = type
            
        case .selectAllGroups:
            state.selectedGroupIDs = Set(state.groups.map { $0.groupUniqueID })
            state.selectedAccountIDs = [] // Сбрасываем выбор счетов
            updateChartData()
            
        case .deselectAllGroups:
            state.selectedGroupIDs = []
            state.selectedAccountIDs = [] // Сбрасываем выбор счетов
            updateChartData()
            
        case .selectAllAccounts:
            let accounts = self.getAccountsForSelectedGroups()
            state.selectedAccountIDs = Set(accounts.map { $0.accountUniqueID })
            // Автоматически переключаем режим
            if state.selectedAccountIDs.count == 1 {
                if let accountID = state.selectedAccountIDs.first {
                    state.dynamicsMode = .singleAccount(accountID)
                } else {
                    state.dynamicsMode = .aggregated
                }
            } else {
                // Для нескольких счетов всегда используем агрегированный режим
                state.dynamicsMode = .aggregated
            }
            updateChartData()
            
        case .deselectAllAccounts:
            state.selectedAccountIDs = []
            state.dynamicsMode = .aggregated
            updateChartData()
            
        case .toggleGroup(let groupID):
            // В режиме одной группы или одного счета запрещаем изменение групп
            if !state.isSingleGroupMode && !state.isSingleAccountMode {
                if state.selectedGroupIDs.contains(groupID) {
                    state.selectedGroupIDs.remove(groupID)
                } else {
                    state.selectedGroupIDs.insert(groupID)
                }
                state.selectedAccountIDs = [] // Сбрасываем выбор счетов
                updateChartData()
            }
            
        case .toggleAccount(let accountID):
            // В режиме одного счета запрещаем изменение счетов
            if !state.isSingleAccountMode {
                if state.selectedAccountIDs.contains(accountID) {
                    state.selectedAccountIDs.remove(accountID)
                } else {
                    state.selectedAccountIDs.insert(accountID)
                }
                // Автоматически переключаем режим
                if state.selectedAccountIDs.count == 1 {
                    if let accountID = state.selectedAccountIDs.first {
                        state.dynamicsMode = .singleAccount(accountID)
                    } else {
                        state.dynamicsMode = .aggregated
                    }
                } else {
                    // Для нескольких счетов всегда используем агрегированный режим
                    state.dynamicsMode = .aggregated
                }
                updateChartData()
            }
        }
    }
    
    func loadData() {
        state.isLoading = true
        
        // При прямом открытии экрана динамики financeViewModel может еще не успеть загрузить state.
        // В этом случае читаем группы напрямую из SwiftData, чтобы breakdown не оставался пустым.
        state.groups = loadGroupsSnapshot()
        
        // Загружаем карты, кредиты и инвестиции напрямую из базы данных,
        // чтобы всегда получать актуальные данные (включая обновленные балансы)
        let cardDescriptor = FetchDescriptor<Card>()
        state.availableCards = (try? modelContext.fetch(cardDescriptor)) ?? []
        
        let creditDescriptor = FetchDescriptor<Credit>()
        state.availableCredits = (try? modelContext.fetch(creditDescriptor)) ?? []
        
        let investmentDescriptor = FetchDescriptor<Investment>()
        state.availableInvestments = (try? modelContext.fetch(investmentDescriptor)) ?? []
        
        // Создаем словари для быстрого поиска (O(1) вместо O(n))
        rebuildCaches()
        
        // Загружаем транзакции Cashflow для расчета динамики балансов
        loadCashflowTransactions()
        
        // Загружаем доступные валюты
        loadAvailableCurrencies()
        
        // Обновляем данные графика
        updateChartData()
        
        state.isLoading = false
    }

    private func loadGroupsSnapshot(forceStoreFetch: Bool = false) -> [FinanceGroup] {
        let currentGroups = financeViewModel.state.groups
        if !forceStoreFetch, !currentGroups.isEmpty {
            return currentGroups
        }

        return fetchGroupsFromStore()
    }

    private func fetchGroupsFromStore() -> [FinanceGroup] {
        let descriptor = FetchDescriptor<FinanceGroup>()
        let ungroupedName = FinanceSystemGroups.ungroupedName
        let groups = (try? modelContext.fetch(descriptor)) ?? []
        return groups
            .sorted { group1, group2 in
                if group1.order != group2.order {
                    return group1.order < group2.order
                }
                return group1.createdAt < group2.createdAt
            }
            .filter { group in
                guard group.name == ungroupedName else { return true }
                return !(group.accounts?.isEmpty ?? true)
            }
    }

    private func reloadChartDataDependencies() {
        state.groups = fetchGroupsFromStore()

        let cardDescriptor = FetchDescriptor<Card>()
        state.availableCards = (try? modelContext.fetch(cardDescriptor)) ?? []

        let creditDescriptor = FetchDescriptor<Credit>()
        state.availableCredits = (try? modelContext.fetch(creditDescriptor)) ?? []

        let investmentDescriptor = FetchDescriptor<Investment>()
        state.availableInvestments = (try? modelContext.fetch(investmentDescriptor)) ?? []

        rebuildCaches()
        loadCashflowTransactions()
    }

    private func fetchAccountsSnapshot() -> [FinanceAccount] {
        let descriptor = FetchDescriptor<FinanceAccount>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fallbackAccountsForCalculation(scope: BalanceScope = .currentVisible) -> [FinanceAccount] {
        let groupsByID = Dictionary(uniqueKeysWithValues: state.groups.map { ($0.groupUniqueID, $0) })
        let selectedGroupIDs = state.selectedGroupIDs
        let selectedAccountIDs = state.selectedAccountIDs

        let accounts = fetchAccountsSnapshot().filter { account in
            if !selectedGroupIDs.isEmpty {
                guard let group = account.group else { return false }
                if groupsByID[group.groupUniqueID] == nil || !selectedGroupIDs.contains(group.groupUniqueID) {
                    return false
                }
            }

            if !selectedAccountIDs.isEmpty && !selectedAccountIDs.contains(account.accountUniqueID) {
                return false
            }

            return true
        }

        if shouldIncludeArchivedAccounts(for: scope) {
            return accounts
        }

        return accounts.filter { !isAccountArchived($0) }
    }

    private func shouldIncludeArchivedAccounts(for scope: BalanceScope) -> Bool {
        switch scope {
        case .currentVisible:
            return state.showArchivedAccounts
        case .historicalAsOf, .historicalInterval, .dashboardSnapshot, .cashflowContribution:
            return true
        }
    }
    
    /// Перестроить кэши для оптимизации производительности
    func rebuildCaches() {
        // Кэш карт
        cardsCache = Dictionary(state.availableCards.map { ($0.cardUniqueID, $0) }, uniquingKeysWith: { first, _ in first })
        
        // Кэш кредитов
        creditsCache = Dictionary(state.availableCredits.map { ($0.creditUniqueID, $0) }, uniquingKeysWith: { first, _ in first })
        
        // Кэш инвестиций
        investmentsCache = Dictionary(state.availableInvestments.map { ($0.investmentUniqueID, $0) }, uniquingKeysWith: { first, _ in first })
        
        // Очищаем кэши балансов при перезагрузке данных
        initialBalancesCache.removeAll()
        balanceCache.removeAll()
        transactionsByCardCache.removeAll()
        transactionsByCreditCache.removeAll()
        transactionsByInvestmentCache.removeAll()
    }
    
    func loadCashflowTransactions() {
        let descriptor = FetchDescriptor<CashflowTransaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .forward)]
        )
        if let transactions = try? modelContext.fetch(descriptor) {
            state.cashflowTransactions = transactions
            // Предфильтруем транзакции по картам для оптимизации
            rebuildTransactionsCache()
        }
    }
    
    /// Предфильтровать транзакции по картам, кредитам и инвестициям для быстрого доступа
    func rebuildTransactionsCache() {
        transactionsByCardCache.removeAll()
        transactionsByCreditCache.removeAll()
        transactionsByInvestmentCache.removeAll()
        for transaction in state.cashflowTransactions {
            if let cardID = transaction.cardID {
                transactionsByCardCache[cardID, default: []].append(transaction)
            }
            if let toCardID = transaction.toCardID {
                transactionsByCardCache[toCardID, default: []].append(transaction)
            }
            if let creditID = transaction.creditID {
                transactionsByCreditCache[creditID, default: []].append(transaction)
            }
            if let investmentID = transaction.investmentID {
                transactionsByInvestmentCache[investmentID, default: []].append(transaction)
            }
        }
    }
    
    func loadAvailableCurrencies() {
        scheduleBackgroundTask { viewModel in
            var extraCodes = Set<String>()
            for card in viewModel.state.availableCards {
                extraCodes.insert(card.currency)
            }
            for credit in viewModel.state.availableCredits {
                extraCodes.insert(credit.currency)
            }
            for investment in viewModel.state.availableInvestments {
                extraCodes.insert(investment.currency)
            }

            if Task.isCancelled { return }
            viewModel.state.availableCurrencies = CurrencySelectionSupport.pickerCodes(extraCodes: Array(extraCodes))
        }
    }
    
    func updateChartData() {
        state.currencyConversionWarning = nil
        let revision = nextChartUpdateRevision()
        scheduleBackgroundTask { viewModel in
            let prioritizeLiveSingleAccountState = viewModel.shouldPrioritizeLiveSingleAccountState
            if prioritizeLiveSingleAccountState {
                guard viewModel.isCurrentChartUpdateRevision(revision) else { return }
                await viewModel.updateCurrentBalanceAndDelta()
                guard viewModel.isCurrentChartUpdateRevision(revision) else { return }
                await viewModel.updateDynamicsBreakdown()
            }
            guard viewModel.isCurrentChartUpdateRevision(revision) else { return }
            await viewModel.prefetchHistoricalRatesForCurrentSelection()
            guard viewModel.isCurrentChartUpdateRevision(revision) else { return }
            await viewModel.updateChartDataAsync(expectedRevision: revision)
            if !prioritizeLiveSingleAccountState {
                guard viewModel.isCurrentChartUpdateRevision(revision) else { return }
                await viewModel.updateCurrentBalanceAndDelta()
                guard viewModel.isCurrentChartUpdateRevision(revision) else { return }
                await viewModel.updateDynamicsBreakdown()
            }
            guard viewModel.isCurrentChartUpdateRevision(revision) else { return }
            await viewModel.updateCurrencyBreakdown()
        }
    }

    private var shouldPrioritizeLiveSingleAccountState: Bool {
        state.isSingleAccountMode && state.selectedDate == nil
    }
    
    /// Получить даты периода
    func getPeriodDates() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate: Date
        
        if let customPeriod = state.customPeriod {
            return (customPeriod.start, customPeriod.end)
        }
        
        // Fallback для случая, когда period == .custom, но customPeriod == nil
        if state.period == .custom {
            // Возвращаем последние 30 дней как разумное значение по умолчанию
            let defaultStartDate = calendar.date(byAdding: .day, value: -30, to: endDate) ?? endDate
            return (defaultStartDate, endDate)
        }
        
        switch state.period {
        case .day, .week, .month, .year:
            if let days = state.period.days {
                startDate = calendar.date(byAdding: .day, value: -days, to: endDate) ?? endDate
            } else {
                startDate = endDate
            }
        case .all:
            // Для "All" берем самую раннюю дату создания счета или транзакции
            var earliestDate = endDate
            for group in state.groups {
                if let accounts = group.accounts {
                    for account in accounts {
                        if account.createdAt < earliestDate {
                            earliestDate = account.createdAt
                        }
                    }
                }
            }
            if let firstTransaction = state.cashflowTransactions.first {
                if firstTransaction.transactionDate < earliestDate {
                    earliestDate = firstTransaction.transactionDate
                }
            }
            startDate = earliestDate
        case .custom:
            // Этот кейс никогда не должен выполняться, так как он обработан выше через ранний возврат
            // Используем разумное значение по умолчанию на случай изменения логики
            startDate = calendar.date(byAdding: .day, value: -30, to: endDate) ?? endDate
        }
        
        return (startDate, endDate)
    }

    private func normalizedCustomPeriod(start: Date, end: Date, now: Date = Date()) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let startDate = min(start, end)
        let endDate = max(start, end)

        let normalizedStart = calendar.startOfDay(for: startDate)
        let endOfSelectedDay = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: endDate
        ) ?? endDate
        let normalizedEnd = min(endOfSelectedDay, now)

        let safeStart = min(normalizedStart, normalizedEnd)
        return (safeStart, normalizedEnd)
    }
    
    /// Обновить текущий баланс и дельту
    func updateCurrentBalanceAndDelta() async {
        await updateCurrentBalanceAndDelta(for: state.selectedDate)
    }

    /// Обновить текущий баланс и дельту для конкретной выбранной даты.
    /// Используется, чтобы избежать race condition при быстром выборе точек на графике.
    private func updateCurrentBalanceAndDelta(for selectedDate: Date?) async {
        if Task.isCancelled { return }

        let accounts = getAccountsForCalculation(scope: .currentVisible)
        // Период вычисляем по всем счетам (включая archived), чтобы диапазон не плыл при архивации.
        // Расчёты баланса/дельты ниже идут только по visible accounts.
        let accountsForPeriod = getAccountsForCalculation(scope: .historicalInterval(DateInterval(start: .distantPast, end: .distantFuture)))
        let (startDate, endDate) = resolvedPeriodDates(for: accountsForPeriod)
        state.periodStartDate = startDate
        state.periodEndDate = endDate

        let useNetTotals = shouldUseNetTotals()

        // Рассчитываем текущий баланс
        let targetDate: Date
        if let selectedDate {
            targetDate = Calendar.current.date(
                bySettingHour: 23,
                minute: 59,
                second: 59,
                of: selectedDate
            ) ?? selectedDate
        } else {
            targetDate = endDate
        }

        // Вклад ЯДРА в агрегат заголовка (6b Фаза 2, single-world): без скоуп-фильтров
        // (все счета, не режим одного счёта) заголовок «Динамика» обязан сходиться с агрегатом
        // Дашборда/«Счетов» (`AccountsTotalsService.totalAt`) — это закрывает R1 аудита 2026-07-02
        // (три пути тотала → один). Для легаси-данных вклад = 0 (нет core-счетов), поэтому
        // легаси-реплей не меняется. Скоупы (выбор групп/счетов, режим одного счёта) остаются на
        // легаси-пути до порта per-account Dynamics на ядро (задача «1b»/Фаза 4).
        let isUnscopedAggregate = state.selectedGroupIDs.isEmpty
            && state.selectedAccountIDs.isEmpty
            && !state.isSingleAccountMode
        let coreCurrent: Double = isUnscopedAggregate
            ? NSDecimalNumber(decimal: await financeViewModel.accountsTotalsService.totalAt(targetDate, in: state.displayCurrency)).doubleValue
            : 0
        let coreStart: Double = isUnscopedAggregate
            ? NSDecimalNumber(decimal: await financeViewModel.accountsTotalsService.totalAt(startDate, in: state.displayCurrency)).doubleValue
            : 0

        // Для single account без выбранной точки: используем live balance напрямую для всех типов,
        // кроме market-priced investments (stocks/crypto) — они идут через replay с рыночными ценами.
        if selectedDate == nil, accounts.count == 1, let account = accounts.first,
           let liveBalance = await liveConvertedBalance(
               for: account, displayCurrency: state.displayCurrency, at: targetDate
           ) {
            if Task.isCancelled { return }
            if selectedDate != state.selectedDate { return }
            state.currentBalance = liveBalance + coreCurrent
            let startBalance = await calculateBalanceAtDate(
                accounts: accounts,
                date: startDate,
                accountCardIDs: Set(),
                debtAsNegative: useNetTotals,
                includeInitialBeforeCreation: false
            ) + coreStart
            if Task.isCancelled { return }
            if selectedDate != state.selectedDate { return }
            let rawDelta = state.currentBalance - startBalance
            let delta = adjustDeltaForSingleAccountIfNeeded(
                delta: rawDelta, accounts: accounts, useNetTotals: useNetTotals
            )
            state.periodDelta = (delta, calculateDeltaPercent(delta: delta, startBalance: startBalance))
            return
        }

        let currentBalance = await calculateBalanceAtDate(
            accounts: accounts,
            date: targetDate,
            accountCardIDs: Set(accounts.compactMap { $0.accountType == .card ? $0.accountID : nil }),
            debtAsNegative: useNetTotals,
            includeInitialBeforeCreation: false
        ) + coreCurrent
        if Task.isCancelled { return }
        if selectedDate != state.selectedDate { return }
        state.currentBalance = currentBalance

        // Рассчитываем баланс на начало периода
        let startBalance = await calculateBalanceAtDate(
            accounts: accounts,
            date: startDate,
            accountCardIDs: Set(accounts.compactMap { $0.accountType == .card ? $0.accountID : nil }),
            debtAsNegative: useNetTotals,
            // Старт периода должен отражать фактическое состояние на эту дату.
            // Счет, созданный позже, не должен "задним числом" попадать в стартовый баланс.
            includeInitialBeforeCreation: false
        ) + coreStart
        if Task.isCancelled { return }
        if selectedDate != state.selectedDate { return }

        // Рассчитываем дельту
        let rawDelta = state.currentBalance - startBalance
        let delta = adjustDeltaForSingleAccountIfNeeded(
            delta: rawDelta,
            accounts: accounts,
            useNetTotals: useNetTotals
        )
        state.periodDelta = (delta, calculateDeltaPercent(delta: delta, startBalance: startBalance))
    }
    
    /// Получить счета для расчета под конкретный balance scope.
    func getAccountsForCalculation(scope: BalanceScope = .currentVisible) -> [FinanceAccount] {
        let groupsToShow = state.selectedGroupIDs.isEmpty
            ? state.groups
            : state.groups.filter { state.selectedGroupIDs.contains($0.groupUniqueID) }
        
        var accounts: [FinanceAccount] = []
        
        if state.isSingleAccountMode && !state.selectedAccountIDs.isEmpty {
            // Режим одного счета
            for group in state.groups {
                let groupAccounts = orderedAccounts(in: group)
                if !groupAccounts.isEmpty {
                    if let account = groupAccounts.first(where: { state.selectedAccountIDs.contains($0.accountUniqueID) }) {
                        accounts.append(account)
                        break
                    }
                }
            }
        } else {
            // Обычная логика
            for group in groupsToShow {
                let groupAccounts = orderedAccounts(in: group)
                guard !groupAccounts.isEmpty else {
                    // Пропускаем группы без счетов
                    continue
                }
                
                // Если выбраны конкретные счета, фильтруем по ним
                if !state.selectedAccountIDs.isEmpty {
                    let filteredAccounts = groupAccounts.filter {
                        state.selectedAccountIDs.contains($0.accountUniqueID)
                    }
                    // Если в группе выбрано 0 счетов - исключаем группу полностью
                    if filteredAccounts.isEmpty {
                        continue
                    }
                    accounts.append(contentsOf: filteredAccounts)
                } else {
                    // Если счета не выбраны, берем все счета группы
                    accounts.append(contentsOf: groupAccounts)
                }
            }
        }
        
        // Убираем дубликаты
        var seenIDs: Set<String> = []
        let uniqueAccounts = accounts.filter { account in
            if seenIDs.contains(account.accountUniqueID) {
                return false
            }
            seenIDs.insert(account.accountUniqueID)
            return true
        }
        
        let visibleAccounts: [FinanceAccount]
        if shouldIncludeArchivedAccounts(for: scope) {
            visibleAccounts = uniqueAccounts
        } else {
            visibleAccounts = uniqueAccounts.filter { !isAccountArchived($0) }
        }

        if !visibleAccounts.isEmpty {
            return visibleAccounts
        }

        // SwiftData relationships can be stale right after inserts/updates in tests and some
        // freshly-saved flows. Falling back to a direct account fetch keeps dynamics deterministic
        // instead of silently producing an empty chart.
        return fallbackAccountsForCalculation(scope: scope)
    }

    @available(*, deprecated, message: "Use getAccountsForCalculation(scope:) with FinanceBalanceScope.")
    func getAccountsForCalculation(includeArchivedForHistory: Bool) -> [FinanceAccount] {
        getAccountsForCalculation(
            scope: includeArchivedForHistory
                ? .historicalInterval(DateInterval(start: .distantPast, end: .distantFuture))
                : .currentVisible
        )
    }
    
    /// Обновить распределение по валютам
    func updateCurrencyBreakdown() async {
        let accounts = getAccountsForCalculation(scope: .currentVisible)
        let displayCurrency = state.displayCurrency
        let endDate = getPeriodDates().end

        // Используем FinanceNetWorthSignedAmount — единая логика знаков для net worth:
        // учитывает includeInTotal, archivedAt, кредитные карты (долг = limit - balance),
        // investmentType == .negative. Не дублируем эту логику вручную.
        var nativeTotals: [String: Double] = [:]
        for account in accounts {
            guard let signed = FinanceNetWorthSignedAmount.signedValue(
                for: account,
                cardsByID: cardsCache,
                creditsByID: creditsCache,
                investmentsByID: investmentsCache
            ) else { continue }

            let currency: String
            switch account.accountType {
            case .card:
                guard let card = cardsCache[account.accountID] else { continue }
                currency = card.currency
            case .credit:
                guard let credit = creditsCache[account.accountID] else { continue }
                currency = credit.currency
            case .investment:
                guard let inv = investmentsCache[account.accountID] else { continue }
                currency = inv.currency
            }
            nativeTotals[currency, default: 0] += signed
        }

        // Для сегодняшней даты CurrencyRateService.getHistoricalRate деградирует
        // в getRate() → cachedRates. Форсируем обновление чтобы курс был актуальным.
        // Для исторических периодов (at: endDate != today) Frankfurter отработает штатно.
        await currencyService.forceRefreshRates()

        var converted: [(currency: String, value: Double)] = []
        for (currency, nativeValue) in nativeTotals {
            let value = await convertAmount(value: nativeValue, from: currency, to: displayCurrency, at: endDate)
            converted.append((currency: currency, value: value))
        }

        // Считаем total по положительным значениям
        let totalPositive = converted.filter { $0.value > 0 }.reduce(0) { $0 + $1.value }
        guard totalPositive > 0 else {
            state.currencyBreakdown = []
            return
        }

        let items = converted
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { entry in
                CurrencyBreakdownItem(
                    id: entry.currency,
                    currency: entry.currency,
                    convertedValue: entry.value,
                    percentage: entry.value / totalPositive * 100
                )
            }
        state.currencyBreakdown = items
    }

    /// Core-счета для ветки `.accounts` дашборда «Динамика»: каждый счёт — отдельная строка, суммы и
    /// дельта в валюте экрана через тот же `accountsTotalsService`, что и per-group суммы (Фаза 1.5).
    /// Уважает выбор групп (`selectedGroupIDs`); дедуп по `id`. Список короткий — считаем последовательно.
    private func coreAccountDynamicsItems(startDate: Date, endDate: Date) async -> [DynamicsBreakdownItem] {
        let groupsToShow = state.selectedGroupIDs.isEmpty
            ? state.groups
            : state.groups.filter { state.selectedGroupIDs.contains($0.groupUniqueID) }
        let currency = state.displayCurrency

        var seen: Set<UUID> = []
        var coreAccounts: [Account] = []
        for group in groupsToShow {
            for account in financeViewModel.newCoreAccounts(matching: group) where seen.insert(account.id).inserted {
                coreAccounts.append(account)
            }
        }
        guard !coreAccounts.isEmpty else { return [] }

        // Легаси-предшественники (реверс LegacyConversionRegistry): до миграции 6b core-двойника не
        // существовало, поэтому core.total(startDate)=0 и строка показывала Start=0 при живом графике
        // («по графику цифры были, а показывает 0»). Добавляем баланс легаси-двойника ТЕМ ЖЕ time-aware
        // движком, что рисует скелет графика (calculateBalanceAtDate: archived-счёт отдаёт реальный
        // баланс только для дат <= archivedAt, после миграции — 0). Итог per-account идентичен
        // комбинированному движку графика (легаси-скелет + core totalAt), поэтому и Total (сумма строк)
        // согласован с первой точкой серии. Двойного счёта нет: конвертированный легаси archived и в
        // .accounts-строки (scope .currentVisible) не попадает.
        // Ключ реестра — легаси `uniqueID` (== `FinanceAccount.accountID`), а не `accountUniqueID`.
        let legacyByUniqueID: [String: FinanceAccount] = Dictionary(
            getAccountsForCalculation(
                scope: .historicalInterval(DateInterval(start: .distantPast, end: .distantFuture))
            ).map { ($0.accountID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var items: [DynamicsBreakdownItem] = []
        for account in coreAccounts {
            var start = NSDecimalNumber(
                decimal: await financeViewModel.accountsTotalsService.total(for: [account], on: startDate, in: currency)
            ).doubleValue
            var end = NSDecimalNumber(
                decimal: await financeViewModel.accountsTotalsService.total(for: [account], on: endDate, in: currency)
            ).doubleValue
            if let legacyUniqueID = LegacyConversionRegistry.shared.legacyUniqueID(forCoreAccountID: account.id),
               let legacyAccount = legacyByUniqueID[legacyUniqueID] {
                let cardIDs: Set<String> = legacyAccount.accountType == .card ? [legacyAccount.accountID] : []
                start += await calculateBalanceAtDate(
                    accounts: [legacyAccount], date: startDate,
                    accountCardIDs: cardIDs, debtAsNegative: true, includeInitialBeforeCreation: false
                )
                end += await calculateBalanceAtDate(
                    accounts: [legacyAccount], date: endDate,
                    accountCardIDs: cardIDs, debtAsNegative: true, includeInitialBeforeCreation: false
                )
            }
            // Знак уже заложен в total (loan/debt отрицательны) — как в ветке .groups, дельту не переворачиваем.
            let delta = end - start
            items.append(DynamicsBreakdownItem(
                id: account.id.uuidString,
                name: account.name,
                startValue: start,
                endValue: end,
                delta: delta,
                deltaPercent: calculateDeltaPercent(delta: delta, startBalance: start),
                icon: account.kind.fallbackIconName,
                accountType: nil,
                isCreditCard: account.kind == .loan,
                isArchived: false
            ))
        }
        return items
    }

    /// Обновить список динамики
    func updateDynamicsBreakdown() async {
        let accounts = getAccountsForCalculation(scope: .currentVisible)
        let requestedPeriod = getPeriodDates()
        let startDate = requestedPeriod.start
        let endDate = requestedPeriod.end
        
        var breakdown: [DynamicsBreakdownItem] = []
        
        let viewMode = state.viewMode
        let selectedGroupIDs = state.selectedGroupIDs
        let selectedAccountIDs = state.selectedAccountIDs
        let groups = state.groups

        switch viewMode {
        case .groups:
            // Группируем по группам - вычисляем параллельно
            let groupsToShow = selectedGroupIDs.isEmpty
                ? groups
                : groups.filter { selectedGroupIDs.contains($0.groupUniqueID) }
            
            // Подготавливаем данные для групп до входа в TaskGroup
            let groupsData = await MainActor.run {
                groupsToShow.enumerated().compactMap { index, groupItem -> (Int, String, String, [String], [String], Bool)? in
                    let groupAccounts = self.getAccounts(for: groupItem)
                    let filteredAccounts = selectedAccountIDs.isEmpty
                        ? groupAccounts
                        : groupAccounts.filter { selectedAccountIDs.contains($0.accountUniqueID) }
                    // Счета нового ядра включаем, только когда НЕ фильтруем по конкретным легаси-счетам
                    // (у core нет legacy-`accountUniqueID`, выбор счетов — легаси-UI). Фаза 1.5: группа
                    // из одних core-счетов больше не выпадает из Groups breakdown (баг §1.3a).
                    let includeCore = selectedAccountIDs.isEmpty
                        && !self.financeViewModel.newCoreAccounts(matching: groupItem).isEmpty
                    if filteredAccounts.isEmpty && !includeCore { return nil }
                    let accountCardIDs = Set(filteredAccounts.compactMap { account -> String? in
                        if account.accountType == .card {
                            return account.accountID
                        }
                        return nil
                    })
                    return (
                        index,
                        groupItem.groupUniqueID,
                        groupItem.name,
                        filteredAccounts.map(\.accountUniqueID),
                        Array(accountCardIDs),
                        includeCore
                    )
                }
            }

            var orderedItems: [Int: DynamicsBreakdownItem] = [:]

            await withTaskGroup(of: (Int, DynamicsBreakdownItem?).self) { group in
                for (index, groupID, groupName, accountIDs, accountCardIDsArray, includeCore) in groupsData {
                    group.addTask { @MainActor in
                        guard let groupItem = self.state.groups.first(where: { $0.groupUniqueID == groupID }) else {
                            return (index, nil)
                        }

                        let filteredAccounts = self
                            .getAccounts(for: groupItem)
                            .filter { accountIDs.contains($0.accountUniqueID) }
                        // Core-счета группы (Фаза 1.5) — считаются, только если фильтр не по легаси-счетам.
                        let coreAccounts = includeCore
                            ? self.financeViewModel.newCoreAccounts(matching: groupItem)
                            : []
                        guard !filteredAccounts.isEmpty || !coreAccounts.isEmpty else {
                            return (index, nil)
                        }
                        let accountCardIDs = Set(accountCardIDsArray)
                        let targetCurrency = self.state.displayCurrency

                        async let startBalanceTask = self.calculateBalanceAtDate(
                            accounts: filteredAccounts,
                            date: startDate,
                            accountCardIDs: accountCardIDs,
                            debtAsNegative: true,
                            includeInitialBeforeCreation: false
                        )
                        async let endBalanceTask = self.calculateBalanceAtDate(
                            accounts: filteredAccounts,
                            date: endDate,
                            accountCardIDs: accountCardIDs,
                            debtAsNegative: true,
                            includeInitialBeforeCreation: false
                        )
                        // Вклад core-счетов в валюте экрана (та же, что у calculateBalanceAtDate) на обе даты.
                        async let coreStartTask = coreAccounts.isEmpty ? Decimal(0)
                            : self.financeViewModel.accountsTotalsService.total(for: coreAccounts, on: startDate, in: targetCurrency)
                        async let coreEndTask = coreAccounts.isEmpty ? Decimal(0)
                            : self.financeViewModel.accountsTotalsService.total(for: coreAccounts, on: endDate, in: targetCurrency)

                        let startBalance = await startBalanceTask + NSDecimalNumber(decimal: await coreStartTask).doubleValue
                        let endBalance = await endBalanceTask + NSDecimalNumber(decimal: await coreEndTask).doubleValue

                        // Для групп считаем чистый баланс (долги учитываем со знаком минус)
                        let delta = endBalance - startBalance
                        let percent = self.calculateDeltaPercent(delta: delta, startBalance: startBalance)

                        return (index, DynamicsBreakdownItem(
                            id: groupID,
                            name: groupName,
                            startValue: startBalance,
                            endValue: endBalance,
                            delta: delta,
                            deltaPercent: percent,
                            icon: nil,
                            accountType: nil,
                            isCreditCard: false,
                            isArchived: false
                        ))
                    }
                }

                for await (index, item) in group {
                    if let item {
                        orderedItems[index] = item
                    }
                }
            }

            breakdown = groupsData.compactMap { orderedItems[$0.0] }
            
        case .accounts:
            // Показываем каждый счет отдельно - вычисляем параллельно
            let accountsData = await MainActor.run {
                accounts.enumerated().compactMap { index, account -> (Int, String, String, String, Bool, Bool)? in
                    guard let accountInfo = self.getAccountInfoForDynamics(account: account) else {
                        return nil
                    }
                    let accountID = account.accountUniqueID
                    let accountCardID = account.accountID
                    let isCard = account.accountType == .card
                    let isArchived = self.isAccountArchived(account)
                    return (index, accountID, accountInfo.name, accountCardID, isCard, isArchived)
                }
            }

            var orderedItems: [Int: DynamicsBreakdownItem] = [:]

            await withTaskGroup(of: (Int, DynamicsBreakdownItem?).self) { group in
                for (index, accountUniqueID, accountName, accountCardID, isCard, isArchived) in accountsData {
                    group.addTask { @MainActor in
                        let accountCardIDs = isCard ? Set([accountCardID]) : Set<String>()

                        let currentAccounts = self.getAccountsForCalculation(scope: .currentVisible)
                        guard let account = currentAccounts.first(where: { $0.accountUniqueID == accountUniqueID }) else {
                            return (index, nil)
                        }

                        async let startBalanceTask = self.calculateBalanceAtDate(
                            accounts: [account],
                            date: startDate,
                            accountCardIDs: accountCardIDs,
                            debtAsNegative: false,
                            includeInitialBeforeCreation: false
                        )
                        async let endBalanceTask = self.calculateBalanceAtDate(
                            accounts: [account],
                            date: endDate,
                            accountCardIDs: accountCardIDs,
                            debtAsNegative: false,
                            includeInitialBeforeCreation: false
                        )
                        
                        let startBalance = await startBalanceTask
                        var endBalance = await endBalanceTask
                        // В single-account current view endpoint совпадает с live balance
                        if accounts.count == 1, self.state.selectedDate == nil,
                           let liveBalance = await self.liveConvertedBalance(
                               for: account, displayCurrency: self.state.displayCurrency, at: endDate
                           ) {
                            endBalance = liveBalance
                        }

                        let isCreditCard: Bool
                        let isCredit: Bool
                        if account.accountType == .card {
                            if let card = self.state.availableCards.first(where: { $0.cardUniqueID == account.accountID }) {
                                isCreditCard = card.cardType == .credit
                                isCredit = false
                            } else {
                                isCreditCard = false
                                isCredit = false
                            }
                        } else if account.accountType == .credit {
                            isCreditCard = false
                            isCredit = true
                        } else {
                            isCreditCard = false
                            isCredit = false
                        }

                        let rawDelta = endBalance - startBalance
                        let delta: Double
                        if isCreditCard || isCredit {
                            delta = -rawDelta
                        } else {
                            delta = rawDelta
                        }

                        let percent = self.calculateDeltaPercent(delta: delta, startBalance: startBalance)

                        guard let accountInfo = self.getAccountInfoForDynamics(account: account) else {
                            return (index, nil)
                        }

                        return (index, DynamicsBreakdownItem(
                            id: accountUniqueID,
                            name: accountName,
                            startValue: startBalance,
                            endValue: endBalance,
                            delta: delta,
                            deltaPercent: percent,
                            icon: accountInfo.icon,
                            accountType: account.accountType,
                            isCreditCard: isCreditCard,
                            isArchived: isArchived
                        ))
                    }
                }

                for await (index, item) in group {
                    if let item {
                        orderedItems[index] = item
                    }
                }
            }

            breakdown = accountsData.compactMap { orderedItems[$0.0] }

            // Core-счета отдельными строками — зеркально ветке .groups (:1084). Легаси-таблицы пусты
            // (Фаза 6b), поэтому без этого вкладка «Счета» показывает «No products» при живом тотале.
            // Фильтр по конкретным легаси-счетам отключает core — у ядра нет legacy-`accountUniqueID`.
            if selectedAccountIDs.isEmpty {
                breakdown.append(contentsOf: await coreAccountDynamicsItems(startDate: startDate, endDate: endDate))
            }
        }

        await MainActor.run {
            state.dynamicsBreakdown = breakdown
        }
    }
    
    func updateChartDataAsync(expectedRevision: Int? = nil) async {
        let revision = expectedRevision ?? nextChartUpdateRevision()
        guard isCurrentChartUpdateRevision(revision) else { return }

        var visibleAccounts = getAccountsForCalculation(scope: .currentVisible)
        if visibleAccounts.isEmpty {
            reloadChartDataDependencies()
            visibleAccounts = getAccountsForCalculation(scope: .currentVisible)
        }
        if visibleAccounts.isEmpty {
            visibleAccounts = fallbackAccountsForCalculation(scope: .currentVisible)
        }

        let allAccountsForPeriod = getAccountsForCalculation(
            scope: .historicalInterval(DateInterval(start: .distantPast, end: .distantFuture))
        )
        let period = resolvedPeriodDates(for: allAccountsForPeriod.isEmpty ? visibleAccounts : allAccountsForPeriod)
        guard isCurrentChartUpdateRevision(revision) else { return }
        state.periodStartDate = period.start
        state.periodEndDate = period.end

        var chartAccounts = getAccountsForCalculation(
            scope: .historicalInterval(DateInterval(start: period.start, end: period.end))
        )
        if chartAccounts.isEmpty {
            chartAccounts = fallbackAccountsForCalculation(
                scope: .historicalInterval(DateInterval(start: period.start, end: period.end))
            )
        }
        if chartAccounts.isEmpty {
            chartAccounts = visibleAccounts
        }
        
        // Строим данные графика в зависимости от режима
        let useNetTotals = shouldUseNetTotals()
        switch state.dynamicsMode {
        case .aggregated:
            // Все счета в одну линию
            let liveEndBalanceAggr: Double? = chartAccounts.count == 1
                && state.selectedDate == nil
                && !isAccountArchived(chartAccounts[0])
                ? await liveConvertedBalance(for: chartAccounts[0], displayCurrency: state.displayCurrency, at: period.end)
                : nil
            var chartData = await buildTimeSeriesData(
                accounts: chartAccounts,
                startDate: period.start,
                endDate: period.end,
                label: L("finances.dynamics.chart.total_label"),
                debtAsNegative: useNetTotals,
                liveEndBalance: liveEndBalanceAggr
            )
            // Вклад ядра event-sourcing (6b Фаза 2b, single-world) — только для агрегированного
            // "тотал-графика"; в byAccounts/singleAccount новые счета появятся в 1b вместе с
            // переносом их выбора в общий список счетов Dynamics. Снесён dual-path
            // (`mergingNewCoreSeries` + отдельный дневной `seriesBetween`-ряд с forward-fill
            // приближением): точный запрос ядра НА ТЕ ЖЕ даты легаси-скелета, без промежуточного
            // массива/эвристики совпадения дат.
            chartData = await addingCoreContribution(chartData, currency: state.displayCurrency)
            guard isCurrentChartUpdateRevision(revision) else { return }
            state.chartData = chartData

        case .byAccounts:
            // Каждый счет - отдельная линия
            var allDataPoints: [ChartDataPoint] = []
            for account in chartAccounts {
                let liveEndBalancePerAccount: Double? = chartAccounts.count == 1
                    && state.selectedDate == nil
                    && !isAccountArchived(account)
                    ? await liveConvertedBalance(for: account, displayCurrency: state.displayCurrency, at: period.end)
                    : nil
                let accountData = await buildTimeSeriesData(
                    accounts: [account],
                    startDate: period.start,
                    endDate: period.end,
                    label: getAccountInfoForDynamics(account: account)?.name ?? L("finances.dynamics.chart.account_fallback"),
                    debtAsNegative: false,
                    liveEndBalance: liveEndBalancePerAccount
                )
                allDataPoints.append(contentsOf: accountData)
            }
            guard isCurrentChartUpdateRevision(revision) else { return }
            state.chartData = allDataPoints

        case .singleAccount(let accountID):
            // Один выбранный счет
            if let account = chartAccounts.first(where: { $0.accountUniqueID == accountID }) {
                let liveEndBalanceSingle: Double? = state.selectedDate == nil && !isAccountArchived(account)
                    ? await liveConvertedBalance(for: account, displayCurrency: state.displayCurrency, at: period.end)
                    : nil
                let chartData = await buildTimeSeriesData(
                    accounts: [account],
                    startDate: period.start,
                    endDate: period.end,
                    label: getAccountInfoForDynamics(account: account)?.name ?? L("finances.dynamics.chart.account_fallback"),
                    debtAsNegative: false,
                    liveEndBalance: liveEndBalanceSingle
                )
                guard isCurrentChartUpdateRevision(revision) else { return }
                state.chartData = chartData
            } else {
                guard isCurrentChartUpdateRevision(revision) else { return }
                state.chartData = []
            }
        }
    }
    
    /// 6b Фаза 2b (single-world): добавляет вклад ядра event-sourcing в каждую точку легаси-
    /// скелета НА ТУ ЖЕ дату — точный запрос через `AccountsTotalsService.totalAt`, без
    /// промежуточного дневного ряда и forward-fill приближения (замена снесённому
    /// `ChartDataPoint.mergingNewCoreSeries`). Легаси-скелет (`points`, из `buildTimeSeriesData`)
    /// остаётся источником ДОмиграционной истории — он уже time-aware (архивные счета отдают
    /// реальный баланс только для дат `<= archivedAt`), поэтому на датах до миграции ядро
    /// добавляет 0 (двойника ещё нет), а после миграции легаси даёт 0 (скрыт) и добавляется
    /// ядро — итог идентичен прежнему dual-path, но без риска рассинхрона дат между двумя
    /// независимо построенными рядами. Известное MVP-ограничение (opening-balance датой
    /// миграции, искажение дельты на границе, см. план 6b §Ф2) не усугубляется и не устраняется —
    /// это тот же compromise, просто без лишнего слоя приближённого слияния.
    /// No-op на пустых `points` (нечего дополнять) — это тот же пробел «1b» (core-only счета ещё
    /// не участвуют в списке счетов Dynamics), не регрессия этой фазы.
    private func addingCoreContribution(_ points: [ChartDataPoint], currency: String) async -> [ChartDataPoint] {
        guard !points.isEmpty else { return points }
        var result: [ChartDataPoint] = []
        result.reserveCapacity(points.count)
        for point in points {
            let coreValue = await financeViewModel.accountsTotalsService.totalAt(point.date, in: currency)
            let addition = NSDecimalNumber(decimal: coreValue).doubleValue
            result.append(ChartDataPoint(date: point.date, value: point.value + addition, label: point.label))
        }
        return result
    }

    /// Построить временной ряд данных для графика
    func buildTimeSeriesData(
        accounts: [FinanceAccount],
        startDate: Date,
        endDate: Date,
        label: String,
        debtAsNegative: Bool = false,
        liveEndBalance: Double? = nil
    ) async -> [ChartDataPoint] {
        var dataPoints: [ChartDataPoint] = []
        let calendar = Calendar.current

        guard !accounts.isEmpty else { return [] }
        guard startDate <= endDate else { return [] }
        
        // ВАЖНО: даже если период укладывается в 1 день, график должен иметь минимум 2 точки (start/end),
        // иначе Charts не рисует линию (получается "пустой" график с осями).
        // Для этого всегда добавляем точки на начало и конец периода с расчетом баланса на эти даты.
        let accountCardIDs: Set<String> = Set(accounts.compactMap { account -> String? in
            guard account.accountType == .card else { return nil }
            return account.accountID
        })
        let startBalance = await calculateBalanceAtDate(
            accounts: accounts,
            date: startDate,
            accountCardIDs: accountCardIDs,
            debtAsNegative: debtAsNegative,
            includeInitialBeforeCreation: false
        )
        let endBalance = await calculateBalanceAtDate(
            accounts: accounts,
            date: endDate,
            accountCardIDs: accountCardIDs,
            debtAsNegative: debtAsNegative,
            includeInitialBeforeCreation: false
        )
        var allBalances: [Date: Double] = [
            startDate: startBalance,
            endDate: endBalance
        ]
        
        // Собираем все уникальные даты событий (создание/обновление счетов и транзакции)
        var eventDates: Set<Date> = [startDate, endDate]
        
        // Добавляем даты создания и обновления счетов
        for account in accounts {
            eventDates.insert(account.createdAt)
            eventDates.insert(account.updatedAt)
        }
        
        // Добавляем даты обновления самих карт/кредитов/инвестиций
        // Это важно для отслеживания ручных изменений баланса (быстрое редактирование)
        // accountCardIDs уже построен выше.
        
        // Добавляем даты обновления карт (используем кэш)
        for cardID in accountCardIDs {
            if let card = cardsCache[cardID] {
                eventDates.insert(card.createdAt)
                eventDates.insert(card.updatedAt) // Дата изменения баланса при быстром редактировании
            }
        }
        
        // Добавляем даты обновления кредитов (используем кэш)
        let accountCreditIDs = Set(accounts.compactMap { account -> String? in
            if account.accountType == .credit {
                return account.accountID
            }
            return nil
        })
        for creditID in accountCreditIDs {
            if let credit = creditsCache[creditID] {
                eventDates.insert(credit.createdAt)
                eventDates.insert(credit.updatedAt)
            }
        }
        
        // Добавляем даты обновления инвестиций (используем кэш)
        let accountInvestmentIDs = Set(accounts.compactMap { account -> String? in
            if account.accountType == .investment {
                return account.accountID
            }
            return nil
        })
        for investmentID in accountInvestmentIDs {
            if let investment = investmentsCache[investmentID] {
                eventDates.insert(investment.createdAt)
                eventDates.insert(investment.updatedAt)
            }
        }
        
        for transaction in state.cashflowTransactions {
            // Проверяем, влияет ли транзакция на выбранные счета
            var affectsAccount = false
            switch transaction.transactionType {
            case .income, .expense:
                if let cardID = transaction.cardID, accountCardIDs.contains(cardID) {
                    affectsAccount = true
                }
            case .transfer:
                if let fromCardID = transaction.cardID, accountCardIDs.contains(fromCardID) {
                    affectsAccount = true
                }
                if let toCardID = transaction.toCardID, accountCardIDs.contains(toCardID) {
                    affectsAccount = true
                }
            case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
                // Ручное изменение баланса/долга может быть для карт, кредитов или инвестиций
                if let cardID = transaction.cardID, accountCardIDs.contains(cardID) {
                    affectsAccount = true
                }
                if let creditID = transaction.creditID, accountCreditIDs.contains(creditID) {
                    affectsAccount = true
                }
                if let investmentID = transaction.investmentID, accountInvestmentIDs.contains(investmentID) {
                    affectsAccount = true
                }
            }
            
            if affectsAccount {
                eventDates.insert(transaction.transactionDate)
            }
        }
        
        // Разделяем даты на важные события (транзакции, обновления счетов) и промежуточные точки
        let importantDates = eventDates
            .filter { $0 >= startDate && $0 <= endDate }
            .sorted()
        
        // Создаем множество дней с важными событиями для проверки
        let importantDays = Set(importantDates.map { calendar.startOfDay(for: $0) })
        
        // Добавляем промежуточные точки для плавности графика
        // Но не добавляем их в дни, где уже есть важные события
        var intermediateDates: [Date] = []
        let periodDays = await MainActor.run { state.period.days }
        
        // Для коротких периодов используем ежедневные точки, для длинных - более плотную сетку для плавности
        let stepDays: Int
        if let days = periodDays {
            if days <= 30 {
                // Для месяца и меньше - ежедневные точки
                stepDays = 1
            } else if days <= 365 {
                // Для года - каждые 2 дня для более плавного графика
                stepDays = 2
            } else {
                // Для длинных периодов - каждые 5 дней для баланса между плавностью и производительностью
                stepDays = 5
            }
        } else {
            // Для "All" периода используем более плотную сетку (каждые 7 дней)
            let totalDays = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 365
            if totalDays <= 365 {
                stepDays = 2
            } else if totalDays <= 730 {
                stepDays = 5
            } else {
                stepDays = 7
            }
        }
        
        var currentDate = startDate
        while currentDate <= endDate {
            let dayStart = calendar.startOfDay(for: currentDate)
            // Добавляем промежуточную точку только если в этот день нет важных событий
            if !importantDays.contains(dayStart) {
                intermediateDates.append(currentDate)
            }
            currentDate = calendar.date(byAdding: .day, value: stepDays, to: currentDate) ?? endDate
        }
        
        // Рассчитываем баланс для каждого дня с важными событиями параллельно
        // Для каждого дня берем баланс на конец дня (после всех транзакций в этот день)
        var eventBalances: [Date: Double] = [:]
        await withTaskGroup(of: (Date, Double).self) { group in
            for dayStart in importantDays {
                group.addTask {
                    let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dayStart) ?? dayStart
                    // Для "текущего дня" конец дня может быть в будущем, поэтому клэмпим к endDate периода.
                    let evaluationDate = min(endOfDay, endDate)
                    let balance = await self.calculateBalanceAtDate(
                        accounts: accounts,
                        date: evaluationDate,
                        accountCardIDs: accountCardIDs,
                        debtAsNegative: debtAsNegative
                    )
                    return (evaluationDate, balance)
                }
            }
            
            for await (evaluationDate, balance) in group {
                eventBalances[evaluationDate] = balance
            }
        }
        
        // Рассчитываем баланс для промежуточных точек параллельно (группируем по дням)
        var intermediateBalances: [Date: Double] = [:]
        await withTaskGroup(of: (Date, Double).self) { group in
            for intermediateDate in intermediateDates {
                group.addTask {
                    let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: intermediateDate) ?? intermediateDate
                    let evaluationDate = min(endOfDay, endDate)
                    let balance = await self.calculateBalanceAtDate(
                        accounts: accounts,
                        date: evaluationDate,
                        accountCardIDs: accountCardIDs,
                        debtAsNegative: debtAsNegative
                    )
                    return (evaluationDate, balance)
                }
            }
            
            for await (evaluationDate, balance) in group {
                intermediateBalances[evaluationDate] = balance
            }
        }
        
        // Добавляем дополнительные промежуточные точки между важными событиями для плавности
        // Это помогает сгладить резкие скачки значений
        var additionalIntermediateDates: [Date] = []
        let sortedImportantDates = importantDates.sorted()
        
        for i in 0..<(sortedImportantDates.count - 1) {
            let startDate = sortedImportantDates[i]
            let endDate = sortedImportantDates[i + 1]
            let daysBetween = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            
            // Если между важными событиями больше 3 дней, добавляем промежуточные точки
            if daysBetween > 3 {
                let intermediateCount = min(3, daysBetween - 1) // Максимум 3 промежуточные точки
                for j in 1...intermediateCount {
                    if let intermediateDate = calendar.date(byAdding: .day, value: (daysBetween * j) / (intermediateCount + 1), to: startDate) {
                        let dayStart = calendar.startOfDay(for: intermediateDate)
                        if !importantDays.contains(dayStart) {
                            additionalIntermediateDates.append(intermediateDate)
                        }
                    }
                }
            }
        }
        
        // Рассчитываем баланс для дополнительных промежуточных точек
        var additionalBalances: [Date: Double] = [:]
        if !additionalIntermediateDates.isEmpty {
            await withTaskGroup(of: (Date, Double).self) { group in
                for intermediateDate in additionalIntermediateDates {
                    group.addTask {
                        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: intermediateDate) ?? intermediateDate
                        let evaluationDate = min(endOfDay, endDate)
                        let balance = await self.calculateBalanceAtDate(
                            accounts: accounts,
                            date: evaluationDate,
                            accountCardIDs: accountCardIDs,
                            debtAsNegative: debtAsNegative
                        )
                        return (evaluationDate, balance)
                    }
                }
                
                for await (evaluationDate, balance) in group {
                    additionalBalances[evaluationDate] = balance
                }
            }
        }
        
        // Объединяем все балансы (важные события имеют приоритет над промежуточными точками)
        allBalances.merge(intermediateBalances, uniquingKeysWith: { _, new in new })
        // Добавляем дополнительные промежуточные точки
        for (day, balance) in additionalBalances {
            allBalances[day] = balance
        }
        // Важные события перезаписывают все промежуточные точки
        for (day, balance) in eventBalances {
            allBalances[day] = balance
        }
        // Non-market single-account: endpoint графика совпадает с live balance
        if let liveEndBalance {
            allBalances[endDate] = liveEndBalance
        }

        // Преобразуем в массив ChartDataPoint, сортируя по дате
        for (date, balance) in allBalances.sorted(by: { $0.key < $1.key }) {
            dataPoints.append(ChartDataPoint(
                date: date,
                value: balance,
                label: label
            ))
        }
        
        return dataPoints
    }

    func resolvedPeriodDates(
        for accounts: [FinanceAccount],
        basePeriod: (start: Date, end: Date)? = nil
    ) -> (start: Date, end: Date) {
        let requestedPeriod = basePeriod ?? getPeriodDates()
        guard !accounts.isEmpty else { return requestedPeriod }

        let firstDataDate = earliestOverviewDate(
            for: accounts,
            referenceDate: requestedPeriod.end
        )

        // Не рисуем и не считаем "виртуальный ноль" до появления первого реального значения.
        let clampedStart = max(requestedPeriod.start, firstDataDate)
        return (min(clampedStart, requestedPeriod.end), requestedPeriod.end)
    }

    func buildOverviewEntries(
        granularity: FinanceOverviewGranularity,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) async -> [FinanceOverviewPeriodEntry] {
        let accounts = getAccountsForCalculation(scope: .dashboardSnapshot)
        guard !accounts.isEmpty else { return [] }

        let normalizedReferenceDate = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: referenceDate
        ) ?? referenceDate
        let firstDate = earliestOverviewDate(
            for: accounts,
            referenceDate: normalizedReferenceDate
        )
        let firstPeriodStart = FinanceOverviewChartBuilder.periodStart(
            for: firstDate,
            granularity: granularity,
            calendar: calendar
        )
        let currentPeriodStart = FinanceOverviewChartBuilder.periodStart(
            for: normalizedReferenceDate,
            granularity: granularity,
            calendar: calendar
        )

        var entries: [FinanceOverviewPeriodEntry] = []
        var cursor = firstPeriodStart
        while cursor <= currentPeriodStart {
            let nextStart = FinanceOverviewChartBuilder.offsetPeriod(
                cursor,
                by: 1,
                granularity: granularity,
                calendar: calendar
            )
            let periodEnd = min(
                normalizedReferenceDate,
                nextStart.addingTimeInterval(-1)
            )
            let periodStartBalanceDate = cursor.addingTimeInterval(-1)

            var debit: Double = 0
            var credit: Double = 0

            for account in accounts {
                let accountCardIDs = account.accountType == .card ? Set([account.accountID]) : Set<String>()
                let startBalance = await calculateBalanceAtDate(
                    accounts: [account],
                    date: periodStartBalanceDate,
                    accountCardIDs: accountCardIDs,
                    debtAsNegative: false,
                    includeInitialBeforeCreation: false
                )
                let endBalance = await calculateBalanceAtDate(
                    accounts: [account],
                    date: periodEnd,
                    accountCardIDs: accountCardIDs,
                    debtAsNegative: false,
                    includeInitialBeforeCreation: false
                )

                let rawDelta = endBalance - startBalance
                let adjustedDelta = isLiabilityAccount(account) ? -rawDelta : rawDelta
                if adjustedDelta > 0.01 {
                    debit += adjustedDelta
                } else if adjustedDelta < -0.01 {
                    credit += abs(adjustedDelta)
                }
            }

            entries.append(
                FinanceOverviewPeriodEntry(
                    id: cursor,
                    date: cursor,
                    debit: debit,
                    credit: credit
                )
            )

            if nextStart <= cursor {
                break
            }
            cursor = nextStart
        }

        return entries
    }
    
    /// Рассчитать баланс счетов на конкретную дату с учетом транзакций
    func calculateBalanceAtDate(
        accounts: [FinanceAccount],
        date: Date,
        accountCardIDs: Set<String>,
        debtAsNegative: Bool = false,
        includeInitialBeforeCreation: Bool = false
    ) async -> Double {
        // Проверяем кэш
        let sortedIDs = accounts.map { $0.accountUniqueID }.sorted()
        let idsHash = sortedIDs.joined().hashValue
        let displayCurrencyKey = normalizedConversionCurrency(state.displayCurrency)
        let cacheKey = "balance_\(idsHash)_\(date.timeIntervalSince1970)_\(displayCurrencyKey)_\(debtAsNegative ? "net" : "raw")_\(includeInitialBeforeCreation ? "init" : "strict")"
        if let cached = balanceCache[cacheKey] {
            return cached
        }
        
        var totalBalance: Double = 0.0
        
        for account in accounts {
            var accountBalance: Double = 0.0
            var accountCurrency: String = "RUB"
            var shouldInclude = false
            
            switch account.accountType {
            case .card:
                // Используем кэш вместо first(where:) для O(1) поиска
                guard let card = cardsCache[account.accountID] else {
                    continue
                }
                
                guard Self.isLegacyActiveInTotal(
                    includeInTotal: card.includeInTotal,
                    archivedAt: card.archivedAt,
                    at: date
                ) else {
                    continue
                }

                accountCurrency = card.currency
                shouldInclude = true
                
                // Кэшируем начальный баланс при создании карты
                // Начальный баланс - это значение, которое пользователь ввел при создании карты
                let initialBalanceKey = "initial_\(account.accountID)"
                var initialBalanceAtCreation: Double
                if let cached = initialBalancesCache[initialBalanceKey] {
                    initialBalanceAtCreation = cached
                } else {
                    initialBalanceAtCreation = await resolveCardInitialBalance(card: card, accountCurrency: accountCurrency)
                    // Кэшируем начальный баланс
                    initialBalancesCache[initialBalanceKey] = initialBalanceAtCreation
                }
                
                let cardTransactions = transactionsByCardCache[account.accountID] ?? []
                let effectiveCreationDate = cardTransactions
                    .map(\.transactionDate)
                    .min()
                    .map { min(card.createdAt, $0) } ?? card.createdAt

                // Определяем баланс на запрашиваемую дату
                var cardBalance: Double
                if date < effectiveCreationDate {
                    if includeInitialBeforeCreation {
                        // Если период начинается раньше создания, считаем старт с начального баланса
                        cardBalance = initialBalanceAtCreation
                    } else {
                        continue
                    }
                } else {
                    // Запрашиваемая дата после или в момент создания карты
                    // Начинаем с начального баланса при создании и применяем транзакции до запрашиваемой даты
                    cardBalance = initialBalanceAtCreation
                    
                    // Используем предфильтрованные транзакции из кэша вместо фильтрации всех транзакций
                    let transactionsUpToDate = cardTransactions
                        .filter { $0.transactionDate >= effectiveCreationDate && $0.transactionDate <= date }
                        .sorted(by: { $0.transactionDate < $1.transactionDate })
                    
                    for transaction in transactionsUpToDate {
                        switch transaction.transactionType {
                        case .income:
                            if transaction.affectsCardBalance,
                               transaction.cardID == account.accountID {
                                let converted = await convertTransactionAmount(
                                    transaction,
                                    to: accountCurrency
                                )
                                cardBalance += converted
                            }
                            
                        case .expense:
                            if transaction.affectsCardBalance,
                               transaction.cardID == account.accountID {
                                let converted = await convertTransactionAmount(
                                    transaction,
                                    to: accountCurrency
                                )
                                cardBalance = max(0, cardBalance - converted)
                            }
                            
                        case .transfer:
                            if transaction.cardID == account.accountID {
                                let converted = await convertTransactionAmount(
                                    transaction,
                                    to: accountCurrency
                                )
                                cardBalance = max(0, cardBalance - converted)
                            } else if transaction.toCardID == account.accountID {
                                let converted = await convertTransactionAmount(
                                    transaction,
                                    to: accountCurrency
                                )
                                cardBalance += converted
                            }
                            
                        case .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
                            // Применяем изменение баланса/долга: положительное = увеличение баланса, отрицательное = уменьшение
                            // Для кредитных карт это меняет доступный баланс (debt = limit - balance)
                            if transaction.cardID == account.accountID {
                                let converted = await convertTransactionAmount(
                                    transaction,
                                    to: accountCurrency
                                )
                                cardBalance += converted
                            }
                        }
                    }
                }
                
                // Для кредитных карт преобразуем баланс в задолженность
                if card.cardType == .credit, let limit = card.creditLimit {
                    // Задолженность = лимит - баланс
                    accountBalance = max(0, limit - cardBalance)
                } else {
                    // Для дебетовых карт используем баланс
                    accountBalance = cardBalance
                }

                // Reconcile live state for card-based accounts.
                // История по Cashflow может быть неполной (например, прямое редактирование баланса
                // без создания balanceAdjustment), поэтому для дат не раньше последнего обновления
                // счета синхронизируемся с фактическим текущим значением модели.
                let lastTrackedCardChangeDate = cardTransactions
                    .map(\.transactionDate)
                    .max() ?? card.createdAt
                // IMPORTANT:
                // `card.balance` is the *current* model value, not necessarily the historical balance for `date`.
                // We can only safely "snap" to the live model state starting from the last moment we know
                // that value was in effect (e.g. after a manual edit of balance that didn't create a
                // balanceAdjustment transaction). Otherwise we erase history for earlier periods.
                let liveStateEffectiveDate = max(lastTrackedCardChangeDate, card.updatedAt)
                // Допуск 1 с для sub-second race: updatedAt может опередить targetDate
                // на несколько миллисекунд при одновременном сохранении и запросе.
                if date.addingTimeInterval(1) >= liveStateEffectiveDate {
                    let actualCurrentValue: Double
                    if card.cardType == .credit, let limit = card.creditLimit {
                        actualCurrentValue = max(0, limit - card.balance)
                    } else {
                        actualCurrentValue = card.balance
                    }
                    let deltaToActual = actualCurrentValue - accountBalance
                    if abs(deltaToActual) > 0.01 {
                        accountBalance += deltaToActual
                    }
                }
                
            case .credit:
                // Используем кэш вместо first(where:) для O(1) поиска
                guard let credit = creditsCache[account.accountID] else {
                    continue
                }
                
                guard Self.isLegacyActiveInTotal(
                    includeInTotal: credit.includeInTotal,
                    archivedAt: credit.archivedAt,
                    at: date
                ) else {
                    continue
                }

                accountCurrency = credit.currency
                shouldInclude = true

                let creditTransactions = transactionsByCreditCache[credit.creditUniqueID] ?? []
                let effectiveCreationDate = creditTransactions
                    .map(\.transactionDate)
                    .min()
                    .map { min(credit.createdAt, $0) } ?? credit.createdAt

                if date < effectiveCreationDate {
                    if includeInitialBeforeCreation {
                        if shouldInclude {
                            let converted = await convertAmount(
                                value: credit.initialRemainingAmount,
                                from: accountCurrency,
                                to: state.displayCurrency,
                                at: date
                            )
                            totalBalance += Self.signedLegacyContribution(
                                converted,
                                isLiability: isLiabilityAccount(account),
                                debtAsNegative: debtAsNegative
                            )
                        }
                    }
                    continue
                }
                
                // Рассчитываем остаток долга на нужную дату с учетом транзакций корректировки
                accountBalance = await calculateCreditRemainingAmount(
                    credit: credit,
                    at: date,
                    accountCurrency: accountCurrency
                )
                
            case .investment:
                // Используем кэш вместо first(where:) для O(1) поиска
                guard let investment = investmentsCache[account.accountID] else {
                    continue
                }
                
                guard Self.isLegacyActiveInTotal(
                    includeInTotal: investment.includeInTotal,
                    archivedAt: investment.archivedAt,
                    at: date
                ) else {
                    continue
                }

                accountCurrency = resolvedInvestmentCurrency(investment)
                shouldInclude = true
                let investmentSign = investment.investmentType == .positive ? 1.0 : -1.0
                
                // Для рыночных активов baseline должен опираться на cost basis, если legacy initialAmount
                // оказался записан как 0. Иначе динамика начинает путь с нуля и рисует ложный +inf.
                var baseAmount = baselineAmountForInvestment(investment)
                let investmentTransactions = transactionsByInvestmentCache[investment.investmentUniqueID] ?? []
                if !investment.hasInitialAmount {
                    var totalDelta: Double = 0.0
                    for transaction in investmentTransactions where transaction.transactionType == .balanceAdjustment &&
                        transaction.investmentID == investment.investmentUniqueID {
                        let converted = await convertTransactionAmount(
                            transaction,
                            to: accountCurrency
                        )
                        totalDelta += converted
                    }
                    baseAmount = investment.amount - totalDelta
                }
                
                var investmentBalance = investmentSign * baseAmount
                
                if date < investment.createdAt {
                    if includeInitialBeforeCreation {
                        accountBalance = investmentBalance
                    } else {
                        continue
                    }
                } else {
                    // Применяем транзакции balanceAdjustment с датой <= запрашиваемой даты
                    let balanceAdjustmentTransactions = investmentTransactions
                        .filter { transaction in
                            transaction.transactionType == .balanceAdjustment &&
                            transaction.investmentID == investment.investmentUniqueID &&
                            transaction.transactionDate <= date
                        }
                        .sorted(by: { $0.transactionDate < $1.transactionDate })

                    if investment.isMarketPriced {
                        investmentBalance = await reconstructMarketInvestmentBalance(
                            investment: investment,
                            accountCurrency: accountCurrency,
                            baseAmount: baseAmount,
                            allTransactions: investmentTransactions,
                            relevantTransactions: balanceAdjustmentTransactions,
                            signedFallbackBalance: investmentBalance,
                            date: date
                        )
                    } else {
                        for transaction in balanceAdjustmentTransactions {
                            let converted = await convertTransactionAmount(
                                transaction,
                                to: accountCurrency
                            )
                            investmentBalance += converted
                        }
                    }

                    // Если история неполная (например, для рыночных активов при изменении цены/количества
                    // без создания balanceAdjustment), фиксируем актуальное значение на дату последнего обновления.
                    let actualSignedAmount = investment.investmentType == .positive ? investment.amount : -investment.amount
                    let lastTrackedInvestmentChangeDate = balanceAdjustmentTransactions
                        .map(\.transactionDate)
                        .max() ?? investment.createdAt
                    let liveStateEffectiveDate = max(lastTrackedInvestmentChangeDate, investment.updatedAt)
                    // Допуск 1 с для sub-second race: updatedAt может опередить targetDate
                    // на несколько миллисекунд при одновременном сохранении и запросе.
                    if date.addingTimeInterval(1) >= liveStateEffectiveDate {
                        let deltaToActual = actualSignedAmount - investmentBalance
                        if abs(deltaToActual) > 0.01 {
                            investmentBalance += deltaToActual
                        }
                    }
                    
                    accountBalance = investmentBalance
                }
            }

            if shouldInclude {
                // Конвертируем в валюту отображения
                let converted = await convertAmount(
                    value: accountBalance,
                    from: accountCurrency,
                    to: state.displayCurrency,
                    at: date
                )
                totalBalance += Self.signedLegacyContribution(
                    converted,
                    isLiability: isLiabilityAccount(account),
                    debtAsNegative: debtAsNegative
                )
            }
        }

        // Сохраняем результат в кэш (ограничиваем размер кэша для экономии памяти)
        if balanceCache.count < 1000 {
            balanceCache[cacheKey] = totalBalance
        }

        return totalBalance
    }

    private func reconstructMarketInvestmentBalance(
        investment: Investment,
        accountCurrency: String,
        baseAmount: Double,
        allTransactions: [CashflowTransaction],
        relevantTransactions: [CashflowTransaction],
        signedFallbackBalance: Double,
        date: Date
    ) async -> Double {
        let balanceAdjustmentTransactions = allTransactions
            .filter { transaction in
                transaction.transactionType == .balanceAdjustment &&
                transaction.investmentID == investment.investmentUniqueID
            }
            .sorted(by: { $0.transactionDate < $1.transactionDate })

        guard !balanceAdjustmentTransactions.isEmpty else {
            return signedFallbackBalance
        }

        let sign = investment.investmentType == .positive ? 1.0 : -1.0
        var unsignedBalance = baseAmount

        if let firstTransaction = balanceAdjustmentTransactions.first,
           date < firstTransaction.transactionDate,
           let amountBefore = firstTransaction.assetAmountBefore {
            return sign * amountBefore
        }

        for transaction in relevantTransactions {
            if let amountAfter = transaction.assetAmountAfter {
                unsignedBalance = amountAfter
                continue
            }

            let converted = await convertTransactionAmount(
                transaction,
                to: accountCurrency
            )
            unsignedBalance += converted
        }

        return sign * unsignedBalance
    }

    private func shouldUseNetTotals() -> Bool {
        if case .singleAccount = state.dynamicsMode {
            return false
        }
        return true
    }

    private func isLiabilityAccount(_ account: FinanceAccount) -> Bool {
        switch account.accountType {
        case .credit:
            return true
        case .card:
            return cardsCache[account.accountID]?.cardType == .credit
        case .investment:
            return false
        }
    }

    // MARK: - Участие легаси-счёта на дату (инлайн бывшего AccountTotalPolicy, снесён в 6b Фазе 2)

    /// Включён флагом И не архивирован строго до `date` (time-aware: точки истории ДО архивации
    /// по-прежнему включают счёт). Легаси-реплей `calculateBalanceAtDate` остаётся до сноса легаси.
    private static func isLegacyActiveInTotal(includeInTotal: Bool, archivedAt: Date?, at date: Date) -> Bool {
        guard includeInTotal else { return false }
        if let archivedAt, date > archivedAt { return false }
        return true
    }

    /// Знак обязательства для net-вклада; при `debtAsNegative == false` — величина как есть.
    private static func signedLegacyContribution(_ amount: Double, isLiability: Bool, debtAsNegative: Bool) -> Double {
        guard debtAsNegative, isLiability else { return amount }
        return -abs(amount)
    }

    private func adjustDeltaForSingleAccountIfNeeded(
        delta: Double,
        accounts: [FinanceAccount],
        useNetTotals: Bool
    ) -> Double {
        guard !useNetTotals, accounts.count == 1 else { return delta }
        return isLiabilityAccount(accounts[0]) ? -delta : delta
    }

    private func calculateDeltaPercent(delta: Double, startBalance: Double) -> Double {
        if abs(startBalance) < 0.01 {
            if abs(delta) < 0.01 {
                return 0.0
            }
            return delta > 0 ? 999999.0 : -999999.0
        }
        return (delta / abs(startBalance)) * 100
    }

    private func resolveCardInitialBalance(card: Card, accountCurrency: String) async -> Double {
        if card.hasInitialBalance {
            return card.initialBalance
        }
        
        // Восстанавливаем базу, чтобы ручные правки не "сдвигали" историю
        let cardTransactions = transactionsByCardCache[card.cardUniqueID] ?? []
        var totalAdjustments: Double = 0.0
            for transaction in cardTransactions where
            (transaction.transactionType == .balanceAdjustment ||
             transaction.transactionType == .cardBalanceAdjustment ||
             transaction.transactionType == .creditDebtAdjustment) &&
            transaction.cardID == card.cardUniqueID {
            let converted = await convertTransactionAmount(
                transaction,
                to: accountCurrency
            )
            totalAdjustments += converted
        }
        return card.balance - totalAdjustments
    }

    private func baselineAmountForInvestment(_ investment: Investment) -> Double {
        let calendar = Calendar.current
        let endOfCreationDay = calendar.date(
            bySettingHour: 23,
            minute: 59,
            second: 59,
            of: investment.createdAt
        ) ?? investment.createdAt

        if investment.hasInitialAmount {
            if abs(investment.initialAmount) >= 0.01 {
                return investment.initialAmount
            }

            if investment.isMarketPriced,
               investment.updatedAt <= endOfCreationDay,
               abs(investment.amount) >= 0.01 {
                return investment.amount
            }

            if investment.isMarketPriced,
               let purchaseCost = investment.totalPurchaseCost,
               purchaseCost > 0 {
                return purchaseCost
            }

            return investment.initialAmount
        }

        if investment.isMarketPriced,
           investment.updatedAt <= endOfCreationDay,
           abs(investment.amount) >= 0.01 {
            return investment.amount
        }

        if investment.isMarketPriced,
           let purchaseCost = investment.totalPurchaseCost,
           purchaseCost > 0 {
            return purchaseCost
        }

        return investment.amount
    }
    
    /// Рассчитать остаток долга по кредиту на конкретную дату с учетом транзакций корректировки
    func calculateCreditRemainingAmount(credit: Credit, at date: Date, accountCurrency: String) async -> Double {
        let creditTransactions = transactionsByCreditCache[credit.creditUniqueID] ?? []
        // Базовый остаток (фиксируем, чтобы ручные правки не сдвигали историю)
        var baseAmount: Double
        if credit.hasInitialRemainingAmount {
            baseAmount = credit.initialRemainingAmount
        } else {
            var totalAdjustments: Double = 0.0
            for transaction in creditTransactions where
                (transaction.transactionType == .balanceAdjustment ||
                 transaction.transactionType == .creditDebtAdjustment) &&
                transaction.creditID == credit.creditUniqueID {
                let converted = await convertTransactionAmount(
                    transaction,
                    to: accountCurrency
                )
                totalAdjustments += converted
            }
            baseAmount = credit.remainingAmount - totalAdjustments
        }
        
        // Применяем транзакции корректировки с датой <= запрашиваемой даты
        let balanceAdjustmentTransactions = creditTransactions
            .filter { transaction in
                (transaction.transactionType == .balanceAdjustment ||
                 transaction.transactionType == .creditDebtAdjustment) &&
                transaction.creditID == credit.creditUniqueID &&
                transaction.transactionDate <= date
            }
            .sorted(by: { $0.transactionDate < $1.transactionDate })
        
        var remainingAmount = baseAmount
        for transaction in balanceAdjustmentTransactions {
            let converted = await convertTransactionAmount(
                transaction,
                to: accountCurrency
            )
            remainingAmount = max(0, remainingAmount - converted)
        }

        // Если итог расходится с текущим остатком, фиксируем актуальное значение
        // на дату последнего изменения (legacy/ручные правки без полной истории транзакций).
        let lastTrackedCreditChangeDate = balanceAdjustmentTransactions
            .map(\.transactionDate)
            .max() ?? credit.createdAt
        let liveStateEffectiveDate = max(lastTrackedCreditChangeDate, credit.updatedAt)
        if date >= liveStateEffectiveDate {
            let deltaToActual = credit.remainingAmount - remainingAmount
            if abs(deltaToActual) > 0.01 {
                remainingAmount = max(0, remainingAmount + deltaToActual)
            }
        }
        
        return remainingAmount
    }
    
    func getAccountInfoForDynamics(account: FinanceAccount) -> (name: String, amount: Double, currency: String, icon: String, isCreditCardDebt: Bool)? {
        switch account.accountType {
        case .card:
            if let card = resolvedCard(for: account.accountID) {
                if card.cardType == .credit, let limit = card.creditLimit {
                    let amount = max(0, limit - card.balance)
                    return (card.name, amount, card.currency, card.cardType.icon, true)
                }
                return (card.name, card.balance, card.currency, card.cardType.icon, false)
            }
        case .credit:
            if let credit = resolvedCredit(for: account.accountID) {
                return (credit.name, credit.remainingAmount, credit.currency, credit.creditType.icon, false)
            }
        case .investment:
            if let investment = resolvedInvestment(for: account.accountID) {
                return (
                    financeViewModel.investmentDisplayName(investment),
                    investment.amount,
                    resolvedInvestmentCurrency(investment),
                    investment.category.icon,
                    false
                )
            }
        }
        
        return nil
    }

    /// Актуальная информация для current-mode UI.
    /// Главный список и quick edit читают данные из FinanceViewModel, поэтому detail-экран
    /// использует тот же источник для live endpoint, а локальные dynamics-кэши оставляет
    /// для исторического replay и независимой загрузки графика.
    func getLiveAccountInfoForDynamics(account: FinanceAccount) -> (name: String, amount: Double, currency: String, icon: String, isCreditCardDebt: Bool)? {
        financeViewModel.getAccountInfo(account: account) ?? getAccountInfoForDynamics(account: account)
    }

    /// Живой баланс счёта, конвертированный в displayCurrency.
    /// Для market-priced investments (stocks/crypto) возвращает nil — нужен replay с рыночными ценами.
    private func liveConvertedBalance(
        for account: FinanceAccount,
        displayCurrency: String,
        at date: Date
    ) async -> Double? {
        let isMarketPriced = account.accountType == .investment
            && (investmentsCache[account.accountID]?.isMarketPriced == true)
        guard !isMarketPriced, let info = getLiveAccountInfoForDynamics(account: account) else { return nil }
        var amount = info.amount
        if account.accountType == .investment,
           investmentsCache[account.accountID]?.investmentType == .negative {
            amount = -amount
        }
        return await convertAmount(value: amount, from: info.currency, to: displayCurrency, at: date)
    }

    private func resolvedCard(for id: String) -> Card? {
        if let cached = cardsCache[id] {
            return cached
        }

        let descriptor = FetchDescriptor<Card>()
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        if let card = fetched.first(where: { $0.cardUniqueID == id }) {
            cardsCache[id] = card
            return card
        }
        return nil
    }

    private func resolvedCredit(for id: String) -> Credit? {
        if let cached = creditsCache[id] {
            return cached
        }

        let descriptor = FetchDescriptor<Credit>()
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        if let credit = fetched.first(where: { $0.creditUniqueID == id }) {
            creditsCache[id] = credit
            return credit
        }
        return nil
    }

    private func resolvedInvestment(for id: String) -> Investment? {
        if let cached = investmentsCache[id] {
            return cached
        }

        let descriptor = FetchDescriptor<Investment>()
        let fetched = (try? modelContext.fetch(descriptor)) ?? []
        if let investment = fetched.first(where: { $0.investmentUniqueID == id }) {
            investmentsCache[id] = investment
            return investment
        }
        return nil
    }
    
    func convertAmount(value: Double, from: String, to: String, at date: Date? = nil) async -> Double {
        let normalizedFrom = normalizedConversionCurrency(from)
        let normalizedTo = normalizedConversionCurrency(to)

        if normalizedFrom == normalizedTo {
            return value
        }
        
        if let date = date {
            let result = await historicalRateStore.getRate(on: date, from: normalizedFrom, to: normalizedTo)
            if result.resolution != .exact {
                if state.currencyConversionWarning == nil {
                    state.currencyConversionWarning = L("finances.dynamics.warning.estimated_rate")
                }
            }
            if let rate = result.rate {
                return value * rate
            }
        }
        
        if let converted = await currencyService.convert(
            amount: value,
            from: normalizedFrom,
            to: normalizedTo
        ) {
            if state.currencyConversionWarning == nil {
                state.currencyConversionWarning = L("finances.dynamics.warning.estimated_rate")
            }
            return converted
        }
        
        return value
    }

    private func convertTransactionAmount(_ transaction: CashflowTransaction, to targetCurrency: String) async -> Double {
        let normalizedTarget = normalizedConversionCurrency(targetCurrency)
        let normalizedSource = normalizedConversionCurrency(transaction.currency)

        if normalizedSource == normalizedTarget {
            return transaction.amount
        }

        if let frozenRate = transaction.exchangeRate,
           frozenRate > 0,
           let frozenCurrency = transaction.exchangeRateCurrency {
            let normalizedFrozenCurrency = normalizedConversionCurrency(frozenCurrency)
            if normalizedFrozenCurrency == normalizedTarget {
                return transaction.amount * frozenRate
            }
        }

        return await convertAmount(
            value: transaction.amount,
            from: transaction.currency,
            to: targetCurrency,
            at: transaction.transactionDate
        )
    }

    private func normalizedConversionCurrency(_ currency: String) -> String {
        let trimmed = currency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !trimmed.isEmpty else { return "USD" }

        let stablecoinToUSD: Set<String> = ["USDT", "USDC", "BUSD", "TUSD", "FDUSD", "DAI"]
        if stablecoinToUSD.contains(trimmed) {
            return "USD"
        }

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/").map(String.init)
            if let quote = parts.last {
                return normalizedConversionCurrency(quote)
            }
        }

        if trimmed.contains("-") {
            let parts = trimmed.split(separator: "-").map(String.init)
            if let quote = parts.last {
                return normalizedConversionCurrency(quote)
            }
        }

        return trimmed
    }

    private func prefetchHistoricalRatesForCurrentSelection() async {
        let displayCurrency = normalizedConversionCurrency(state.displayCurrency)

        var sourceCurrencies: Set<String> = []
        for card in state.availableCards {
            let currency = normalizedConversionCurrency(card.currency)
            if currency != displayCurrency {
                sourceCurrencies.insert(currency)
            }
        }
        for credit in state.availableCredits {
            let currency = normalizedConversionCurrency(credit.currency)
            if currency != displayCurrency {
                sourceCurrencies.insert(currency)
            }
        }
        for investment in state.availableInvestments {
            let currency = normalizedConversionCurrency(resolvedInvestmentCurrency(investment))
            if currency != displayCurrency {
                sourceCurrencies.insert(currency)
            }
        }
        guard !sourceCurrencies.isEmpty else { return }

        let accounts = getAccountsForCalculation(
            scope: .historicalInterval(DateInterval(start: .distantPast, end: .distantFuture))
        )
        let (startDate, endDate) = resolvedPeriodDates(for: accounts)
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let days = max(0, calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0)
        let step = max(1, days / 90)

        var dates: [Date] = [startDay, endDay]
        if days > 0 {
            var offset = 0
            while offset <= days {
                if let date = calendar.date(byAdding: .day, value: offset, to: startDay) {
                    dates.append(date)
                }
                offset += step
            }
        }

        let pairs = sourceCurrencies.map { (from: $0, to: displayCurrency) }
        await historicalRateStore.prefetchExactRates(on: Array(Set(dates)), pairs: pairs)
    }

    private func resolvedInvestmentCurrency(_ investment: Investment) -> String {
        let normalizedCurrency = investment.currency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !normalizedCurrency.isEmpty {
            return normalizedCurrency
        }

        if let marketCurrency = investment.marketCurrency?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
           !marketCurrency.isEmpty {
            return marketCurrency
        }

        return "USD"
    }

    private func earliestOverviewDate(
        for accounts: [FinanceAccount],
        referenceDate: Date
    ) -> Date {
        var earliestDate = referenceDate

        for account in accounts {
            earliestDate = min(earliestDate, account.createdAt)

            switch account.accountType {
            case .card:
                if let card = cardsCache[account.accountID] {
                    earliestDate = min(earliestDate, card.createdAt)
                }
            case .credit:
                if let credit = creditsCache[account.accountID] {
                    earliestDate = min(earliestDate, credit.createdAt)
                }
            case .investment:
                if let investment = investmentsCache[account.accountID] {
                    earliestDate = min(earliestDate, investment.createdAt)
                }
            }
        }

        for transaction in state.cashflowTransactions {
            if affectsOverviewSelection(transaction: transaction, accounts: accounts) {
                earliestDate = min(earliestDate, transaction.transactionDate)
            }
        }

        return earliestDate
    }

    private func affectsOverviewSelection(
        transaction: CashflowTransaction,
        accounts: [FinanceAccount]
    ) -> Bool {
        let cardIDs = Set(accounts.filter { $0.accountType == .card }.map(\.accountID))
        let creditIDs = Set(accounts.filter { $0.accountType == .credit }.map(\.accountID))
        let investmentIDs = Set(accounts.filter { $0.accountType == .investment }.map(\.accountID))

        if let cardID = transaction.cardID, cardIDs.contains(cardID) {
            return true
        }
        if let toCardID = transaction.toCardID, cardIDs.contains(toCardID) {
            return true
        }
        if let creditID = transaction.creditID, creditIDs.contains(creditID) {
            return true
        }
        if let investmentID = transaction.investmentID, investmentIDs.contains(investmentID) {
            return true
        }

        return false
    }

    /// Получить список счетов для выбранных групп
    func getAccountsForSelectedGroups() -> [FinanceAccount] {
        let groupsToShow = state.selectedGroupIDs.isEmpty
            ? state.groups
            : state.groups.filter { state.selectedGroupIDs.contains($0.groupUniqueID) }
        
        var accounts: [FinanceAccount] = []
        for group in groupsToShow {
            accounts.append(contentsOf: orderedAccounts(in: group))
        }
        
        guard state.showArchivedAccounts == false else {
            return accounts
        }
        
        return accounts.filter { !isAccountArchived($0) }
    }

    /// Получить список счетов внутри группы (с учетом архива)
    func getAccounts(for group: FinanceGroup) -> [FinanceAccount] {
        let groupAccounts = orderedAccounts(in: group)
        if state.showArchivedAccounts {
            return groupAccounts
        }
        return groupAccounts.filter { !isAccountArchived($0) }
    }

    private func orderedAccounts(in group: FinanceGroup) -> [FinanceAccount] {
        let accounts = hydratedAccounts(in: group)
        if group.usesManualAccountOrdering {
            return accounts.sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.createdAt < rhs.createdAt
            }
        }

        return accounts.sorted { lhs, rhs in
            let lhsAmount = getAccountInfoForDynamics(account: lhs)?.amount ?? 0
            let rhsAmount = getAccountInfoForDynamics(account: rhs)?.amount ?? 0
            if lhsAmount != rhsAmount {
                return lhsAmount > rhsAmount
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func hydratedAccounts(in group: FinanceGroup) -> [FinanceAccount] {
        let relationAccounts = group.accounts ?? []
        if !relationAccounts.isEmpty {
            return relationAccounts
        }

        // SwiftData relations are occasionally stale right after test/setup inserts.
        // Fall back to the store so chart building never silently collapses to zero accounts.
        let descriptor = FetchDescriptor<FinanceAccount>()
        let fetchedAccounts = (try? modelContext.fetch(descriptor)) ?? []
        return fetchedAccounts.filter { account in
            account.group?.persistentModelID == group.persistentModelID
                || account.group?.groupUniqueID == group.groupUniqueID
        }
    }

    private func isAccountArchived(_ account: FinanceAccount) -> Bool {
        switch account.accountType {
        case .card:
            return cardsCache[account.accountID]?.archivedAt != nil
        case .credit:
            return creditsCache[account.accountID]?.archivedAt != nil
        case .investment:
            return investmentsCache[account.accountID]?.archivedAt != nil
        }
    }
}
