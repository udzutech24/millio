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
    var period: DynamicsPeriod = .month
    
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

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String
}

// MARK: - Dynamics Mode

enum DynamicsMode {
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
    
    private let defaults = UserDefaults.standard
    
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
            let accounts = getAccountsForSelectedGroups()
            state.selectedAccountIDs = Set(accounts.map { $0.accountUniqueID })
            // Автоматически переключаем режим
            if state.selectedAccountIDs.count == 1 {
                state.dynamicsMode = .singleAccount(state.selectedAccountIDs.first!)
            } else if state.selectedAccountIDs.count > 1 {
                state.dynamicsMode = .byAccounts
            } else {
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
                // Автоматически переключаем режим, если выбран один счет
                if state.selectedAccountIDs.count == 1 {
                    state.dynamicsMode = .singleAccount(state.selectedAccountIDs.first!)
                } else if state.selectedAccountIDs.count > 1 {
                    state.dynamicsMode = .byAccounts
                } else {
                    state.dynamicsMode = .aggregated
                }
                updateChartData()
            }
        }
    }
    
    private func loadData() {
        state.isLoading = true
        
        // Загружаем группы и счета из financeViewModel
        state.groups = financeViewModel.state.groups
        state.availableCards = financeViewModel.state.availableCards
        state.availableCredits = financeViewModel.state.availableCredits
        state.availableInvestments = financeViewModel.state.availableInvestments
        
        // Загружаем транзакции Cashflow для расчета динамики балансов
        loadCashflowTransactions()
        
        // Загружаем доступные валюты
        loadAvailableCurrencies()
        
        // Обновляем данные графика
        updateChartData()
        
        state.isLoading = false
    }
    
    private func loadCashflowTransactions() {
        let descriptor = FetchDescriptor<CashflowTransaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .forward)]
        )
        if let transactions = try? modelContext.fetch(descriptor) {
            state.cashflowTransactions = transactions
        }
    }
    
    private func loadAvailableCurrencies() {
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
    
    private func updateChartData() {
        Task {
            await updateChartDataAsync()
            await updateCurrentBalanceAndDelta()
            await updateDynamicsBreakdown()
        }
    }
    
    /// Получить даты периода
    private func getPeriodDates() -> (start: Date, end: Date) {
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
    private func updateCurrentBalanceAndDelta() async {
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
        let percent = startBalance != 0 
            ? (delta / abs(startBalance)) * 100 
            : (state.currentBalance > 0 ? 100.0 : (state.currentBalance < 0 ? -100.0 : 0.0))
        state.periodDelta = (delta, percent)
    }
    
    /// Получить счета для расчета (в зависимости от фильтров)
    private func getAccountsForCalculation() -> [FinanceAccount] {
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
    private func updateDynamicsBreakdown() async {
        let accounts = getAccountsForCalculation()
        let (startDate, endDate) = getPeriodDates()
        
        var breakdown: [DynamicsBreakdownItem] = []
        
        switch state.viewMode {
        case .groups:
            // Группируем по группам
            let groupsToShow = state.selectedGroupIDs.isEmpty
                ? state.groups
                : state.groups.filter { state.selectedGroupIDs.contains($0.groupUniqueID) }
            
            for group in groupsToShow {
                guard let groupAccounts = group.accounts else { continue }
                
                // Фильтруем счета группы, если есть выбор счетов
                let filteredAccounts = state.selectedAccountIDs.isEmpty
                    ? groupAccounts
                    : groupAccounts.filter { state.selectedAccountIDs.contains($0.accountUniqueID) }
                
                if filteredAccounts.isEmpty { continue }
                
                let startBalance = await calculateBalanceAtDate(
                    accounts: filteredAccounts,
                    date: startDate,
                    accountCardIDs: Set(filteredAccounts.compactMap { $0.accountType == .card ? $0.accountID : nil })
                )
                
                let endBalance = await calculateBalanceAtDate(
                    accounts: filteredAccounts,
                    date: endDate,
                    accountCardIDs: Set(filteredAccounts.compactMap { $0.accountType == .card ? $0.accountID : nil })
                )
                
                let delta = endBalance - startBalance
                let percent = startBalance != 0 
                    ? (delta / abs(startBalance)) * 100 
                    : (endBalance > 0 ? 100.0 : (endBalance < 0 ? -100.0 : 0.0))
                
                breakdown.append(DynamicsBreakdownItem(
                    id: group.groupUniqueID,
                    name: group.name,
                    startValue: startBalance,
                    endValue: endBalance,
                    delta: delta,
                    deltaPercent: percent
                ))
            }
            
        case .accounts:
            // Показываем каждый счет отдельно
            for account in accounts {
                guard let accountInfo = financeViewModel.getAccountInfo(account: account) else { continue }
                
                let accountCardIDs = account.accountType == .card ? Set([account.accountID]) : Set<String>()
                
                let startBalance = await calculateBalanceAtDate(
                    accounts: [account],
                    date: startDate,
                    accountCardIDs: accountCardIDs
                )
                
                let endBalance = await calculateBalanceAtDate(
                    accounts: [account],
                    date: endDate,
                    accountCardIDs: accountCardIDs
                )
                
                let delta = endBalance - startBalance
                let percent = startBalance != 0 
                    ? (delta / abs(startBalance)) * 100 
                    : (endBalance > 0 ? 100.0 : (endBalance < 0 ? -100.0 : 0.0))
                
                breakdown.append(DynamicsBreakdownItem(
                    id: account.accountUniqueID,
                    name: accountInfo.name,
                    startValue: startBalance,
                    endValue: endBalance,
                    delta: delta,
                    deltaPercent: percent
                ))
            }
        }
        
        state.dynamicsBreakdown = breakdown
    }
    
    private func updateChartDataAsync() async {
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
    private func buildTimeSeriesData(
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
        
        // Добавляем даты обновления карт
        for cardID in accountCardIDs {
            if let card = state.availableCards.first(where: { $0.cardUniqueID == cardID }) {
                eventDates.insert(card.createdAt)
                eventDates.insert(card.updatedAt) // Дата изменения баланса при быстром редактировании
            }
        }
        
        // Добавляем даты обновления кредитов
        let accountCreditIDs = Set(accounts.compactMap { account -> String? in
            if account.accountType == .credit {
                return account.accountID
            }
            return nil
        })
        for creditID in accountCreditIDs {
            if let credit = state.availableCredits.first(where: { $0.creditUniqueID == creditID }) {
                eventDates.insert(credit.createdAt)
                eventDates.insert(credit.updatedAt)
            }
        }
        
        // Добавляем даты обновления инвестиций
        let accountInvestmentIDs = Set(accounts.compactMap { account -> String? in
            if account.accountType == .investment {
                return account.accountID
            }
            return nil
        })
        for investmentID in accountInvestmentIDs {
            if let investment = state.availableInvestments.first(where: { $0.investmentUniqueID == investmentID }) {
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
        let periodDays = state.period.days ?? 30
        let stepDays = max(1, periodDays / 15)
        var currentDate = startDate
        while currentDate <= endDate {
            let dayStart = calendar.startOfDay(for: currentDate)
            // Добавляем промежуточную точку только если в этот день нет важных событий
            if !importantDays.contains(dayStart) {
                intermediateDates.append(currentDate)
            }
            currentDate = calendar.date(byAdding: .day, value: stepDays, to: currentDate) ?? endDate
        }
        
        // Рассчитываем баланс для каждого дня с важными событиями
        // Для каждого дня берем баланс на конец дня (после всех транзакций в этот день)
        var eventBalances: [Date: Double] = [:]
        for dayStart in importantDays {
            // Рассчитываем баланс на конец этого дня
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: dayStart) ?? dayStart
            let balance = await calculateBalanceAtDate(
                accounts: accounts,
                date: endOfDay,
                accountCardIDs: accountCardIDs
            )
            eventBalances[dayStart] = balance
        }
        
        // Рассчитываем баланс для промежуточных точек (группируем по дням)
        var intermediateBalances: [Date: Double] = [:]
        for intermediateDate in intermediateDates {
            let dayStart = calendar.startOfDay(for: intermediateDate)
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: intermediateDate) ?? intermediateDate
            let balance = await calculateBalanceAtDate(
                accounts: accounts,
                date: endOfDay,
                accountCardIDs: accountCardIDs
            )
            intermediateBalances[dayStart] = balance
        }
        
        // Объединяем все балансы (важные события имеют приоритет над промежуточными точками)
        var allBalances = intermediateBalances
        for (day, balance) in eventBalances {
            allBalances[day] = balance // Важные события перезаписывают промежуточные точки
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
    private func calculateBalanceAtDate(
        accounts: [FinanceAccount],
        date: Date,
        accountCardIDs: Set<String>
    ) async -> Double {
        var totalBalance: Double = 0.0
        
        for account in accounts {
            // Счет учитывается только если он был создан до или в эту дату
            if account.createdAt <= date {
                if let accountInfo = financeViewModel.getAccountInfo(account: account) {
                    // Начальный баланс счета (будет пересчитан для карт)
                    var accountBalance = accountInfo.amount
                    
                    // Для карт учитываем транзакции Cashflow и пересчитываем баланс
                    if account.accountType == .card, accountCardIDs.contains(account.accountID) {
                        guard let card = state.availableCards.first(where: { $0.cardUniqueID == account.accountID }) else {
                            // Если карта не найдена, используем значение из accountInfo
                            let converted = await convertAmount(
                                value: accountBalance,
                                from: accountInfo.currency,
                                to: state.displayCurrency
                            )
                            totalBalance += converted
                            continue
                        }
                        
                        // Используем текущий баланс карты и откатываем транзакции назад до нужной даты
                        // Это проще и надежнее, чем пытаться рассчитать начальный баланс
                        var cardBalance = card.balance
                        
                        // Откатываем все транзакции после ТОЧНОЙ даты события (от новых к старым)
                        // Сортируем транзакции по убыванию даты
                        // Важно: используем точную дату, а не конец дня, чтобы транзакции в тот же день учитывались правильно
                        let transactionsAfterDate = state.cashflowTransactions
                            .filter { $0.transactionDate > date && $0.transactionDate <= Date() }
                            .sorted(by: { $0.transactionDate > $1.transactionDate })
                        
                        for transaction in transactionsAfterDate {
                            switch transaction.transactionType {
                            case .income:
                                if transaction.cardID == account.accountID {
                                    // Откатываем доход - вычитаем
                                    let converted = await convertAmount(
                                        value: transaction.amount,
                                        from: transaction.currency,
                                        to: accountInfo.currency
                                    )
                                    cardBalance -= converted
                                }
                                
                            case .expense:
                                if transaction.cardID == account.accountID {
                                    // Откатываем расход - возвращаем деньги
                                    let converted = await convertAmount(
                                        value: transaction.amount,
                                        from: transaction.currency,
                                        to: accountInfo.currency
                                    )
                                    cardBalance += converted
                                }
                                
                            case .transfer:
                                if transaction.cardID == account.accountID {
                                    // Откатываем перевод с карты - возвращаем деньги
                                    let converted = await convertAmount(
                                        value: transaction.amount,
                                        from: transaction.currency,
                                        to: accountInfo.currency
                                    )
                                    cardBalance += converted
                                } else if transaction.toCardID == account.accountID {
                                    // Откатываем перевод на карту - забираем деньги
                                    let converted = await convertAmount(
                                        value: transaction.amount,
                                        from: transaction.currency,
                                        to: accountInfo.currency
                                    )
                                    cardBalance -= converted
                                }
                                
                            case .exchange:
                                break
                            }
                        }
                        
                        // Используем рассчитанный баланс
                        accountBalance = cardBalance
                        
                        // Для кредитных карт преобразуем баланс в задолженность (если нужно)
                        if card.cardType == .credit, let limit = card.creditLimit {
                            // Для кредитных карт в динамике показываем задолженность как положительное значение
                            // Задолженность = лимит - баланс
                            accountBalance = max(0, limit - accountBalance)
                        }
                    }
                    
                    // Конвертируем в валюту отображения
                    let converted = await convertAmount(
                        value: accountBalance,
                        from: accountInfo.currency,
                        to: state.displayCurrency
                    )
                    totalBalance += converted
                }
            }
        }
        
        return totalBalance
    }
    
    private func calculateTotalForAllGroups() async -> Double {
        var total: Double = 0.0
        for group in state.groups {
            total += await calculateGroupTotal(group: group)
        }
        return total
    }
    
    private func calculateGroupTotal(group: FinanceGroup) async -> Double {
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
