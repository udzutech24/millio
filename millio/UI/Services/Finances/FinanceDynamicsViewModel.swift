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
    var period: DynamicsPeriod = .all
    
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
}

// MARK: - Dynamics Period

enum DynamicsPeriod: String, CaseIterable {
    case week = "1W"
    case month = "1M"
    case year = "1Y"
    case all = "All"
    case custom = "Custom"
    
    var days: Int? {
        switch self {
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
}

// MARK: - Finance Dynamics ViewModel

@MainActor
final class FinanceDynamicsViewModel: ViewModelProtocol {
    typealias State = FinanceDynamicsState
    typealias Action = FinanceDynamicsAction
    
    @Published var state = FinanceDynamicsState()
    
    let modelContext: ModelContext
    let financeViewModel: FinanceViewModel
    let currencyService: CurrencyRateServiceProtocol
    private let historicalRateStore: HistoricalRateStore
    private let auditStore: FinanceBalanceAuditStoreProtocol
    
    let defaults = UserDefaults.standard
    private var eventSubscriptionID: UUID?
    private var selectionUpdateTask: Task<Void, Never>?
    private var backgroundTasks: [UUID: Task<Void, Never>] = [:]
    
    // Кэши для оптимизации производительности
    var cardsCache: [String: Card] = [:]
    var creditsCache: [String: Credit] = [:]
    var investmentsCache: [String: Investment] = [:]
    var transactionsByCardCache: [String: [CashflowTransaction]] = [:]
    var transactionsByCreditCache: [String: [CashflowTransaction]] = [:]
    var transactionsByInvestmentCache: [String: [CashflowTransaction]] = [:]
    var initialBalancesCache: [String: Double] = [:]
    var balanceCache: [String: Double] = [:] // Кэш для calculateBalanceAtDate: "accountID_date" -> balance
    var dailyAuditSnapshotCache: [String: [String: FinanceBalanceSnapshotValue]] = [:]
    
    init(
        modelContext: ModelContext,
        financeViewModel: FinanceViewModel,
        initialGroupID: String? = nil,
        initialGroupCurrency: String? = nil,
        initialAccountID: String? = nil,
        initialAccountCurrency: String? = nil,
        currencyService: CurrencyRateServiceProtocol,
        auditStore: FinanceBalanceAuditStoreProtocol = FinanceBalanceAuditStore()
    ) {
        self.modelContext = modelContext
        self.financeViewModel = financeViewModel
        self.currencyService = currencyService
        self.historicalRateStore = HistoricalRateStore(modelContext: modelContext, currencyService: currencyService)
        self.auditStore = auditStore
        
        // Если передан initialAccountID, устанавливаем его как выбранный счет и включаем режим одного счета
        if let accountID = initialAccountID {
            state.selectedAccountIDs = [accountID]
            state.isSingleAccountMode = true
            state.isSingleGroupMode = true // В режиме одного счета также скрываем фильтры групп
            state.dynamicsMode = .singleAccount(accountID)
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
        backgroundTasks[taskID] = Task { [weak self] in
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
    
    private func subscribeToEvents() {
        eventSubscriptionID = EventBus.shared.subscribe { [weak self] event in
            guard let self else { return }
            switch event {
            case FinanceEvent.cardsUpdated,
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
            selectionUpdateTask = Task { [weak self] in
                guard let self else { return }
                await self.updateCurrentBalanceAndDelta(for: selectedDateSnapshot)
            }
            
        case .setDynamicsMode(let mode):
            state.dynamicsMode = mode
            updateChartData()
            
        case .setViewMode(let mode):
            state.viewMode = mode
            scheduleBackgroundTask { viewModel in
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
        
        // Загружаем группы и счета из financeViewModel
        state.groups = financeViewModel.state.groups
        
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
        dailyAuditSnapshotCache.removeAll()
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
            // Загружаем курсы для получения списка валют
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            
            // Собираем валюты из всех счетов
            var currencies = Set<String>()
            for card in viewModel.state.availableCards {
                currencies.insert(card.currency)
            }
            for credit in viewModel.state.availableCredits {
                currencies.insert(credit.currency)
            }
            for investment in viewModel.state.availableInvestments {
                currencies.insert(investment.currency)
            }
            
            // Объединяем с валютами из источника курсов
            currencies = currencies.union(fromRateSource)
            
            if Task.isCancelled { return }
            viewModel.state.availableCurrencies = Array(currencies).sorted()
        }
    }
    
    func updateChartData() {
        state.currencyConversionWarning = nil
        scheduleBackgroundTask { viewModel in
            await viewModel.prefetchHistoricalRatesForCurrentSelection()
            if Task.isCancelled { return }
            await viewModel.updateChartDataAsync()
            if Task.isCancelled { return }
            await viewModel.updateCurrentBalanceAndDelta()
            if Task.isCancelled { return }
            await viewModel.updateDynamicsBreakdown()
        }
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
        case .week, .month, .year:
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

        let (startDate, endDate) = getPeriodDates()
        state.periodStartDate = startDate
        state.periodEndDate = endDate
        
        // Получаем счета для расчета
        let accounts = getAccountsForCalculation()
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
        let currentBalance = await calculateBalanceAtDate(
            accounts: accounts,
            date: targetDate,
            accountCardIDs: Set(accounts.compactMap { $0.accountType == .card ? $0.accountID : nil }),
            debtAsNegative: useNetTotals,
            includeInitialBeforeCreation: false
        )
        if Task.isCancelled { return }
        if selectedDate != state.selectedDate { return }
        state.currentBalance = currentBalance
        
        // Рассчитываем баланс на начало периода
        let startBalance = await calculateBalanceAtDate(
            accounts: accounts,
            date: startDate,
            accountCardIDs: Set(accounts.compactMap { $0.accountType == .card ? $0.accountID : nil }),
            debtAsNegative: useNetTotals,
            includeInitialBeforeCreation: true
        )
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
    
    /// Получить счета для расчета (в зависимости от фильтров)
    func getAccountsForCalculation() -> [FinanceAccount] {
        let groupsToShow = state.selectedGroupIDs.isEmpty
            ? state.groups
            : state.groups.filter { state.selectedGroupIDs.contains($0.groupUniqueID) }
        
        var accounts: [FinanceAccount] = []
        
        if state.isSingleAccountMode && !state.selectedAccountIDs.isEmpty {
            // Режим одного счета
            for group in state.groups {
                if let groupAccounts = group.accounts {
                    if let account = groupAccounts.first(where: { state.selectedAccountIDs.contains($0.accountUniqueID) }) {
                        accounts.append(account)
                        break
                    }
                }
            }
        } else {
            // Обычная логика
            for group in groupsToShow {
                guard let groupAccounts = group.accounts, !groupAccounts.isEmpty else {
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
        
        guard state.showArchivedAccounts == false else {
            return uniqueAccounts
        }
        
        return uniqueAccounts.filter { !isAccountArchived($0) }
    }
    
    /// Обновить список динамики
    func updateDynamicsBreakdown() async {
        let accounts = getAccountsForCalculation()
        let (startDate, endDate) = getPeriodDates()
        
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
                groupsToShow.compactMap { groupItem -> (String, String, [String])? in
                    guard let groupAccounts = groupItem.accounts else { return nil }
                    let filteredAccounts = selectedAccountIDs.isEmpty
                        ? groupAccounts
                        : groupAccounts.filter { selectedAccountIDs.contains($0.accountUniqueID) }
                    if filteredAccounts.isEmpty { return nil }
                    // Извлекаем accountCardIDs на main actor
                    let accountCardIDs = Set(filteredAccounts.compactMap { account -> String? in
                        if account.accountType == .card {
                            return account.accountID
                        }
                        return nil
                    })
                    return (groupItem.groupUniqueID, groupItem.name, Array(accountCardIDs))
                }
            }
            
            // Подготавливаем account IDs для передачи
            let accountIDsForGroups = await MainActor.run {
                groupsToShow.compactMap { groupItem -> (String, [String])? in
                    guard let groupAccounts = groupItem.accounts else { return nil }
                    let filteredAccounts = selectedAccountIDs.isEmpty
                        ? groupAccounts
                        : groupAccounts.filter { selectedAccountIDs.contains($0.accountUniqueID) }
                    if filteredAccounts.isEmpty { return nil }
                    let accountIDs = filteredAccounts.map { $0.accountUniqueID }
                    return (groupItem.groupUniqueID, accountIDs)
                }
            }
            
            // Сохраняем только ID групп для передачи между задачами
            let groupIDs = await MainActor.run {
                Set(groupsToShow.map { $0.groupUniqueID })
            }
            
            await withTaskGroup(of: DynamicsBreakdownItem?.self) { group in
                for (groupID, groupName, accountCardIDsArray) in groupsData {
                    group.addTask { @MainActor in
                        // Получаем accounts на main actor по их IDs из state.groups внутри @MainActor контекста
                        guard groupIDs.contains(groupID),
                              let (_, accountIDs) = accountIDsForGroups.first(where: { $0.0 == groupID }),
                              let groupItem = self.state.groups.first(where: { $0.groupUniqueID == groupID }),
                              let groupAccounts = groupItem.accounts else {
                            return nil
                        }
                        
                        let filteredAccounts = groupAccounts.filter { accountIDs.contains($0.accountUniqueID) }
                        let accountCardIDs = Set(accountCardIDsArray)
                        
                        // Вычисляем start и end балансы параллельно
                        async let startBalanceTask = self.calculateBalanceAtDate(
                            accounts: filteredAccounts,
                            date: startDate,
                            accountCardIDs: accountCardIDs,
                            debtAsNegative: true,
                            includeInitialBeforeCreation: true
                        )
                        async let endBalanceTask = self.calculateBalanceAtDate(
                            accounts: filteredAccounts,
                            date: endDate,
                            accountCardIDs: accountCardIDs,
                            debtAsNegative: true,
                            includeInitialBeforeCreation: false
                        )
                        
                        let startBalance = await startBalanceTask
                        let endBalance = await endBalanceTask
                        
                        // Для групп считаем чистый баланс (долги учитываем со знаком минус)
                        let delta = endBalance - startBalance
                        let percent = self.calculateDeltaPercent(delta: delta, startBalance: startBalance)
                        
                        return DynamicsBreakdownItem(
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
                        )
                    }
                }
                
                for await item in group {
                    if let item = item {
                        breakdown.append(item)
                    }
                }
            }
            
        case .accounts:
            // Показываем каждый счет отдельно - вычисляем параллельно
            // Подготавливаем данные для счетов до входа в TaskGroup
            let accountsData = await MainActor.run {
                accounts.compactMap { account -> (String, String, String, String, Bool, Bool)? in
                    guard let accountInfo = self.getAccountInfoForDynamics(account: account) else {
                        return nil
                    }
                    let accountID = account.accountUniqueID
                    let accountCardID = account.accountID
                    let isCard = account.accountType == .card
                    let isArchived = self.isAccountArchived(account)
                    return (accountID, accountInfo.name, accountCardID, accountID, isCard, isArchived)
                }
            }
            
            // Сохраняем accounts для использования в TaskGroup
            // Используем только ID для передачи между задачами, объекты получаем внутри @MainActor
            let accountUniqueIDs = await MainActor.run {
                Set(accounts.map { $0.accountUniqueID })
            }
            
            await withTaskGroup(of: DynamicsBreakdownItem?.self) { group in
                for (accountUniqueID, accountName, accountCardID, _, isCard, isArchived) in accountsData {
                    group.addTask { @MainActor in
                        let accountCardIDs = isCard ? Set([accountCardID]) : Set<String>()
                        
                        // Получаем account из getAccountsForCalculation() внутри @MainActor контекста
                        guard accountUniqueIDs.contains(accountUniqueID) else {
                            return nil
                        }
                        
                        let currentAccounts = self.getAccountsForCalculation()
                        guard let account = currentAccounts.first(where: { $0.accountUniqueID == accountUniqueID }) else {
                            return nil
                        }
                        
                        // Вычисляем start и end балансы параллельно
                        async let startBalanceTask = self.calculateBalanceAtDate(
                            accounts: [account],
                            date: startDate,
                            accountCardIDs: accountCardIDs,
                            debtAsNegative: false,
                            includeInitialBeforeCreation: true
                        )
                        async let endBalanceTask = self.calculateBalanceAtDate(
                            accounts: [account],
                            date: endDate,
                            accountCardIDs: accountCardIDs,
                            debtAsNegative: false,
                            includeInitialBeforeCreation: false
                        )
                        
                        let startBalance = await startBalanceTask
                        let endBalance = await endBalanceTask
                
                        // Определяем, является ли карта кредитной или это кредит
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
                        
                        // Для кредитных карт и кредитов: уменьшение долга = положительная дельта
                        // Инвертируем дельту: если долг уменьшился (endBalance < startBalance), это хорошо (+)
                        let rawDelta = endBalance - startBalance
                        let delta: Double
                        if isCreditCard || isCredit {
                            // Инвертируем: уменьшение долга (отрицательная rawDelta) становится положительной дельтой
                            delta = -rawDelta
                        } else {
                            delta = rawDelta
                        }
                        
                        // Расчет процента: для кредитных карт и кредитов считаем от начального долга
                        let percent = self.calculateDeltaPercent(delta: delta, startBalance: startBalance)
                        
                        // Получаем информацию о счете для иконки
                        guard let accountInfo = self.getAccountInfoForDynamics(account: account) else {
                            return nil
                        }
                        
                        return DynamicsBreakdownItem(
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
                        )
                    }
                }
                
                for await item in group {
                    if let item = item {
                        breakdown.append(item)
                    }
                }
            }
        }
        
        await MainActor.run {
            state.dynamicsBreakdown = breakdown
        }
    }
    
    func updateChartDataAsync() async {
        let accounts = getAccountsForCalculation()
        
        // Строим данные графика в зависимости от режима
        let useNetTotals = shouldUseNetTotals()
        switch state.dynamicsMode {
        case .aggregated:
            // Все счета в одну линию
            state.chartData = await buildTimeSeriesData(
                accounts: accounts,
                startDate: getPeriodDates().start,
                endDate: getPeriodDates().end,
                label: String(localized: "finances.dynamics.chart.total_label"),
                debtAsNegative: useNetTotals
            )
            
        case .byAccounts:
            // Каждый счет - отдельная линия
            var allDataPoints: [ChartDataPoint] = []
            for account in accounts {
                let accountData = await buildTimeSeriesData(
                    accounts: [account],
                    startDate: getPeriodDates().start,
                    endDate: getPeriodDates().end,
                    label: getAccountInfoForDynamics(account: account)?.name ?? String(localized: "finances.dynamics.chart.account_fallback"),
                    debtAsNegative: false
                )
                allDataPoints.append(contentsOf: accountData)
            }
            state.chartData = allDataPoints
            
        case .singleAccount(let accountID):
            // Один выбранный счет
            if let account = accounts.first(where: { $0.accountUniqueID == accountID }) {
                state.chartData = await buildTimeSeriesData(
                    accounts: [account],
                    startDate: getPeriodDates().start,
                    endDate: getPeriodDates().end,
                    label: getAccountInfoForDynamics(account: account)?.name ?? String(localized: "finances.dynamics.chart.account_fallback"),
                    debtAsNegative: false
                )
            } else {
                state.chartData = []
            }
        }
    }
    
    /// Построить временной ряд данных для графика
    func buildTimeSeriesData(
        accounts: [FinanceAccount],
        startDate: Date,
        endDate: Date,
        label: String,
        debtAsNegative: Bool = false
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
            includeInitialBeforeCreation: true
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

    func buildOverviewEntries(
        granularity: FinanceOverviewGranularity,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) async -> [FinanceOverviewPeriodEntry] {
        let accounts = getAccountsForCalculation()
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
        let daySnapshot = snapshotValues(for: date)
        
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
                
                if let archivedAt = card.archivedAt, date > archivedAt {
                    continue
                }
                
                guard card.includeInTotal else {
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

                // Определяем баланс на запрашиваемую дату
                var cardBalance: Double
                if date < card.createdAt {
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
                        .filter { $0.transactionDate >= card.createdAt && $0.transactionDate <= date }
                        .sorted(by: { $0.transactionDate < $1.transactionDate })
                    
                    for transaction in transactionsUpToDate {
                        switch transaction.transactionType {
                        case .income:
                            if transaction.cardID == account.accountID {
                                let converted = await convertTransactionAmount(
                                    transaction,
                                    to: accountCurrency
                                )
                                cardBalance += converted
                            }
                            
                        case .expense:
                            if transaction.cardID == account.accountID {
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
                if date >= liveStateEffectiveDate {
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
                
                if let archivedAt = credit.archivedAt, date > archivedAt {
                    continue
                }
                
                guard credit.includeInTotal else {
                    continue
                }
                
                accountCurrency = credit.currency
                shouldInclude = true
                
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
                
                if let archivedAt = investment.archivedAt, date > archivedAt {
                    continue
                }
                
                guard investment.includeInTotal else {
                    continue
                }
                
                accountCurrency = resolvedInvestmentCurrency(investment)
                shouldInclude = true
                
                // Активы = оценочная стоимость + история изменений
                var baseAmount = investment.hasInitialAmount ? investment.initialAmount : investment.amount
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
                
                var investmentBalance = investment.investmentType == .positive ? baseAmount : -baseAmount
                
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
                    
                    for transaction in balanceAdjustmentTransactions {
                        let converted = await convertTransactionAmount(
                            transaction,
                            to: accountCurrency
                        )
                        investmentBalance += converted
                    }

                    // Если история неполная (например, для рыночных активов при изменении цены/количества
                    // без создания balanceAdjustment), фиксируем актуальное значение на дату последнего обновления.
                    let actualSignedAmount = investment.investmentType == .positive ? investment.amount : -investment.amount
                    let lastTrackedInvestmentChangeDate = balanceAdjustmentTransactions
                        .map(\.transactionDate)
                        .max() ?? investment.createdAt
                    let liveStateEffectiveDate = max(lastTrackedInvestmentChangeDate, investment.updatedAt)
                    if date >= liveStateEffectiveDate {
                        let deltaToActual = actualSignedAmount - investmentBalance
                        if abs(deltaToActual) > 0.01 {
                            investmentBalance += deltaToActual
                        }
                    }
                    
                    accountBalance = investmentBalance
                }
            }

            if let snapshotValue = snapshotValue(for: account, in: daySnapshot) {
                accountBalance = snapshotValue.value
                accountCurrency = normalizedAuditCurrency(
                    snapshotValue.currencyCode,
                    fallback: accountCurrency
                )
            }
            
            if shouldInclude {
                // Конвертируем в валюту отображения
                let converted = await convertAmount(
                    value: accountBalance,
                    from: accountCurrency,
                    to: state.displayCurrency,
                    at: date
                )
                let isLiability = debtAsNegative && isLiabilityAccount(account)
                if isLiability {
                    totalBalance -= abs(converted)
                } else {
                    totalBalance += converted
                }
            }
        }
        
        // Сохраняем результат в кэш (ограничиваем размер кэша для экономии памяти)
        if balanceCache.count < 1000 {
            balanceCache[cacheKey] = totalBalance
        }
        
        return totalBalance
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
    
    func calculateTotalForAllGroups() async -> Double {
        var total: Double = 0.0
        for group in state.groups {
            total += await calculateGroupTotal(group: group)
        }
        return total
    }
    
    func calculateGroupTotal(group: FinanceGroup) async -> Double {
        var total: Double = 0.0
        
        guard let accounts = group.accounts else { return 0.0 }
        
        for account in accounts {
            if let accountInfo = getAccountInfoForDynamics(account: account) {
                let converted = await convertAmount(
                    value: accountInfo.amount,
                    from: accountInfo.currency,
                    to: state.displayCurrency
                )
                total += converted
            }
        }
        
        return total
    }

    func getAccountInfoForDynamics(account: FinanceAccount) -> (name: String, amount: Double, currency: String, icon: String, isCreditCardDebt: Bool)? {
        switch account.accountType {
        case .card:
            if let card = cardsCache[account.accountID] {
                if card.cardType == .credit, let limit = card.creditLimit {
                    let amount = max(0, limit - card.balance)
                    return (card.name, amount, card.currency, card.cardType.icon, true)
                }
                return (card.name, card.balance, card.currency, card.cardType.icon, false)
            }
        case .credit:
            if let credit = creditsCache[account.accountID] {
                return (credit.name, credit.remainingAmount, credit.currency, credit.creditType.icon, false)
            }
        case .investment:
            if let investment = investmentsCache[account.accountID] {
                return (investment.name, investment.amount, resolvedInvestmentCurrency(investment), investment.category.icon, false)
            }
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
                    state.currencyConversionWarning = String(localized: "finances.dynamics.warning.estimated_rate")
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
                state.currencyConversionWarning = String(localized: "finances.dynamics.warning.estimated_rate")
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

        let (startDate, endDate) = getPeriodDates()
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

    private func snapshotValues(for date: Date) -> [String: FinanceBalanceSnapshotValue] {
        let dayKey = FinanceBalanceDayKey(date: date).rawValue
        if let cached = dailyAuditSnapshotCache[dayKey] {
            return cached
        }

        let snapshot = auditStore.daySnapshot(for: FinanceBalanceDayKey(date: date))
        dailyAuditSnapshotCache[dayKey] = snapshot
        return snapshot
    }

    private func snapshotValue(
        for account: FinanceAccount,
        in daySnapshot: [String: FinanceBalanceSnapshotValue]
    ) -> FinanceBalanceSnapshotValue? {
        daySnapshot[accountKey(for: account)]
    }

    private func accountKey(for account: FinanceAccount) -> String {
        "\(account.accountTypeRaw):\(account.accountID)"
    }

    private func normalizedAuditCurrency(_ code: String, fallback: String) -> String {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.isEmpty ? fallback : normalized
    }
    
    /// Получить список счетов для выбранных групп
    func getAccountsForSelectedGroups() -> [FinanceAccount] {
        let groupsToShow = state.selectedGroupIDs.isEmpty
            ? state.groups
            : state.groups.filter { state.selectedGroupIDs.contains($0.groupUniqueID) }
        
        var accounts: [FinanceAccount] = []
        for group in groupsToShow {
            if let groupAccounts = group.accounts {
                accounts.append(contentsOf: groupAccounts)
            }
        }
        
        guard state.showArchivedAccounts == false else {
            return accounts
        }
        
        return accounts.filter { !isAccountArchived($0) }
    }

    /// Получить список счетов внутри группы (с учетом архива)
    func getAccounts(for group: FinanceGroup) -> [FinanceAccount] {
        guard let groupAccounts = group.accounts else { return [] }
        if state.showArchivedAccounts {
            return groupAccounts
        }
        return groupAccounts.filter { !isAccountArchived($0) }
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
