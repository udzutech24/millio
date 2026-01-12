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
    
    /// Показывать ли sheet с деталями
    var showDetailsSheet: Bool = false
    
    /// Режим просмотра одной группы (скрывает фильтры групп)
    var isSingleGroupMode: Bool = false
    
    /// Все транзакции Cashflow для расчета динамики балансов
    var cashflowTransactions: [CashflowTransaction] = []
}

// MARK: - Dynamics Period

enum DynamicsPeriod: String, CaseIterable {
    case day = "День"
    case week = "Неделя"
    case month = "Месяц"
    case year = "Год"
    
    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .year: return 365
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

// MARK: - Finance Dynamics Actions

enum FinanceDynamicsAction {
    case loadData
    case selectGroups(Set<String>)
    case selectAccounts(Set<String>)
    case setDisplayCurrency(String)
    case setPeriod(DynamicsPeriod)
    case toggleGroup(String)
    case toggleAccount(String)
    case showDetailsSheet
    case hideDetailsSheet
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
    
    init(modelContext: ModelContext, financeViewModel: FinanceViewModel, initialGroupID: String? = nil, initialGroupCurrency: String? = nil) {
        self.modelContext = modelContext
        self.financeViewModel = financeViewModel
        
        // Если передан initialGroupID, устанавливаем его как выбранную группу и включаем режим одной группы
        if let groupID = initialGroupID {
            state.selectedGroupIDs = [groupID]
            state.isSingleGroupMode = true
        }
        
        // Если у группы есть своя валюта, используем её, иначе используем общую валюту
        if let groupCurrency = initialGroupCurrency {
            state.displayCurrency = groupCurrency
        } else {
            state.displayCurrency = financeViewModel.state.displayCurrency
        }
        
        // Если период установлен на "День", меняем на "Месяц" (так как период "День" убран из фильтров)
        if state.period == .day {
            state.period = .month
        }
    }
    
    func handle(_ action: FinanceDynamicsAction) {
        switch action {
        case .loadData:
            loadData()
            
        case .selectGroups(let groupIDs):
            // В режиме одной группы запрещаем изменение групп
            if !state.isSingleGroupMode {
                state.selectedGroupIDs = groupIDs
                state.selectedAccountIDs = [] // Сбрасываем выбор счетов при изменении групп
                updateChartData()
            }
            
        case .selectAccounts(let accountIDs):
            state.selectedAccountIDs = accountIDs
            updateChartData()
            
        case .setDisplayCurrency(let currency):
            state.displayCurrency = currency
            updateChartData()
            
        case .setPeriod(let period):
            state.period = period
            updateChartData()
            
        case .toggleGroup(let groupID):
            // В режиме одной группы запрещаем изменение групп
            if !state.isSingleGroupMode {
                if state.selectedGroupIDs.contains(groupID) {
                    state.selectedGroupIDs.remove(groupID)
                } else {
                    state.selectedGroupIDs.insert(groupID)
                }
                state.selectedAccountIDs = [] // Сбрасываем выбор счетов
                updateChartData()
            }
            
        case .toggleAccount(let accountID):
            if state.selectedAccountIDs.contains(accountID) {
                state.selectedAccountIDs.remove(accountID)
            } else {
                state.selectedAccountIDs.insert(accountID)
            }
            updateChartData()
            
        case .showDetailsSheet:
            state.showDetailsSheet = true
            
        case .hideDetailsSheet:
            state.showDetailsSheet = false
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
        }
    }
    
    private func updateChartDataAsync() async {
        var dataPoints: [ChartDataPoint] = []
        
        // Определяем период для графика
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .day, value: -state.period.days, to: endDate) ?? endDate
        
        // Определяем, какие группы и счета показывать
        let groupsToShow = state.selectedGroupIDs.isEmpty 
            ? state.groups 
            : state.groups.filter { state.selectedGroupIDs.contains($0.groupUniqueID) }
        
