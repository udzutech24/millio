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
        
        // Загружаем доступные валюты
        loadAvailableCurrencies()
        
        // Обновляем данные графика
        updateChartData()
        
        state.isLoading = false
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
        
        // Собираем все уникальные даты событий (создание/обновление счетов)
        var eventDates: Set<Date> = [startDate, endDate]
        for account in accounts {
            eventDates.insert(account.createdAt)
            eventDates.insert(account.updatedAt)
        }
        
        // Фильтруем даты в пределах периода и сортируем
        let sortedDates = eventDates
            .filter { $0 >= startDate && $0 <= endDate }
            .sorted()
        
        // Если дат мало, добавляем промежуточные точки для плавности графика
        var datesToShow = sortedDates
        if sortedDates.count < 10 {
            // Добавляем точки каждые N дней в зависимости от периода
            let stepDays = max(1, state.period.days / 20)
            var currentDate = startDate
            while currentDate <= endDate {
                if !datesToShow.contains(where: { calendar.isDate($0, inSameDayAs: currentDate) }) {
                    datesToShow.append(currentDate)
                }
                currentDate = calendar.date(byAdding: .day, value: stepDays, to: currentDate) ?? endDate
            }
            datesToShow.sort()
        }
        
        // Для каждой даты рассчитываем накопленную сумму
        var cumulativeTotal: Double = 0.0
        
        for date in datesToShow {
            // Рассчитываем сумму всех счетов, которые были созданы до или в эту дату
            var totalAtDate: Double = 0.0
            
            for account in accounts {
                // Счет учитывается только если он был создан до или в эту дату
                if account.createdAt <= date {
                    if let accountInfo = financeViewModel.getAccountInfo(account: account) {
                        // Используем текущее значение счета (так как истории изменений нет)
                        let amount = await convertAmount(
                            value: accountInfo.amount,
                            from: accountInfo.currency,
                            to: state.displayCurrency
                        )
                        totalAtDate += amount
                    }
                }
            }
            
            dataPoints.append(ChartDataPoint(
                date: date,
                value: totalAtDate,
                label: label
            ))
        }
        
        return dataPoints
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
