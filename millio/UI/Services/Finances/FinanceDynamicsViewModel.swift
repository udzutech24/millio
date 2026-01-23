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
}

// MARK: - Finance Dynamics ViewModel

@MainActor
final class FinanceDynamicsViewModel: ViewModelProtocol {
    typealias State = FinanceDynamicsState
    typealias Action = FinanceDynamicsAction
    
    @Published var state = FinanceDynamicsState()
    
    let modelContext: ModelContext
    let financeViewModel: FinanceViewModel
    
    let defaults = UserDefaults.standard
    
    // Кэши для оптимизации производительности
    var cardsCache: [String: Card] = [:]
    var creditsCache: [String: Credit] = [:]
    var investmentsCache: [String: Investment] = [:]
    var transactionsByCardCache: [String: [CashflowTransaction]] = [:]
    var initialBalancesCache: [String: Double] = [:]
    var balanceCache: [String: Double] = [:] // Кэш для calculateBalanceAtDate: "accountID_date" -> balance
    
    init(modelContext: ModelContext, financeViewModel: FinanceViewModel, initialGroupID: String? = nil, initialGroupCurrency: String? = nil, initialAccountID: String? = nil, initialAccountCurrency: String? = nil) {
        self.modelContext = modelContext
        self.financeViewModel = financeViewModel
        
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
            state.displayCurrency = currency
            updateChartData()
            
        case .setPeriod(let period):
            state.period = period
            if period != .custom {
                state.customPeriod = nil
            }
            updateChartData()
            
        case .setCustomPeriod(let start, let end):
            state.period = .custom
            state.customPeriod = (start, end)
            updateChartData()
            
        case .selectDateOnChart(let date):
            state.selectedDate = date
            Task {
                await updateCurrentBalanceAndDelta()
            }
            
        case .setDynamicsMode(let mode):
            state.dynamicsMode = mode
            updateChartData()
            
        case .setViewMode(let mode):
            state.viewMode = mode
            Task {
                await updateDynamicsBreakdown()
            }
            
        case .showFilterSheet:
            state.showFilterSheet = true
            
        case .hideFilterSheet:
            state.showFilterSheet = false
            
        case .showPeriodSelector:
            state.showPeriodSelector = true
            
        case .hidePeriodSelector:
            state.showPeriodSelector = false
            
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
                state.dynamicsMode = .singleAccount(state.selectedAccountIDs.first!)
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
                    state.dynamicsMode = .singleAccount(state.selectedAccountIDs.first!)
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
        cardsCache = Dictionary(uniqueKeysWithValues: state.availableCards.map { ($0.cardUniqueID, $0) })
        
        // Кэш кредитов
        creditsCache = Dictionary(uniqueKeysWithValues: state.availableCredits.map { ($0.creditUniqueID, $0) })
        
        // Кэш инвестиций
        investmentsCache = Dictionary(uniqueKeysWithValues: state.availableInvestments.map { ($0.investmentUniqueID, $0) })
        
        // Очищаем кэши балансов при перезагрузке данных
        initialBalancesCache.removeAll()
        balanceCache.removeAll()
        transactionsByCardCache.removeAll()
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
    
    /// Предфильтровать транзакции по картам для быстрого доступа
    func rebuildTransactionsCache() {
        transactionsByCardCache.removeAll()
        for transaction in state.cashflowTransactions {
            if let cardID = transaction.cardID {
                transactionsByCardCache[cardID, default: []].append(transaction)
            }
            if let toCardID = transaction.toCardID {
                transactionsByCardCache[toCardID, default: []].append(transaction)
            }
        }
    }
    
    func loadAvailableCurrencies() {
        Task {
            // Загружаем курсы для получения списка валют
            _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
            
            let fromRateSource = Set(CurrencyRateService.shared.getAvailableCurrencies())
            
            // Собираем валюты из всех счетов
            var currencies = Set<String>()
            for card in state.availableCards {
                currencies.insert(card.currency)
            }
            for credit in state.availableCredits {
                currencies.insert(credit.currency)
            }
            for investment in state.availableInvestments {
                currencies.insert(investment.currency)
            }
            
            // Объединяем с валютами из источника курсов
            currencies = currencies.union(fromRateSource)
            
            state.availableCurrencies = Array(currencies).sorted()
        }
    }
    
    func updateChartData() {
        Task {
            await updateChartDataAsync()
            await updateCurrentBalanceAndDelta()
            await updateDynamicsBreakdown()
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
            if let customPeriod = state.customPeriod {
                return (customPeriod.start, customPeriod.end)
            }
            startDate = endDate
        }
        
        return (startDate, endDate)
    }
    
    /// Обновить текущий баланс и дельту
    func updateCurrentBalanceAndDelta() async {
        let (startDate, endDate) = getPeriodDates()
        state.periodStartDate = startDate
        state.periodEndDate = endDate
        
        // Получаем счета для расчета
        let accounts = getAccountsForCalculation()
        
        // Рассчитываем текущий баланс
        let targetDate = state.selectedDate ?? endDate
        state.currentBalance = await calculateBalanceAtDate(
            accounts: accounts,
            date: targetDate,
            accountCardIDs: Set(accounts.compactMap { $0.accountType == .card ? $0.accountID : nil })
        )
        
        // Рассчитываем баланс на начало периода
        let startBalance = await calculateBalanceAtDate(
            accounts: accounts,
            date: startDate,
            accountCardIDs: Set(accounts.compactMap { $0.accountType == .card ? $0.accountID : nil })
        )
        
        // Рассчитываем дельту
        let delta = state.currentBalance - startBalance
        let percent: Double
        if abs(startBalance) < 0.01 {
            // Если начальный баланс близок к нулю, процентный прирост очень большой или бесконечный
            if abs(state.currentBalance) < 0.01 {
                percent = 0.0
            } else if state.currentBalance > 0 {
                // Очень большой положительный прирост (можно использовать Double.infinity, но для отображения используем большое число)
                percent = 999999.0
            } else {
                // Очень большой отрицательный прирост
                percent = -999999.0
            }
        } else {
            percent = (delta / abs(startBalance)) * 100
        }
        state.periodDelta = (delta, percent)
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
        return accounts.filter { account in
            if seenIDs.contains(account.accountUniqueID) {
                return false
            }
            seenIDs.insert(account.accountUniqueID)
            return true
        }
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
                            accountCardIDs: accountCardIDs
                        )
                        async let endBalanceTask = self.calculateBalanceAtDate(
                            accounts: filteredAccounts,
                            date: endDate,
                            accountCardIDs: accountCardIDs
                        )
                        
                        let startBalance = await startBalanceTask
                        let endBalance = await endBalanceTask
                        
                        let delta = endBalance - startBalance
                        let percent: Double
                        if abs(startBalance) < 0.01 {
                            // Если начальный баланс близок к нулю, процентный прирост очень большой или бесконечный
                            if abs(endBalance) < 0.01 {
                                percent = 0.0
                            } else if endBalance > 0 {
                                percent = 999999.0
                            } else {
                                percent = -999999.0
                            }
                        } else {
                            percent = (delta / abs(startBalance)) * 100
                        }
                        
                        return DynamicsBreakdownItem(
                            id: groupID,
                            name: groupName,
                            startValue: startBalance,
                            endValue: endBalance,
                            delta: delta,
                            deltaPercent: percent,
                            icon: nil,
                            accountType: nil,
                            isCreditCard: false
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
                accounts.compactMap { account -> (String, String, String, String, Bool)? in
                    guard let accountInfo = self.financeViewModel.getAccountInfo(account: account) else {
                        return nil
                    }
                    let accountID = account.accountUniqueID
                    let accountCardID = account.accountID
                    let isCard = account.accountType == .card
                    return (accountID, accountInfo.name, accountCardID, accountID, isCard)
                }
            }
            
            // Сохраняем accounts для использования в TaskGroup
            // Используем только ID для передачи между задачами, объекты получаем внутри @MainActor
            let accountUniqueIDs = await MainActor.run {
                Set(accounts.map { $0.accountUniqueID })
            }
            
            await withTaskGroup(of: DynamicsBreakdownItem?.self) { group in
                for (accountUniqueID, accountName, accountCardID, _, isCard) in accountsData {
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
                            accountCardIDs: accountCardIDs
                        )
                        async let endBalanceTask = self.calculateBalanceAtDate(
                            accounts: [account],
                            date: endDate,
                            accountCardIDs: accountCardIDs
                        )
                        
                        let startBalance = await startBalanceTask
                        let endBalance = await endBalanceTask
                
                        let delta = endBalance - startBalance
                        let percent: Double
                        if abs(startBalance) < 0.01 {
                            // Если начальный баланс близок к нулю, процентный прирост очень большой или бесконечный
                            if abs(endBalance) < 0.01 {
                                percent = 0.0
                            } else if endBalance > 0 {
                                percent = 999999.0
                            } else {
                                percent = -999999.0
                            }
                        } else {
                            percent = (delta / abs(startBalance)) * 100
                        }
                        
                        // Получаем информацию о счете для иконки
                        guard let accountInfo = self.financeViewModel.getAccountInfo(account: account) else {
                            return nil
                        }
                        
                        // Определяем, является ли карта кредитной
                        let isCreditCard: Bool
                        if account.accountType == .card {
                            if let card = self.state.availableCards.first(where: { $0.cardUniqueID == account.accountID }) {
                                isCreditCard = card.cardType == .credit
                            } else {
                                isCreditCard = false
                            }
                        } else {
                            isCreditCard = false
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
                            isCreditCard: isCreditCard
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
        switch state.dynamicsMode {
        case .aggregated:
            // Все счета в одну линию
            state.chartData = await buildTimeSeriesData(
                accounts: accounts,
                startDate: getPeriodDates().start,
                endDate: getPeriodDates().end,
                label: "Общая сумма"
            )
            
        case .byAccounts:
            // Каждый счет - отдельная линия
            var allDataPoints: [ChartDataPoint] = []
            for account in accounts {
                let accountData = await buildTimeSeriesData(
                    accounts: [account],
                    startDate: getPeriodDates().start,
                    endDate: getPeriodDates().end,
                    label: financeViewModel.getAccountInfo(account: account)?.name ?? "Счет"
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
                    label: financeViewModel.getAccountInfo(account: account)?.name ?? "Счет"
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
        label: String
    ) async -> [ChartDataPoint] {
        var dataPoints: [ChartDataPoint] = []
        let calendar = Calendar.current
        
        // Собираем все уникальные даты событий (создание/обновление счетов и транзакции)
        var eventDates: Set<Date> = [startDate, endDate]
        
        // Добавляем даты создания и обновления счетов
        for account in accounts {
            eventDates.insert(account.createdAt)
            eventDates.insert(account.updatedAt)
        }
        
        // Добавляем даты обновления самих карт/кредитов/инвестиций
        // Это важно для отслеживания ручных изменений баланса (быстрое редактирование)
        let accountCardIDs = Set(accounts.compactMap { account -> String? in
            if account.accountType == .card {
                return account.accountID
            }
            return nil
        })
        
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
            case .exchange:
                // Обмен валют не влияет напрямую на балансы карт
                break
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
                    let balance = await self.calculateBalanceAtDate(
                        accounts: accounts,
                        date: endOfDay,
                        accountCardIDs: accountCardIDs
                    )
                    return (dayStart, balance)
                }
            }
            
            for await (dayStart, balance) in group {
                eventBalances[dayStart] = balance
            }
        }
        
        // Рассчитываем баланс для промежуточных точек параллельно (группируем по дням)
        var intermediateBalances: [Date: Double] = [:]
        await withTaskGroup(of: (Date, Double).self) { group in
            for intermediateDate in intermediateDates {
                group.addTask {
                    let dayStart = calendar.startOfDay(for: intermediateDate)
                    let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: intermediateDate) ?? intermediateDate
                    let balance = await self.calculateBalanceAtDate(
                        accounts: accounts,
                        date: endOfDay,
                        accountCardIDs: accountCardIDs
                    )
                    return (dayStart, balance)
                }
            }
            
            for await (dayStart, balance) in group {
                intermediateBalances[dayStart] = balance
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
                        let dayStart = calendar.startOfDay(for: intermediateDate)
                        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: intermediateDate) ?? intermediateDate
                        let balance = await self.calculateBalanceAtDate(
                            accounts: accounts,
                            date: endOfDay,
                            accountCardIDs: accountCardIDs
                        )
                        return (dayStart, balance)
                    }
                }
                
                for await (dayStart, balance) in group {
                    additionalBalances[dayStart] = balance
                }
            }
        }
        
        // Объединяем все балансы (важные события имеют приоритет над промежуточными точками)
        var allBalances = intermediateBalances
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
    
    /// Рассчитать баланс счетов на конкретную дату с учетом транзакций
    func calculateBalanceAtDate(
        accounts: [FinanceAccount],
        date: Date,
        accountCardIDs: Set<String>
    ) async -> Double {
        // Проверяем кэш
        let cacheKey = "\(accounts.map { $0.accountUniqueID }.joined(separator: "_"))_\(date.timeIntervalSince1970)"
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
                
                // Карта учитывается только если она была создана до или в эту дату
                guard card.createdAt <= date else {
                    continue
                }
                
                guard card.includeInTotal else {
                    continue
                }
                
                accountCurrency = card.currency
                shouldInclude = true
                
                // Кэшируем начальный баланс при создании карты
                let initialBalanceKey = "initial_\(account.accountID)"
                var initialBalanceAtCreation: Double
                if let cached = initialBalancesCache[initialBalanceKey] {
                    initialBalanceAtCreation = cached
                } else {
                    // Рассчитываем начальный баланс при создании карты один раз
                    initialBalanceAtCreation = card.balance
                    // Используем предфильтрованные транзакции из кэша
                    let cardTransactions = transactionsByCardCache[account.accountID] ?? []
                    let transactionsSinceCreation = cardTransactions
                        .filter { $0.transactionDate >= card.createdAt && $0.transactionDate <= Date() }
                        .sorted(by: { $0.transactionDate > $1.transactionDate })
                    
                    for transaction in transactionsSinceCreation {
                        switch transaction.transactionType {
                        case .income:
                            if transaction.cardID == account.accountID {
                                let converted = await convertAmount(
                                    value: transaction.amount,
                                    from: transaction.currency,
                                    to: accountCurrency
                                )
                                initialBalanceAtCreation -= converted
                            }
                            
                        case .expense:
                            if transaction.cardID == account.accountID {
                                let converted = await convertAmount(
                                    value: transaction.amount,
                                    from: transaction.currency,
                                    to: accountCurrency
                                )
                                initialBalanceAtCreation += converted
                            }
                            
                        case .transfer:
                            if transaction.cardID == account.accountID {
                                let converted = await convertAmount(
                                    value: transaction.amount,
                                    from: transaction.currency,
                                    to: accountCurrency
                                )
                                initialBalanceAtCreation += converted
                            } else if transaction.toCardID == account.accountID {
                                let converted = await convertAmount(
                                    value: transaction.amount,
                                    from: transaction.currency,
                                    to: accountCurrency
                                )
                                initialBalanceAtCreation -= converted
                            }
                            
                        case .exchange:
                            // Для обмена валют учитываем изменения баланса
                            if transaction.cardID == account.accountID {
                                if let fromAmount = transaction.exchangeFromAmount {
                                    let converted = await convertAmount(
                                        value: fromAmount,
                                        from: transaction.exchangeFromCurrency ?? accountCurrency,
                                        to: accountCurrency
                                    )
                                    initialBalanceAtCreation += converted
                                }
                                if let toAmount = transaction.exchangeToAmount {
                                    let converted = await convertAmount(
                                        value: toAmount,
                                        from: transaction.exchangeToCurrency ?? accountCurrency,
                                        to: accountCurrency
                                    )
                                    initialBalanceAtCreation -= converted
                                }
                            }
                        }
                    }
                    // Кэшируем начальный баланс
                    initialBalancesCache[initialBalanceKey] = initialBalanceAtCreation
                }
                
                // Определяем баланс на запрашиваемую дату
                var cardBalance: Double
                if date < card.createdAt {
                    // Запрашиваемая дата раньше создания карты
                    // Используем начальный баланс при создании (который пользователь ввел)
                    cardBalance = initialBalanceAtCreation
                } else {
                    // Запрашиваемая дата после или в момент создания карты
                    // Начинаем с начального баланса при создании и применяем транзакции до запрашиваемой даты
                    cardBalance = initialBalanceAtCreation
                    
                    // Используем предфильтрованные транзакции из кэша вместо фильтрации всех транзакций
                    let cardTransactions = transactionsByCardCache[account.accountID] ?? []
                    let transactionsUpToDate = cardTransactions
                        .filter { $0.transactionDate >= card.createdAt && $0.transactionDate <= date }
                        .sorted(by: { $0.transactionDate < $1.transactionDate })
                    
                    for transaction in transactionsUpToDate {
                        switch transaction.transactionType {
                        case .income:
                            if transaction.cardID == account.accountID {
                                let converted = await convertAmount(
                                    value: transaction.amount,
                                    from: transaction.currency,
                                    to: accountCurrency
                                )
                                cardBalance += converted
                            }
                            
                        case .expense:
                            if transaction.cardID == account.accountID {
                                let converted = await convertAmount(
                                    value: transaction.amount,
                                    from: transaction.currency,
                                    to: accountCurrency
                                )
                                cardBalance = max(0, cardBalance - converted)
                            }
                            
                        case .transfer:
                            if transaction.cardID == account.accountID {
                                let converted = await convertAmount(
                                    value: transaction.amount,
                                    from: transaction.currency,
                                    to: accountCurrency
                                )
                                cardBalance = max(0, cardBalance - converted)
                            } else if transaction.toCardID == account.accountID {
                                let converted = await convertAmount(
                                    value: transaction.amount,
                                    from: transaction.currency,
                                    to: accountCurrency
                                )
                                cardBalance += converted
                            }
                            
                        case .exchange:
                            // Для обмена валют учитываем изменения баланса
                            if transaction.cardID == account.accountID {
                                if let fromAmount = transaction.exchangeFromAmount {
                                    let converted = await convertAmount(
                                        value: fromAmount,
                                        from: transaction.exchangeFromCurrency ?? accountCurrency,
                                        to: accountCurrency
                                    )
                                    cardBalance = max(0, cardBalance - converted)
                                }
                                if let toAmount = transaction.exchangeToAmount {
                                    let converted = await convertAmount(
                                        value: toAmount,
                                        from: transaction.exchangeToCurrency ?? accountCurrency,
                                        to: accountCurrency
                                    )
                                    cardBalance += converted
                                }
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
                
            case .credit:
                // Используем кэш вместо first(where:) для O(1) поиска
                guard let credit = creditsCache[account.accountID] else {
                    continue
                }
                
                // Кредит учитывается только если он был начат до или в эту дату
                guard credit.startDate <= date else {
                    continue
                }
                
                guard credit.includeInTotal else {
                    continue
                }
                
                accountCurrency = credit.currency
                shouldInclude = true
                
                // Рассчитываем остаток долга на нужную дату
                accountBalance = calculateCreditRemainingAmount(credit: credit, at: date)
                
            case .investment:
                // Используем кэш вместо first(where:) для O(1) поиска
                guard let investment = investmentsCache[account.accountID] else {
                    continue
                }
                
                // Актив учитывается только если он был создан до или в эту дату
                guard investment.createdAt <= date else {
                    continue
                }
                
                guard investment.includeInTotal else {
                    continue
                }
                
                accountCurrency = investment.currency
                shouldInclude = true
                
                // Для активов используем текущую сумму (предполагаем, что она не менялась)
                // В будущем можно добавить историю изменений активов
                accountBalance = investment.investmentType == .positive ? investment.amount : -investment.amount
            }
            
            if shouldInclude {
                // Конвертируем в валюту отображения
                let converted = await convertAmount(
                    value: accountBalance,
                    from: accountCurrency,
                    to: state.displayCurrency
                )
                totalBalance += converted
            }
        }
        
        // Сохраняем результат в кэш (ограничиваем размер кэша для экономии памяти)
        if balanceCache.count < 1000 {
            balanceCache[cacheKey] = totalBalance
        }
        
        return totalBalance
    }
    
    /// Рассчитать остаток долга по кредиту на конкретную дату
    func calculateCreditRemainingAmount(credit: Credit, at date: Date) -> Double {
        let calendar = Calendar.current
        
        // Если кредит еще не начался, остаток равен сумме кредита
        if date < credit.startDate {
            return credit.amount
        }
        
        // Если кредит закрыт и дата после закрытия, остаток равен 0
        if credit.isClosed, let endDate = credit.endDate, date > endDate {
            return 0.0
        }
        
        // Рассчитываем количество прошедших месяцев с начала кредита до указанной даты
        let components = calendar.dateComponents([.month], from: credit.startDate, to: date)
        let monthsPassed = max(0, components.month ?? 0)
        let monthsPaid = min(monthsPassed, credit.termMonths)
        let monthsRemaining = max(0, credit.termMonths - monthsPaid)
        
        // Если все платежи сделаны, остаток равен нулю
        guard monthsRemaining > 0 else {
            return 0.0
        }
        
        // Если платежей не было, остаток равен сумме кредита минус досрочные платежи
        guard monthsPaid > 0 else {
            return max(0, credit.amount - credit.earlyPaymentsAmount)
        }
        
        let monthlyRate = credit.interestRate / 12.0 / 100.0
        
        if monthlyRate == 0 {
            // Без процентов: просто вычитаем выплаченное
            let paid = credit.monthlyPayment * Double(monthsPaid)
            return max(0, credit.amount - paid - credit.earlyPaymentsAmount)
        } else {
            // Формула для расчета остатка долга через текущую стоимость оставшихся платежей
            let discountFactor = pow(1 + monthlyRate, -Double(monthsRemaining))
            let remaining = credit.monthlyPayment * ((1 - discountFactor) / monthlyRate)
            return max(0, remaining - credit.earlyPaymentsAmount)
        }
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
            if let accountInfo = financeViewModel.getAccountInfo(account: account) {
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
    
    func convertAmount(value: Double, from: String, to: String) async -> Double {
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
        
        return accounts
    }
}