        // Собираем все счета из выбранных групп
        var accountsToShow: [FinanceAccount] = []
        for group in groupsToShow {
            if let accounts = group.accounts {
                if state.selectedAccountIDs.isEmpty {
                    accountsToShow.append(contentsOf: accounts)
                } else {
                    accountsToShow.append(contentsOf: accounts.filter { 
                        state.selectedAccountIDs.contains($0.accountUniqueID) 
                    })
                }
            }
        }
        
        // Если ничего не выбрано, показываем общую сумму всех групп
        if groupsToShow.isEmpty && accountsToShow.isEmpty {
            // Собираем все счета из всех групп
            var allAccounts: [FinanceAccount] = []
            for group in state.groups {
                if let accounts = group.accounts {
                    allAccounts.append(contentsOf: accounts)
                }
            }
            dataPoints = await buildTimeSeriesData(
                accounts: allAccounts,
                startDate: startDate,
                endDate: endDate,
                label: "Общая сумма"
            )
        } else if accountsToShow.isEmpty {
            // Показываем суммы по группам - объединяем все счета из выбранных групп
            var allGroupAccounts: [FinanceAccount] = []
            for group in groupsToShow {
                if let accounts = group.accounts {
                    allGroupAccounts.append(contentsOf: accounts)
                }
            }
            dataPoints = await buildTimeSeriesData(
                accounts: allGroupAccounts,
                startDate: startDate,
                endDate: endDate,
                label: groupsToShow.count == 1 ? groupsToShow.first?.name ?? "Группа" : "Выбранные группы"
            )
        } else {
            // Показываем суммы по выбранным счетам
            dataPoints = await buildTimeSeriesData(
                accounts: accountsToShow,
                startDate: startDate,
                endDate: endDate,
                label: accountsToShow.count == 1 ? (financeViewModel.getAccountInfo(account: accountsToShow.first!)?.name ?? "Счет") : "Выбранные счета"
            )
        }
        
        state.chartData = dataPoints
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
        
        // Добавляем даты транзакций Cashflow, которые влияют на выбранные счета
        let accountCardIDs = Set(accounts.compactMap { account -> String? in
            if account.accountType == .card {
                return account.accountID
            }
            return nil
        })
        
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
        
        // Фильтруем даты в пределах периода и сортируем
        let sortedDates = eventDates
            .filter { $0 >= startDate && $0 <= endDate }
            .sorted()
        
        // Всегда добавляем промежуточные точки для плавности графика
        // Но не дублируем даты, которые уже есть в eventDates
        var datesToShow = sortedDates
        let stepDays = max(1, state.period.days / 15) // Уменьшил делитель для большего количества точек
        var currentDate = startDate
        while currentDate <= endDate {
            if !datesToShow.contains(where: { calendar.isDate($0, inSameDayAs: currentDate) }) {
                datesToShow.append(currentDate)
            }
            currentDate = calendar.date(byAdding: .day, value: stepDays, to: currentDate) ?? endDate
        }
        datesToShow.sort()
        
        // Группируем даты по дням и рассчитываем баланс для каждого дня
        var dailyBalances: [Date: Double] = [:]
        
        for date in datesToShow {
            // Рассчитываем баланс на конец этого дня с учетом транзакций
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: date) ?? date
            let balance = await calculateBalanceAtDate(
                accounts: accounts,
                date: endOfDay,
                accountCardIDs: accountCardIDs
            )
            
            // Группируем по дню (без учета времени)
            let dayStart = calendar.startOfDay(for: date)
            // Всегда используем баланс на конец дня (после всех транзакций в этот день)
            // Это гарантирует, что расходы правильно отображаются
            dailyBalances[dayStart] = balance
        }
        
        // Преобразуем в массив ChartDataPoint, убирая дубликаты по дням
        for (date, balance) in dailyBalances.sorted(by: { $0.key < $1.key }) {
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
                        
                        // Откатываем все транзакции после нужной даты (от новых к старым)
                        // Сортируем транзакции по убыванию даты
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
