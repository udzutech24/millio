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

// MARK: - Dynamics Series

/// Итог одного построения агрегированной серии «Динамики» (Ф2 dynamics-single-source-of-truth):
/// точки графика. Точка = легаси-реплей + вклад ядра, суммарно, в валюте экрана. Заголовок-дельта
/// и карточка «Общая сумма» — чистые функции от `points` (первая/последняя точка), а не три
/// независимых калькулятора над одними данными.
struct DynamicsSeries {
    let points: [ChartDataPoint]
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
    private(set) var historicalPortfolioSeries: HistoricalPortfolioSeriesResult?
    private(set) var historicalShadowDeltaBucket: HistoricalPortfolioShadowDeltaBucket?
    private let historicalReaderMode: HistoricalPortfolioReaderMode
    private lazy var legacyHistoricalValuator = LegacyHistoricalValuator(
        modelContext: modelContext,
        currencyService: currencyService,
        onEstimatedConversion: { [weak self] in
            guard let self, self.state.currencyConversionWarning == nil else { return }
            self.state.currencyConversionWarning = L("finances.dynamics.warning.estimated_rate")
        }
    )
    
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
        currencyService: CurrencyRateServiceProtocol,
        historicalReaderMode: HistoricalPortfolioReaderMode? = nil
    ) {
        self.modelContext = modelContext
        self.financeViewModel = financeViewModel
        self.currencyService = currencyService
        self.historicalReaderMode = historicalReaderMode
            ?? HistoricalPortfolioReaderConfiguration.current(defaults: UserDefaults.standard).mode
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
        legacyHistoricalValuator.reload()
        
        // Загружаем доступные валюты
        loadAvailableCurrencies()
        
        // Обновляем данные графика
        updateChartData()
        
        state.isLoading = false
    }

    /// [Ф5c.7 contract] `financeViewModel.state.groups` теперь `[AccountGroup]` (core primary) —
    /// FDVM легаси-группы (per-account chart-modes, вне скоупа этого гейта) читаются НАПРЯМУЮ, без
    /// быстрого пути через FVM-кэш (был микро-оптимизацией, не семантикой). `forceStoreFetch` больше
    /// не влияет на путь — оставлен в сигнатуре ради совместимости вызывающих.
    private func loadGroupsSnapshot(forceStoreFetch: Bool = false) -> [FinanceGroup] {
        fetchGroupsFromStore()
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
        legacyHistoricalValuator.reload()
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
    
    /// Unscoped-агрегат: нет фильтра по группам/счетам и не режим одного счёта. Только в этом режиме
    /// заголовок, карточка «Общая сумма» и график обязаны сходиться на концах единой серии (AC1);
    /// scoped-режимы остаются на легаси per-account пути до порта «1b».
    var isUnscopedAggregate: Bool {
        state.selectedGroupIDs.isEmpty
            && state.selectedAccountIDs.isEmpty
            && !state.isSingleAccountMode
    }

    /// Карточка «Общая сумма» для unscoped-агрегата = концы единой серии (заголовок), а НЕ повторный
    /// reduce по breakdown — единый источник числа закрывает расхождение заголовок/карточка (AC1).
    /// В режиме выбранной точки (scrub) и в scoped-режимах возвращает nil → карточка считается по
    /// breakdown, как раньше.
    func aggregateTotalRow() -> DynamicsBreakdownItem? {
        guard isUnscopedAggregate, state.selectedDate == nil else { return nil }
        let endValue = state.currentBalance
        let delta = state.periodDelta.absolute
        let startValue = endValue - delta
        return DynamicsBreakdownItem(
            id: "total",
            name: L("finances.dynamics.chart.total_label"),
            startValue: startValue,
            endValue: endValue,
            delta: delta,
            deltaPercent: state.periodDelta.percent,
            icon: nil,
            accountType: nil,
            isCreditCard: false,
            isArchived: false
        )
    }

    /// Обновить текущий баланс и дельту
    func updateCurrentBalanceAndDelta() async {
        await updateCurrentBalanceAndDelta(for: state.selectedDate)
    }

    /// Обновить текущий баланс и дельту для конкретной выбранной даты.
    /// Используется, чтобы избежать race condition при быстром выборе точек на графике.
    private func updateCurrentBalanceAndDelta(for selectedDate: Date?) async {
        if Task.isCancelled { return }

        // Structured readers select the already-valued point. No replay, FX lookup or live total is
        // allowed after the series bundle exists. Shadow deliberately keeps current pixels.
        if historicalReaderMode != .shadow {
            guard let series = historicalPortfolioSeries else {
                state.currencyConversionWarning = L("finances.dynamics.warning.history_incomplete")
                return
            }
            let first = series.points.first
            let selected = selectedDate.flatMap { series.point(nearestTo: $0) } ?? series.points.last
            if let startTotal = first?.valuation.total,
               let selectedTotal = selected?.valuation.total {
                let start = NSDecimalNumber(decimal: startTotal).doubleValue
                let current = NSDecimalNumber(decimal: selectedTotal).doubleValue
                state.currentBalance = current
                let delta = current - start
                state.periodDelta = (delta, calculateDeltaPercent(delta: delta, startBalance: start))
                state.currencyConversionWarning = nil
            } else {
                // Preserve the last visibly labelled value. A diagnostic subtotal or synthetic zero
                // would be mathematically false; no legacy replay is allowed as a hidden fallback.
                state.currencyConversionWarning = L("finances.dynamics.warning.history_incomplete")
            }
            return
        }

        // Период вычисляем по всем счетам (включая archived), чтобы диапазон не плыл при архивации.
        let accountsForPeriod = getAccountsForCalculation(scope: .historicalInterval(DateInterval(start: .distantPast, end: .distantFuture)))
        let (startDate, endDate) = resolvedPeriodDates(for: accountsForPeriod)
        state.periodStartDate = startDate
        state.periodEndDate = endDate

        // Баланс/дельту заголовка и карточки считаем на ТОМ ЖЕ скоупе, что и серия графика
        // (updateChartDataAsync: .historicalInterval того же периода). Он включает archived-счета
        // (Q3 — архивация не переписывает прошлое). Раньше здесь был .currentVisible (archived
        // исключены) → правый край заголовка расходился с последней точкой серии на портфеле с
        // архивным счётом (AC1/AC4). Для не-архивных портфелей набор счетов идентичен currentVisible.
        let accounts = getAccountsForCalculation(scope: .historicalInterval(DateInterval(start: startDate, end: endDate)))

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
        if historicalReaderMode != .shadow, let series = historicalPortfolioSeries {
            state.currencyBreakdown = structuredCurrencyBreakdown(from: series)
            return
        }
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

        // [Ф5c.7 Gate A] Core-счета (вклады/кредиты/маркет-инвестиции, созданные через
        // `AccountsCoreService`) раньше не участвовали в разбивке по валютам вообще — для
        // мигрированного юзера давало 0/занижение. Используем ТУ ЖЕ единую точку сбора счетов
        // (`coreAccountsForDynamics()`), что per-account/per-group строки Динамики (инвариант
        // «один источник правды»), и ТОТ ЖЕ движок баланса (`accountsTotalsService`), что
        // `coreAccountDynamicsItems`/`coreContributionWithLegacyPredecessor` — не вводим второй
        // путь агрегации. Валюта — нативная (`account.currency` как target для `total`, без FX).
        // Дедуп: `FinanceNetWorthSignedAmount.signedValue` (выше) БЕЗУСЛОВНО возвращает nil для
        // archived-счёта (card/credit/investment — каждый гардит `archivedAt == nil` независимо
        // от `state.showArchivedAccounts`/scope-фильтра) — мигрированный легаси-двойник поэтому
        // НИКОГДА не попадает в `nativeTotals` выше, ни при каком состоянии тумблера «показать
        // архивные». Доп. проверка по `LegacyConversionRegistry` здесь была бы недостижимым кодом
        // (доказано мутационным тестом: отключение такой проверки не роняет
        // `migratedTwinNotDoubleCountedWhenArchivedAccountsShown`) — не добавляем.
        // [Известное ограничение, унаследовано] `coreAccountsForDynamics()` не уважает
        // `selectedAccountIDs`/`isSingleAccountMode` — общая функция для нескольких потребителей
        // (per-account/per-group строки Динамики), каскад правки вне скоупа этого фикса.
        for coreAccount in coreAccountsForDynamics() {
            let value = NSDecimalNumber(
                decimal: await financeViewModel.accountsTotalsService.total(for: [coreAccount], on: Date(), in: coreAccount.currency)
            ).doubleValue
            guard abs(value) > 0.01 else { continue }
            nativeTotals[coreAccount.currency, default: 0] += value
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

    private func structuredCurrencyBreakdown(
        from series: HistoricalPortfolioSeriesResult
    ) -> [CurrencyBreakdownItem] {
        guard let point = state.selectedDate.flatMap({ series.point(nearestTo: $0) }) ?? series.points.last,
              point.valuation.total != nil else {
            return []
        }
        let currencyByID = structuredAccountDescriptors().mapValues(\.currency)
        var totals: [String: Double] = [:]
        for contribution in point.accountContributions {
            guard let value = contribution.value,
                  let currency = currencyByID[contribution.opaqueAccountID] else { continue }
            totals[currency, default: 0] += NSDecimalNumber(decimal: value).doubleValue
        }
        let positiveTotal = totals.values.filter { $0 > 0 }.reduce(0, +)
        guard positiveTotal > 0 else { return [] }
        return totals
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map {
                CurrencyBreakdownItem(
                    id: $0.key,
                    currency: $0.key,
                    convertedValue: $0.value,
                    percentage: $0.value / positiveTotal * 100
                )
            }
    }

    /// Легаси-счета, индексированные по `accountID` (== легаси `uniqueID`, ключ `LegacyConversionRegistry`).
    /// Историческая выборка (distantPast…distantFuture) включает archived-предшественников мигрированных
    /// core-счетов, скрытых из `.currentVisible`.
    private func legacyAccountsByUniqueID() -> [String: FinanceAccount] {
        Dictionary(
            getAccountsForCalculation(
                scope: .historicalInterval(DateInterval(start: .distantPast, end: .distantFuture))
            ).map { ($0.accountID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Вклад легаси-предшественников набора core-счетов на дату (реверс `LegacyConversionRegistry`).
    /// До миграции 6b core-двойника не существовало → `accountsTotalsService.total` = 0 на домиграционных
    /// датах, из-за чего Start строки/группы показывался 0 при живом графике. Добавляем баланс легаси-
    /// двойника ТЕМ ЖЕ time-aware движком, что рисует скелет графика (`calculateBalanceAtDate`: archived-
    /// счёт отдаёт реальный баланс для дат <= archivedAt, после — 0). Двойного счёта нет: конвертированный
    /// легаси archived и в `.currentVisible`-строки не попадает.
    private func legacyPredecessorContribution(
        for coreAccounts: [Account],
        on date: Date,
        legacyByUniqueID: [String: FinanceAccount]
    ) async -> Double {
        var sum: Double = 0
        for account in coreAccounts {
            guard let legacyUniqueID = LegacyConversionRegistry.shared.legacyUniqueID(forCoreAccountID: account.id),
                  let legacyAccount = legacyByUniqueID[legacyUniqueID] else { continue }
            // Инвариант границы (СТРОГО `<`, не `<=`): день миграции (`dayKey == archivedAt`) принадлежит
            // core-двойнику через opening-снапшот. Легаси-предшественник отдаёт баланс ТОЛЬКО для дней
            // строго ДО дня архивации; на сам день миграции его вклад = 0, иначе вклад легаси и вклад
            // core-двойника за один и тот же день суммируются → двойной учёт вклада в графике «Динамика».
            // Сравнение на уровне dayKey (день), а не Date: archivedAt может иметь время внутри дня.
            // archivedAt легаси-предшественника лежит на конкретной модели (Card/Credit/Investment)
            // в кэшах, а не на FinanceAccount. Нет archivedAt (не архивирован) → окно не сужаем.
            if let archivedAt = legacyPredecessorArchivedAt(for: legacyAccount),
               AccountEvent.dayKey(for: date) >= AccountEvent.dayKey(for: archivedAt) {
                continue
            }
            let cardIDs: Set<String> = legacyAccount.accountType == .card ? [legacyAccount.accountID] : []
            sum += await calculateBalanceAtDate(
                accounts: [legacyAccount], date: date,
                accountCardIDs: cardIDs, debtAsNegative: true, includeInitialBeforeCreation: false
            )
        }
        return sum
    }

    /// `archivedAt` конкретной легаси-модели (Card/Credit/Investment) по её FinanceAccount-обёртке.
    /// FinanceAccount — лишь связь группа↔счёт и archivedAt не хранит; берём его из тех же кэшей,
    /// что и `calculateBalanceAtDate`. `nil` — счёт не архивирован (или не найден в кэше).
    private func legacyPredecessorArchivedAt(for legacyAccount: FinanceAccount) -> Date? {
        switch legacyAccount.accountType {
        case .card: return cardsCache[legacyAccount.accountID]?.archivedAt
        case .credit: return creditsCache[legacyAccount.accountID]?.archivedAt
        case .investment: return investmentsCache[legacyAccount.accountID]?.archivedAt
        }
    }

    /// Core-счета, участвующие в Динамике. `Account`/`AccountGroup` — primary source of truth;
    /// легаси-`FinanceGroup` используется только как name bridge для старых filter IDs. После
    /// core-primary flip сбор через `state.groups: [FinanceGroup]` возвращал пустой scope
    /// на реальном core-only профиле, хотя экран «Счета» видел все данны.
    private func coreAccountsForDynamics() -> [Account] {
        let today = Date()
        let allCoreAccounts = ((try? modelContext.fetch(FetchDescriptor<Account>())) ?? [])
            .filter { $0.participates(on: today) }
        guard !state.selectedGroupIDs.isEmpty else { return allCoreAccounts }

        let selectedCoreGroupIDs = Set(state.selectedGroupIDs.compactMap { UUID(uuidString: $0) })
        let selectedLegacyGroupNames = Set(
            state.groups
                .filter { state.selectedGroupIDs.contains($0.groupUniqueID) }
                .map(\.name)
        )
        return allCoreAccounts.filter { account in
            guard let group = account.group else { return false }
            return selectedCoreGroupIDs.contains(group.id) || selectedLegacyGroupNames.contains(group.name)
        }
    }

    /// Суммарный core-вклад (per-account total + вклад легаси-предшественника) на пару дат при текущем
    /// фильтре групп. Считается ТЕМ ЖЕ движком, что per-account строки Динамики (`coreAccountDynamicsItems`),
    /// поэтому Cashflow Assets-snapshot, вызывая этот метод, получает Start/End, идентичный вкладке «Динамика».
    /// Агрегатный `accountsTotalsService.totalAt` тут НЕ годится: для мигрировавшего из легаси core-счёта он
    /// возвращает 0 на датах ДО первого core-снапшота (легаси-история конвертации теряется) — это и был баг
    /// «Активы на начало периода = 0» в Cashflow при живом Start в Динамике.
    func coreContributionWithLegacyPredecessor(startDate: Date, endDate: Date) async -> (start: Double, end: Double) {
        let coreAccounts = coreAccountsForDynamics()
        guard !coreAccounts.isEmpty else { return (0, 0) }
        let currency = state.displayCurrency
        let legacyByUniqueID = legacyAccountsByUniqueID()

        var start: Double = 0
        var end: Double = 0
        for account in coreAccounts {
            start += NSDecimalNumber(
                decimal: await financeViewModel.accountsTotalsService.total(for: [account], on: startDate, in: currency)
            ).doubleValue + (await legacyPredecessorContribution(for: [account], on: startDate, legacyByUniqueID: legacyByUniqueID))
            end += NSDecimalNumber(
                decimal: await financeViewModel.accountsTotalsService.total(for: [account], on: endDate, in: currency)
            ).doubleValue + (await legacyPredecessorContribution(for: [account], on: endDate, legacyByUniqueID: legacyByUniqueID))
        }
        return (start, end)
    }

    /// Core-счета для ветки `.accounts` дашборда «Динамика»: каждый счёт — отдельная строка, суммы и
    /// дельта в валюте экрана через тот же `accountsTotalsService`, что и per-group суммы (Фаза 1.5).
    /// Уважает выбор групп (`selectedGroupIDs`); дедуп по `id`. Список короткий — считаем последовательно.
    private func coreAccountDynamicsItems(startDate: Date, endDate: Date) async -> [DynamicsAccountRow] {
        let currency = state.displayCurrency
        let coreAccounts = coreAccountsForDynamics()
        guard !coreAccounts.isEmpty else { return [] }

        // Легаси-предшественники (реверс LegacyConversionRegistry): до миграции 6b core-двойника не
        // существовало → core.total(startDate)=0 и строка показывала Start=0 при живом графике
        // («по графику цифры были, а показывает 0»). Добавляем баланс легаси-двойника тем же движком
        // (legacyPredecessorContribution), что и per-group строки — итог per-account идентичен
        // комбинированному движку графика, поэтому Total (сумма строк) согласован с первой точкой серии.
        let legacyByUniqueID = legacyAccountsByUniqueID()
        let ungroupedName = FinanceSystemGroups.ungroupedName

        var rows: [DynamicsAccountRow] = []
        for account in coreAccounts {
            let start = NSDecimalNumber(
                decimal: await financeViewModel.accountsTotalsService.total(for: [account], on: startDate, in: currency)
            ).doubleValue + (await legacyPredecessorContribution(for: [account], on: startDate, legacyByUniqueID: legacyByUniqueID))
            let end = NSDecimalNumber(
                decimal: await financeViewModel.accountsTotalsService.total(for: [account], on: endDate, in: currency)
            ).doubleValue + (await legacyPredecessorContribution(for: [account], on: endDate, legacyByUniqueID: legacyByUniqueID))
            // Знак уже заложен в total (loan/debt отрицательны) — как в ветке .groups, дельту не переворачиваем.
            let delta = end - start
            let item = DynamicsBreakdownItem(
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
            )
            // Группа core-счёта (`AccountGroup`) связана с легаси `FinanceGroup` по имени — так же матчит
            // `newCoreAccounts(matching:)`. Резолвим в `groupUniqueID`, чтобы агрегация шла по строкам
            // state.groups. Псевдогруппу «Без группы» и нераспознанное имя нормализуем в nil (одна ungrouped-строка).
            let coreGroupName = account.group?.name
            let groupUniqueID: String? = {
                guard let coreGroupName, coreGroupName != ungroupedName else { return nil }
                return state.groups.first(where: { $0.name == coreGroupName })?.groupUniqueID
            }()
            rows.append(DynamicsAccountRow(item: item, groupUniqueID: groupUniqueID))
        }
        return rows
    }

    /// Per-account строка динамики + принадлежность к группе (`nil` → «Без группы»).
    /// Единый промежуточный тип: вкладка «Счета» отдаёт `item` как есть, вкладка «Группы»
    /// агрегирует те же строки по `groupUniqueID` — один расчёт, инвариант Total(Groups)==Total(Accounts).
    private struct DynamicsAccountRow {
        let item: DynamicsBreakdownItem
        let groupUniqueID: String?
    }

    /// Карта легаси-счёт → группа (`accountUniqueID` → `groupUniqueID`). Псевдогруппу «Без группы»
    /// пропускаем: её счета остаются `nil` (ungrouped) — иначе получаем две строки «Без группы».
    private func legacyAccountGroupMap() -> [String: String] {
        var map: [String: String] = [:]
        let ungroupedName = FinanceSystemGroups.ungroupedName
        for group in state.groups where group.name != ungroupedName {
            for account in getAccounts(for: group) {
                map[account.accountUniqueID] = group.groupUniqueID
            }
        }
        return map
    }

    /// Легаси per-account строки — тот же движок, что раньше был заинлайнен в ветке `.accounts`.
    /// Каждая строка помечается группой из `legacyAccountGroupMap`, чтобы ветка `.groups`
    /// агрегировала эти же значения без повторного расчёта.
    private func legacyAccountDynamicsRows(
        accounts: [FinanceAccount],
        startDate: Date,
        endDate: Date
    ) async -> [DynamicsAccountRow] {
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

        let groupMap = legacyAccountGroupMap()
        return accountsData.compactMap { data -> DynamicsAccountRow? in
            guard let item = orderedItems[data.0] else { return nil }
            return DynamicsAccountRow(item: item, groupUniqueID: groupMap[data.1])
        }
    }

    /// Агрегация per-account строк в строки групп. Складываем ЗНАКОВЫЕ значения (обязательства с `-abs`)
    /// тем же правилом, что `FinanceDynamicsPresentation.signedAccountValue` применяет к заголовку «Счета» —
    /// поэтому Total(Groups) через `totalRow(.groups)` == Total(Accounts) на любом наборе. Строк «Без группы»
    /// ровно одна; порядок групп — как в `state.groups`.
    private func aggregateGroupRows(
        from rows: [DynamicsAccountRow],
        groupsToShow: [FinanceGroup],
        includeUngrouped: Bool
    ) -> [DynamicsBreakdownItem] {
        var groupStart: [String: Double] = [:]
        var groupEnd: [String: Double] = [:]
        var ungroupedStart = 0.0
        var ungroupedEnd = 0.0
        var hasUngrouped = false

        for row in rows {
            let start = FinanceDynamicsPresentation.signedAccountValue(row.item.startValue, for: row.item)
            let end = FinanceDynamicsPresentation.signedAccountValue(row.item.endValue, for: row.item)
            if let groupID = row.groupUniqueID {
                groupStart[groupID, default: 0] += start
                groupEnd[groupID, default: 0] += end
            } else {
                ungroupedStart += start
                ungroupedEnd += end
                hasUngrouped = true
            }
        }

        var result: [DynamicsBreakdownItem] = []
        for group in groupsToShow {
            guard let start = groupStart[group.groupUniqueID] else { continue }
            let end = groupEnd[group.groupUniqueID] ?? 0
            let delta = end - start
            result.append(DynamicsBreakdownItem(
                id: group.groupUniqueID,
                name: group.name,
                startValue: start,
                endValue: end,
                delta: delta,
                deltaPercent: calculateDeltaPercent(delta: delta, startBalance: start),
                icon: nil,
                accountType: nil,
                isCreditCard: false,
                isArchived: false
            ))
        }

        if hasUngrouped, includeUngrouped {
            let delta = ungroupedEnd - ungroupedStart
            result.append(DynamicsBreakdownItem(
                id: "ungrouped",
                name: FinanceSystemGroups.ungroupedName,
                startValue: ungroupedStart,
                endValue: ungroupedEnd,
                delta: delta,
                deltaPercent: calculateDeltaPercent(delta: delta, startBalance: ungroupedStart),
                icon: nil,
                accountType: nil,
                isCreditCard: false,
                isArchived: false
            ))
        }

        return result
    }

    /// Обновить список динамики
    func updateDynamicsBreakdown() async {
        if historicalReaderMode != .shadow, let series = historicalPortfolioSeries {
            state.dynamicsBreakdown = structuredDynamicsBreakdown(from: series)
            return
        }
        let accounts = getAccountsForCalculation(scope: .currentVisible)
        let requestedPeriod = getPeriodDates()
        let startDate = requestedPeriod.start
        let endDate = requestedPeriod.end
        
        var breakdown: [DynamicsBreakdownItem] = []
        
        let viewMode = state.viewMode
        let selectedGroupIDs = state.selectedGroupIDs
        let selectedAccountIDs = state.selectedAccountIDs
        let groups = state.groups

        // ЕДИНЫЙ ИСТОЧНИК: per-account строки считаются один раз (легаси + core). Вкладка «Счета»
        // отдаёт их как есть, вкладка «Группы» агрегирует те же строки по группам. Это гарантирует
        // Total(Groups) == Total(Accounts) и устраняет тройной Ungrouped (был второй расчёт в .groups).
        var rows = await legacyAccountDynamicsRows(accounts: accounts, startDate: startDate, endDate: endDate)
        // Core-счета: у ядра нет legacy-`accountUniqueID`, поэтому при фильтре по конкретным легаси-счетам
        // их не показываем (как и раньше). coreAccountDynamicsItems уважает фильтр по группам.
        if selectedAccountIDs.isEmpty {
            rows.append(contentsOf: await coreAccountDynamicsItems(startDate: startDate, endDate: endDate))
        }

        switch viewMode {
        case .groups:
            // Агрегируем per-account строки по группам (никакого второго расчёта). Порядок групп — как в
            // state.groups; Ungrouped-строка ровно одна и только когда фильтр по группам не активен.
            let groupsToShow = selectedGroupIDs.isEmpty
                ? groups
                : groups.filter { selectedGroupIDs.contains($0.groupUniqueID) }
            breakdown = aggregateGroupRows(
                from: rows,
                groupsToShow: groupsToShow,
                includeUngrouped: selectedGroupIDs.isEmpty
            )

        case .accounts:
            // Каждый счёт отдельной строкой — те же per-account строки, что агрегирует ветка .groups.
            breakdown = rows.map(\.item)
        }

        await MainActor.run {
            state.dynamicsBreakdown = breakdown
        }
    }

    private func structuredDynamicsBreakdown(
        from series: HistoricalPortfolioSeriesResult
    ) -> [DynamicsBreakdownItem] {
        guard let first = series.points.first,
              let last = series.points.last,
              first.valuation.total != nil,
              last.valuation.total != nil else {
            return []
        }
        let descriptors = structuredAccountDescriptors()
        let startByID = Dictionary(uniqueKeysWithValues: first.accountContributions.compactMap { contribution in
            contribution.value.map { value in (contribution.opaqueAccountID, value) }
        })
        let endByID = Dictionary(uniqueKeysWithValues: last.accountContributions.compactMap { contribution in
            contribution.value.map { value in (contribution.opaqueAccountID, value) }
        })
        let contributionIDs = Set(startByID.keys).union(endByID.keys)
        let rows: [DynamicsAccountRow] = contributionIDs.sorted().compactMap { id in
            guard let startValue = startByID[id],
                  let endValue = endByID[id] else { return nil }
            let descriptor = descriptors[id] ?? StructuredAccountDescriptor(
                name: L("finances.dynamics.chart.account_fallback"),
                currency: state.displayCurrency,
                groupUniqueID: nil,
                icon: nil,
                accountType: nil,
                isLiability: false,
                isArchived: false
            )
            let start = NSDecimalNumber(decimal: startValue).doubleValue
            let end = NSDecimalNumber(decimal: endValue).doubleValue
            let delta = end - start
            return DynamicsAccountRow(
                item: DynamicsBreakdownItem(
                    id: id,
                    name: descriptor.name,
                    startValue: start,
                    endValue: end,
                    delta: delta,
                    deltaPercent: calculateDeltaPercent(delta: delta, startBalance: start),
                    icon: descriptor.icon,
                    accountType: descriptor.accountType,
                    isCreditCard: descriptor.isLiability,
                    isArchived: descriptor.isArchived
                ),
                groupUniqueID: descriptor.groupUniqueID
            )
        }
        switch state.viewMode {
        case .accounts:
            return rows.map(\.item)
        case .groups:
            let groups = state.selectedGroupIDs.isEmpty
                ? state.groups
                : state.groups.filter { state.selectedGroupIDs.contains($0.groupUniqueID) }
            return aggregateGroupRows(
                from: rows,
                groupsToShow: groups,
                includeUngrouped: state.selectedGroupIDs.isEmpty
            )
        }
    }

    /// Presentation metadata only. Historical amounts always come from the bundle; this lookup must
    /// never replay balances. Both core IDs and unresolved legacy opaque IDs are represented so a
    /// mixed portfolio's breakdown/distributions reconstruct the selected endpoint exactly.
    private func structuredAccountDescriptors() -> [String: StructuredAccountDescriptor] {
        let coreAccounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        var result = Dictionary(uniqueKeysWithValues: coreAccounts.map { account in
            let groupID = account.group.flatMap { group in
                state.groups.first(where: { $0.name == group.name })?.groupUniqueID
            }
            return (account.id.uuidString, StructuredAccountDescriptor(
                name: account.name,
                currency: account.currency,
                groupUniqueID: groupID,
                icon: account.kind.fallbackIconName,
                accountType: nil,
                isLiability: account.kind == .loan,
                isArchived: account.archivedAt != nil
            ))
        })

        let groupByAccountID = legacyAccountGroupMap()
        let legacyAccounts = (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []
        for account in legacyAccounts {
            let currency: String
            let name: String
            let isLiability: Bool
            switch account.accountType {
            case .card:
                let card = cardsCache[account.accountID]
                currency = card?.currency ?? state.displayCurrency
                name = card?.name ?? account.accountID
                isLiability = card?.cardType == .credit
            case .credit:
                let credit = creditsCache[account.accountID]
                currency = credit?.currency ?? state.displayCurrency
                name = credit?.name ?? account.accountID
                isLiability = true
            case .investment:
                let investment = investmentsCache[account.accountID]
                currency = investment?.currency ?? state.displayCurrency
                name = investment?.name ?? account.accountID
                isLiability = investment?.investmentType == .negative
            }
            result[account.accountUniqueID] = StructuredAccountDescriptor(
                name: name,
                currency: currency,
                groupUniqueID: groupByAccountID[account.accountUniqueID],
                icon: nil,
                accountType: account.accountType,
                isLiability: isLiability,
                isArchived: isAccountArchived(account)
            )
        }
        return result
    }

    private struct StructuredAccountDescriptor {
        let name: String
        let currency: String
        let groupUniqueID: String?
        let icon: String?
        let accountType: FinanceAccountType?
        let isLiability: Bool
        let isArchived: Bool
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
            let liveEndBalanceAggr: Double? = historicalReaderMode == .shadow && chartAccounts.count == 1
                && state.selectedDate == nil
                && !isAccountArchived(chartAccounts[0])
                ? await liveConvertedBalance(for: chartAccounts[0], displayCurrency: state.displayCurrency, at: period.end)
                : nil
            // Единый продюсер серии (Ф2 dynamics-single-source-of-truth): легаси-реплей + вклад
            // ядра ровно один раз на календарный день, дедуп точек по дню. График — это сам массив;
            // заголовок и карточка «Общая сумма» читают его концы. Снесён отдельный шаг
            // addingCoreContribution — core сворачивается внутри продюсера.
            let compatibilitySeries = if historicalReaderMode == .shadow {
                await aggregatedDynamicsSeries(
                    accounts: chartAccounts,
                    period: (start: period.start, end: period.end),
                    useNetTotals: useNetTotals,
                    liveEndBalance: liveEndBalanceAggr
                )
            } else {
                historicalDateSkeleton(period: period)
            }
            guard isCurrentChartUpdateRevision(revision) else { return }
            let structuredSeries = await historicalAggregatedSeries(
                period: period,
                compatibilitySeries: compatibilitySeries
            )
            guard isCurrentChartUpdateRevision(revision) else { return }
            state.chartData = structuredSeries.points

        case .byAccounts:
            // Каждый счет - отдельная линия
            var allDataPoints: [ChartDataPoint] = []
            if historicalReaderMode == .shadow {
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
            } else {
                allDataPoints = historicalDateSkeleton(period: period).points
            }
            guard isCurrentChartUpdateRevision(revision) else { return }
            let structuredSeries = await historicalScopedSeries(
                period: period,
                compatibilitySeries: DynamicsSeries(points: allDataPoints),
                accountIDs: scopedCoreAccountIDs(),
                singleAccountID: nil
            )
            guard isCurrentChartUpdateRevision(revision) else { return }
            state.chartData = structuredSeries.points

        case .singleAccount(let accountID):
            // Один выбранный счет
            if let account = chartAccounts.first(where: { $0.accountUniqueID == accountID }) {
                let chartData: [ChartDataPoint]
                if historicalReaderMode == .shadow {
                    let liveEndBalanceSingle: Double? = state.selectedDate == nil && !isAccountArchived(account)
                        ? await liveConvertedBalance(for: account, displayCurrency: state.displayCurrency, at: period.end)
                        : nil
                    chartData = await buildTimeSeriesData(
                        accounts: [account],
                        startDate: period.start,
                        endDate: period.end,
                        label: getAccountInfoForDynamics(account: account)?.name ?? L("finances.dynamics.chart.account_fallback"),
                        debtAsNegative: false,
                        liveEndBalance: liveEndBalanceSingle
                    )
                } else {
                    chartData = historicalDateSkeleton(period: period).points
                }
                guard isCurrentChartUpdateRevision(revision) else { return }
                let coreID = coreAccountID(forVisibleAccountID: accountID)
                let structuredSeries = await historicalScopedSeries(
                    period: period,
                    compatibilitySeries: DynamicsSeries(points: chartData),
                    accountIDs: coreID.map { Set([$0]) } ?? [],
                    singleAccountID: coreID
                )
                guard isCurrentChartUpdateRevision(revision) else { return }
                state.chartData = structuredSeries.points
            } else {
                guard isCurrentChartUpdateRevision(revision) else { return }
                state.chartData = []
            }
        }
    }

    private func scopedCoreAccountIDs() -> Set<UUID> {
        let selected = state.selectedAccountIDs
        let available = Set(coreAccountsForDynamics().map(\.id))
        guard !selected.isEmpty else { return available }
        return Set(selected.compactMap(coreAccountID(forVisibleAccountID:))).intersection(available)
    }

    private func coreAccountID(forVisibleAccountID id: String) -> UUID? {
        if let uuid = UUID(uuidString: id) { return uuid }
        return LegacyConversionRegistry.shared.coreAccountID(forLegacyUniqueID: id)
    }

    /// Phase 4 reader switch. Shadow executes the structured producer but keeps the compatibility
    /// pixels until the observation gate; structured mode projects only complete/provisional totals.
    /// Incomplete diagnostic subtotals are deliberately omitted, producing a chart gap.
    private func historicalAggregatedSeries(
        period: (start: Date, end: Date),
        compatibilitySeries: DynamicsSeries
    ) async -> DynamicsSeries {
        await historicalScopedSeries(
            period: period,
            compatibilitySeries: compatibilitySeries,
            accountIDs: scopedCoreAccountIDs(),
            singleAccountID: nil,
            projectsAccountLines: false
        )
    }

    private func historicalScopedSeries(
        period: (start: Date, end: Date),
        compatibilitySeries: DynamicsSeries,
        accountIDs: Set<UUID>?,
        singleAccountID: UUID?,
        projectsAccountLines: Bool = true
    ) async -> DynamicsSeries {
        let query = HistoricalPortfolioSeriesQuery(
            period: DateInterval(start: period.start, end: period.end),
            timeZoneID: TimeZone.current.identifier,
            displayCurrency: state.displayCurrency,
            accountScope: accountIDs.map(HistoricalPortfolioAccountScope.accountIDs) ?? .portfolio,
            samplingPolicy: .exact(
                compatibilitySeries.points.isEmpty
                    ? [period.start, period.end]
                    : compatibilitySeries.points.map(\.date)
            ),
            valuationPolicyVersion: 1,
            unresolvedExternalAccountIDs: unresolvedLegacyAccountIDs()
        )
        let result = await HistoricalPortfolioSeriesProducer(
            valuator: financeViewModel.accountsTotalsService,
            scopeID: financeViewModel.historicalValuationScopeID,
            closeStore: HistoricalValuationCloseStore(modelContainer: modelContext.container),
            externalCoverage: legacyHistoricalValuator
        ).series(for: query)
        historicalPortfolioSeries = result
        logIncompleteHistoricalSeries(result, requestedCoreAccountCount: accountIDs?.count)

        if historicalReaderMode == .shadow {
            let structuredResult = result.points.last?.valuation
            let structuredEnd = structuredResult?.total
            let compatibilityEnd = compatibilitySeries.points.last.map { Decimal($0.value) }
            historicalShadowDeltaBucket = .classify(
                structured: structuredEnd,
                compatibility: compatibilityEnd
            )
            if let structuredResult {
                HistoricalPortfolioShadowEvidenceStore().append(.init(
                    observation: .classify(
                        structured: structuredResult,
                        compatibilityTotal: compatibilityEnd,
                        compatibilityContributionCount: nil,
                        hasExpectedResolverCorrection: false
                    ),
                    dayKey: structuredResult.key.dayKey
                ))
            }
        } else {
            historicalShadowDeltaBucket = nil
        }
        guard historicalReaderMode != .shadow else { return compatibilitySeries }

        let label = L("finances.dynamics.chart.total_label")
        let points = result.points.flatMap { point -> [ChartDataPoint] in
            guard point.valuation.total != nil else { return [] }
            if !projectsAccountLines {
                guard let total = point.valuation.total else { return [] }
                return [ChartDataPoint(
                    date: point.date,
                    value: NSDecimalNumber(decimal: total).doubleValue,
                    label: label
                )]
            }
            return point.accountContributions.compactMap { contribution in
                guard let value = contribution.value,
                      singleAccountID == nil || contribution.opaqueAccountID == singleAccountID?.uuidString else {
                    return nil
                }
                return ChartDataPoint(
                    date: point.date,
                    value: NSDecimalNumber(decimal: value).doubleValue,
                    label: contribution.opaqueAccountID
                )
            }
        }
        return DynamicsSeries(points: points)
    }

    /// Non-PII diagnostics for the fail-closed historical reader. Exact balances, names and opaque
    /// account identifiers are deliberately excluded; Xcode receives only coverage and reason codes.
    private func logIncompleteHistoricalSeries(
        _ series: HistoricalPortfolioSeriesResult,
        requestedCoreAccountCount: Int?
    ) {
        let incomplete = series.points.filter { $0.valuation.total == nil }
        guard !incomplete.isEmpty else { return }

        let dimensions = Set(incomplete.flatMap { point in
            point.valuation.unresolved.map { String(describing: $0.dimension) }
        }).sorted().joined(separator: ",")
        let reasons = Set(incomplete.flatMap { point in
            point.valuation.unresolved.map(\.reasonCode)
        }).sorted().joined(separator: ",")
        let expected = incomplete.map { $0.valuation.expectedContributionCount }.max() ?? 0
        let resolved = incomplete.map { $0.valuation.resolvedContributionCount }.min() ?? 0
        let requestedCore = requestedCoreAccountCount.map { String($0) } ?? "all"

        AppLogger.log(
            .warning,
            category: "HistoricalPortfolio",
            "Incomplete series: points=\(incomplete.count)/\(series.points.count), "
                + "requestedCore=\(requestedCore), "
                + "coverage=\(resolved)/\(expected), dimensions=[\(dimensions)], reasons=[\(reasons)]"
        )
    }

    /// Pure sampling skeleton for structured/compatibility readers. It selects dates only and never
    /// executes legacy replay, FX, market lookup or live endpoint reconciliation.
    private func historicalDateSkeleton(
        period: (start: Date, end: Date)
    ) -> DynamicsSeries {
        let calendar = Calendar.current
        let start = min(period.start, period.end)
        let end = max(period.start, period.end)
        let totalDays = max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
        let stepDays: Int
        if let configuredDays = state.period.days {
            stepDays = configuredDays <= 30 ? 1 : configuredDays <= 365 ? 2 : 5
        } else {
            stepDays = totalDays <= 365 ? 2 : totalDays <= 730 ? 5 : 7
        }

        var dates: Set<Date> = [start, end]
        var cursor = start
        while cursor < end,
              let next = calendar.date(byAdding: .day, value: stepDays, to: cursor),
              next > cursor {
            cursor = min(next, end)
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: cursor) ?? cursor
            dates.insert(min(endOfDay, end))
        }
        return DynamicsSeries(points: dates.sorted().map {
            ChartDataPoint(date: $0, value: 0, label: "sampling")
        })
    }

    private func unresolvedLegacyAccountIDs() -> Set<String> {
        let period = DateInterval(start: state.periodStartDate, end: state.periodEndDate)
        return Set(getAccountsForCalculation(scope: .historicalInterval(period)).map(\.accountUniqueID))
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

    // MARK: - Единый продюсер серии (Ф2 dynamics-single-source-of-truth)

    /// Единый per-day продюсер агрегированной серии «Динамики»: сворачивает легаси-реплей
    /// (`buildTimeSeriesData`) и вклад ядра (`AccountsTotalsService.totalAt`) ОДИН раз на календарный
    /// день. Обслуживает unscoped-агрегат (общий тотал) — scoped-режимы (группы/один счёт) остаются
    /// на легаси per-account пути до порта «1b». Легаси+core складываются один раз на день (устраняет
    /// класс double-count), точки дедуплятся по календарному дню (закрывает дубль даты на оси,
    /// находка 4). Заголовок и карточка «Общая сумма» читают концы этой серии.
    func aggregatedDynamicsSeries(
        accounts: [FinanceAccount],
        period: (start: Date, end: Date),
        useNetTotals: Bool,
        liveEndBalance: Double? = nil,
        includeCore: Bool = true
    ) async -> DynamicsSeries {
        let legacyPoints = await buildTimeSeriesData(
            accounts: accounts,
            startDate: period.start,
            endDate: period.end,
            label: L("finances.dynamics.chart.total_label"),
            debtAsNegative: useNetTotals,
            liveEndBalance: liveEndBalance
        )
        let deduped = dedupedByCalendarDay(legacyPoints)
        guard includeCore else {
            return DynamicsSeries(points: deduped)
        }
        // Core-only портфель: легаси-счетов нет → legacyPoints пуст, dedupedByCalendarDay возвращает []
        // (guard на пустом входе) и core-цикл не стартует → пустая серия (AC5/AC1). Строим дневной
        // скелет из самих концов периода (нулевые легаси-значения), чтобы core-вклад лёг на непустую
        // основу. Концы = resolvedPeriodDates, поэтому startValue/endValue сходятся с заголовком.
        let skeleton: [ChartDataPoint]
        if deduped.isEmpty {
            let label = L("finances.dynamics.chart.total_label")
            skeleton = [
                ChartDataPoint(date: period.start, value: 0, label: label),
                ChartDataPoint(date: period.end, value: 0, label: label)
            ]
        } else {
            skeleton = deduped
        }
        // Core складывается ОДИН раз на точку (= на день): точный запрос ядра на дату точки. На
        // концах даты совпадают с resolvedPeriodDates, поэтому endValue/startValue серии сходятся с
        // core-вкладом заголовка (totalAt на тех же датах) — инвариант AC1.
        var withCore: [ChartDataPoint] = []
        withCore.reserveCapacity(skeleton.count)
        for point in skeleton {
            let core = NSDecimalNumber(
                decimal: await financeViewModel.accountsTotalsService.totalAt(point.date, in: state.displayCurrency)
            ).doubleValue
            withCore.append(ChartDataPoint(date: point.date, value: point.value + core, label: point.label))
        }
        return DynamicsSeries(points: withCore)
    }

    /// Сворачивает точки к одной на календарный день. Концы периода сохраняются как есть (база =
    /// баланс на `periodStart`, конец = баланс на `periodEnd`), середина — по одной точке на день
    /// (последнее значение дня = баланс на конец дня). Для однодневного периода концы совпадают по
    /// дню, но остаются двумя точками — иначе Charts не рисует линию.
    private func dedupedByCalendarDay(_ points: [ChartDataPoint]) -> [ChartDataPoint] {
        let calendar = Calendar.current
        let sorted = points.sorted { $0.date < $1.date }
        guard let first = sorted.first, let last = sorted.last else { return [] }
        let startDay = calendar.startOfDay(for: first.date)
        let endDay = calendar.startOfDay(for: last.date)
        var middleByDay: [Date: ChartDataPoint] = [:]
        for point in sorted {
            let day = calendar.startOfDay(for: point.date)
            guard day != startDay, day != endDay else { continue }
            middleByDay[day] = point
        }
        let middle = middleByDay.values.sorted { $0.date < $1.date }
        return [first] + middle + [last]
    }

    func resolvedPeriodDates(
        for accounts: [FinanceAccount],
        basePeriod: (start: Date, end: Date)? = nil
    ) -> (start: Date, end: Date) {
        let requestedPeriod = basePeriod ?? getPeriodDates()
        guard !accounts.isEmpty else { return requestedPeriod }

        // Q2 (dynamics-single-source-of-truth): база периода НЕ клэмпится к дате первого реального
        // значения. Счёт, созданный внутри периода, до своего createdAt даёт 0 — период держит
        // запрошенную ширину, а дельта честно включает появившиеся на счёт деньги (единый расчёт
        // периода для заголовка, графика и карточки).
        return (min(requestedPeriod.start, requestedPeriod.end), requestedPeriod.end)
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

        var boundaries: [(start: Date, end: Date, id: Date)] = []
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

            boundaries.append((periodStartBalanceDate, periodEnd, cursor))

            if nextStart <= cursor {
                break
            }
            cursor = nextStart
        }
        guard let firstBoundary = boundaries.first, let lastBoundary = boundaries.last else { return [] }

        let overviewLegacyValuator = LegacyHistoricalValuator(
            modelContext: modelContext,
            currencyService: currencyService
        )
        overviewLegacyValuator.reload()
        let sampleDates = boundaries.flatMap { [$0.start, $0.end] }
        let query = HistoricalPortfolioSeriesQuery(
            period: DateInterval(start: firstBoundary.start, end: lastBoundary.end),
            timeZoneID: calendar.timeZone.identifier,
            displayCurrency: state.displayCurrency,
            samplingPolicy: .exact(sampleDates),
            unresolvedExternalAccountIDs: unresolvedLegacyAccountIDs()
        )
        let series = await HistoricalPortfolioSeriesProducer(
            valuator: financeViewModel.accountsTotalsService,
            scopeID: financeViewModel.historicalValuationScopeID,
            closeStore: HistoricalValuationCloseStore(modelContainer: modelContext.container),
            externalCoverage: overviewLegacyValuator
        ).series(for: query)
        let descriptors = structuredAccountDescriptors()

        return boundaries.compactMap { boundary in
            guard let start = series.point(nearestTo: boundary.start),
                  let end = series.point(nearestTo: boundary.end),
                  start.valuation.total != nil,
                  end.valuation.total != nil else { return nil }
            let startByID = Dictionary(uniqueKeysWithValues: start.accountContributions.compactMap { contribution in
                contribution.value.map { (contribution.opaqueAccountID, $0) }
            })
            let endByID = Dictionary(uniqueKeysWithValues: end.accountContributions.compactMap { contribution in
                contribution.value.map { (contribution.opaqueAccountID, $0) }
            })
            var debit = 0.0
            var credit = 0.0
            for id in Set(startByID.keys).union(endByID.keys) {
                let startValue = NSDecimalNumber(decimal: startByID[id] ?? 0).doubleValue
                let endValue = NSDecimalNumber(decimal: endByID[id] ?? 0).doubleValue
                let rawDelta = endValue - startValue
                let adjustedDelta = descriptors[id]?.isLiability == true ? -rawDelta : rawDelta
                if adjustedDelta > 0.01 { debit += adjustedDelta }
                if adjustedDelta < -0.01 { credit += abs(adjustedDelta) }
            }
            return FinanceOverviewPeriodEntry(
                id: boundary.id,
                date: boundary.id,
                debit: debit,
                credit: credit
            )
        }
    }
    
    /// Compatibility API retained for existing Dynamics projections. The replay itself is a
    /// standalone production service and is also the structured producer's legacy coverage.
    func calculateBalanceAtDate(
        accounts: [FinanceAccount],
        date: Date,
        accountCardIDs: Set<String>,
        debtAsNegative: Bool = false,
        includeInitialBeforeCreation: Bool = false
    ) async -> Double {
        _ = accountCardIDs // Kept in the compatibility signature; replay derives IDs from accounts.
        return await legacyHistoricalValuator.balance(
            accounts: accounts,
            at: date,
            displayCurrency: state.displayCurrency,
            debtAsNegative: debtAsNegative,
            includeInitialBeforeCreation: includeInitialBeforeCreation
        )
    }

    /// Explicit shadow copy kept temporarily for parity review during the Phase 4 cutover. New
    /// production consumers must use `LegacyHistoricalValuator` or the structured series producer.
    private func calculateBalanceAtDateCompatibilityShadow(
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
        // Phase 5 warms one shared HistoricalRate cache for both model worlds. Previously the
        // prefetch inspected only legacy products, so a core-only foreign account stayed incomplete
        // even while the identical legacy portfolio had an exact persisted FX row.
        for account in coreAccountsForDynamics() {
            let currency = normalizedConversionCurrency(account.currency)
            if currency != displayCurrency {
                sourceCurrencies.insert(currency)
            }
        }
        let accounts = getAccountsForCalculation(
            scope: .historicalInterval(DateInterval(start: .distantPast, end: .distantFuture))
        )
        let (startDate, endDate) = resolvedPeriodDates(for: accounts)
        // Warm exactly the dates that the producer will request. The former independent 90-point
        // sampler left most chart dates without exact FX evidence.
        let dates = historicalDateSkeleton(period: (startDate, endDate)).points.map(\.date)

        let pairs = sourceCurrencies.map { (from: $0, to: displayCurrency) }
        if !pairs.isEmpty {
            await historicalRateStore.prefetchExactRates(on: Array(Set(dates)), pairs: pairs)
        }
        await AccountMarketPriceService(
            modelContext: modelContext,
            marketDataClient: financeViewModel.marketDataClient
        ).prefetchHistoricalPrices(on: dates, accounts: coreAccountsForDynamics())
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
