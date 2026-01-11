//
//  FinanceViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Finance State

struct FinanceState {
    /// Все группы
    var groups: [FinanceGroup] = []
    
    
    /// Показывать ли экран создания/редактирования группы
    var showGroupEditor: Bool = false
    
    /// Редактируемая группа (nil = новая группа)
    var editingGroup: FinanceGroup? = nil
    
    /// Показывать ли экран добавления счета
    var showAddAccountSheet: Bool = false
    
    /// Показывать ли экран создания карты
    var showCreateCardSheet: Bool = false
    
    /// Показывать ли экран создания кредита
    var showCreateCreditSheet: Bool = false
    
    /// Показывать ли экран создания актива
    var showCreateInvestmentSheet: Bool = false
    
    /// Выбранная группа для добавления счета
    var selectedGroupForAccount: FinanceGroup? = nil
    
    /// Показывать ли sheet выбора валюты для отображения
    var showDisplayCurrencySheet: Bool = false
    
    /// Валюта для отображения
    var displayCurrency: String = "RUB"
    
    /// Общая сумма всех групп (в выбранной валюте)
    var totalAmount: Double = 0.0
    
    /// Флаг загрузки курсов
    var isLoadingRates: Bool = false
    
    /// Доступные карты
    var availableCards: [Card] = []
    
    /// Доступные кредиты
    var availableCredits: [Credit] = []
    
    /// Доступные активы
    var availableInvestments: [Investment] = []
    
    /// ID группы с открытым свайпом (nil = нет открытого свайпа)
    var openedSwipeGroupID: String? = nil
    
    /// Множество ID групп с открытыми аккордеонами
    var expandedGroupIDs: Set<String> = []
    
    /// Словарь сумм групп по их ID
    var groupTotals: [String: Double] = [:]
}

// MARK: - Finance Actions

enum FinanceAction {
    case loadGroups
    case loadAccounts
    case addGroup
    case editGroup(FinanceGroup)
    case deleteGroup(FinanceGroup)
    case updateGroup(name: String, colorHex: String, displayCurrency: String?)
    case hideGroupEditor
    case showAddAccountSheet(FinanceGroup?)
    case hideAddAccountSheet
    case addAccountToGroup(accountType: FinanceAccountType, accountID: String, group: FinanceGroup?)
    case removeAccountFromGroup(FinanceAccount)
    case showCreateCardSheet
    case hideCreateCardSheet
    case showCreateCreditSheet
    case hideCreateCreditSheet
    case showCreateInvestmentSheet
    case hideCreateInvestmentSheet
    case showDisplayCurrencySheet
    case hideDisplayCurrencySheet
    case setDisplayCurrency(String)
    case setOpenedSwipeGroupID(String?)
    case moveGroup(from: Int, to: Int)
    case toggleGroupExpanded(String)
    case setGroupTotal(String, Double)
}

// MARK: - Finance ViewModel

@MainActor
final class FinanceViewModel: ViewModelProtocol {
    @Published var state = FinanceState()
    
    let modelContext: ModelContext
    
    private let defaults = UserDefaults.standard
    
    private var storedDisplayCurrency: String {
        get { defaults.string(forKey: "finance_display_currency") ?? "RUB" }
        set { defaults.set(newValue, forKey: "finance_display_currency") }
    }
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        state.displayCurrency = storedDisplayCurrency
        loadGroups()
        loadAccounts()
    }
    
    func handle(_ action: FinanceAction) {
        switch action {
        case .loadGroups:
            loadGroups()
            
        case .loadAccounts:
            loadAccounts()
            
        case .addGroup:
            state.editingGroup = nil
            state.showGroupEditor = true
            
        case .editGroup(let group):
            state.editingGroup = group
            state.showGroupEditor = true
            
        case .deleteGroup(let group):
            deleteGroup(group)
            
        case .updateGroup(let name, let colorHex, let displayCurrency):
            updateGroup(name: name, colorHex: colorHex, displayCurrency: displayCurrency)
            
        case .hideGroupEditor:
            state.showGroupEditor = false
            state.editingGroup = nil
            
        case .showAddAccountSheet(let group):
            state.selectedGroupForAccount = group
            state.showAddAccountSheet = true
            
        case .hideAddAccountSheet:
            state.showAddAccountSheet = false
            state.selectedGroupForAccount = nil
            
        case .addAccountToGroup(let accountType, let accountID, let group):
            addAccountToGroup(accountType: accountType, accountID: accountID, group: group)
            
        case .removeAccountFromGroup(let account):
            removeAccountFromGroup(account)
            
        case .showCreateCardSheet:
            state.showCreateCardSheet = true
            
        case .hideCreateCardSheet:
            state.showCreateCardSheet = false
            
        case .showCreateCreditSheet:
            state.showCreateCreditSheet = true
            
        case .hideCreateCreditSheet:
            state.showCreateCreditSheet = false
            
        case .showCreateInvestmentSheet:
            state.showCreateInvestmentSheet = true
            
        case .hideCreateInvestmentSheet:
            state.showCreateInvestmentSheet = false
            
        case .showDisplayCurrencySheet:
            state.showDisplayCurrencySheet = true
            
        case .hideDisplayCurrencySheet:
            state.showDisplayCurrencySheet = false
            
        case .setDisplayCurrency(let currency):
            state.displayCurrency = currency
            storedDisplayCurrency = currency
            calculateTotalAmount()
            
        case .setOpenedSwipeGroupID(let groupID):
            state.openedSwipeGroupID = groupID
            
        case .moveGroup(let from, let to):
            moveGroup(from: from, to: to)
            
        case .toggleGroupExpanded(let groupID):
            if state.expandedGroupIDs.contains(groupID) {
                state.expandedGroupIDs.remove(groupID)
            } else {
                state.expandedGroupIDs.insert(groupID)
            }
            
        case .setGroupTotal(let groupID, let total):
            state.groupTotals[groupID] = total
        }
    }
    
    // MARK: - Private Methods
    
    private func loadGroups() {
        let descriptor = FetchDescriptor<FinanceGroup>(
            sortBy: [
                SortDescriptor(\.order, order: .forward),
                SortDescriptor(\.createdAt, order: .forward)
            ]
        )
        if let groups = try? modelContext.fetch(descriptor) {
            state.groups = groups
            calculateTotalAmount()
        }
    }
    
    private func moveGroup(from: Int, to: Int) {
        guard from >= 0, to >= 0, from < state.groups.count, to < state.groups.count, from != to else {
            return
        }
        
        let group = state.groups[from]
        state.groups.remove(at: from)
        state.groups.insert(group, at: to)
        
        // Обновляем порядок всех групп
        for (index, group) in state.groups.enumerated() {
            group.order = index
        }
        
        do {
            try modelContext.save()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to save group order: \(error.localizedDescription)")
        }
    }
    
    private func loadAccounts() {
        // Загружаем карты, кредиты и активы
        let cardDescriptor = FetchDescriptor<Card>()
        state.availableCards = (try? modelContext.fetch(cardDescriptor)) ?? []
        
        let creditDescriptor = FetchDescriptor<Credit>()
        state.availableCredits = (try? modelContext.fetch(creditDescriptor)) ?? []
        
        let investmentDescriptor = FetchDescriptor<Investment>()
        state.availableInvestments = (try? modelContext.fetch(investmentDescriptor)) ?? []
        
        // Обновляем менеджеры
        CardManager.shared.setup(modelContext: modelContext)
        CreditManager.shared.setup(modelContext: modelContext)
        InvestmentManager.shared.setup(modelContext: modelContext)
    }
    
    private func calculateTotalAmount() {
        Task {
            await calculateTotalAmountAsync()
        }
    }
    
    private func calculateTotalAmountAsync() async {
        let displayCurrency = state.displayCurrency
        var total: Double = 0.0
        
        // Проходим по всем группам
        for group in state.groups {
            let groupTotal = await calculateGroupTotal(group: group, in: displayCurrency)
            total += groupTotal
        }
        
        state.totalAmount = total
    }
    
    /// Подсчитать сумму группы в указанной валюте
    func calculateGroupTotal(group: FinanceGroup, in currency: String) async -> Double {
        var total: Double = 0.0
        
        guard let accounts = group.accounts else { return 0.0 }
        
        for account in accounts {
            let amount = await getAccountAmount(account: account)
            if amount.currency == currency {
                total += amount.value
            } else {
                if let converted = await CurrencyRateService.shared.convert(
                    amount: amount.value,
                    from: amount.currency,
                    to: currency
                ) {
                    total += converted
                } else {
                    total += amount.value
                }
            }
        }
        
        return total
    }
    
    /// Получить сумму счета
    private func getAccountAmount(account: FinanceAccount) async -> (value: Double, currency: String) {
        switch account.accountType {
        case .card:
            if let card = state.availableCards.first(where: { $0.cardUniqueID == account.accountID }) {
                // Учитываем только если includeInTotal = true
                guard card.includeInTotal else { return (0.0, card.currency) }
                
                // Для кредитных карт учитываем долг (лимит - баланс)
                if card.cardType == .credit, let limit = card.creditLimit {
                    let debt = max(0, limit - card.balance)
                    return (card.balance - debt, card.currency)
                }
                return (card.balance, card.currency)
            }
            
        case .credit:
            if let credit = state.availableCredits.first(where: { $0.creditUniqueID == account.accountID }) {
                // Учитываем только если includeInTotal = true
                guard credit.includeInTotal else { return (0.0, credit.currency) }
                
                // Для кредитов учитываем остаток долга как отрицательное значение
                return (-credit.remainingAmount, credit.currency)
            }
            
        case .investment:
            if let investment = state.availableInvestments.first(where: { $0.investmentUniqueID == account.accountID }) {
                // Учитываем только если includeInTotal = true
                if investment.includeInTotal {
                    let value = investment.investmentType == .positive ? investment.amount : -investment.amount
                    return (value, investment.currency)
                }
            }
        }
        
        return (0.0, "RUB")
    }
    
    /// Получить информацию о счете для отображения
    func getAccountInfo(account: FinanceAccount) -> (name: String, amount: Double, currency: String, icon: String)? {
        switch account.accountType {
        case .card:
            if let card = state.availableCards.first(where: { $0.cardUniqueID == account.accountID }) {
                let amount = card.cardType == .credit && card.creditLimit != nil ? 
                    card.balance - max(0, card.creditLimit! - card.balance) : card.balance
                return (card.name, amount, card.currency, card.cardType.icon)
            }
            
        case .credit:
            if let credit = state.availableCredits.first(where: { $0.creditUniqueID == account.accountID }) {
                return (credit.name, credit.remainingAmount, credit.currency, credit.creditType.icon)
            }
            
        case .investment:
            if let investment = state.availableInvestments.first(where: { $0.investmentUniqueID == account.accountID }) {
                return (investment.name, investment.amount, investment.currency, investment.category.icon)
            }
        }
        
        return nil
    }
    
    func refreshRates() async {
        state.isLoadingRates = true
        defer { state.isLoadingRates = false }
        
        _ = await CurrencyRateService.shared.getRate(from: "USD", to: "RUB")
        await calculateTotalAmountAsync()
    }
    
    private func deleteGroup(_ group: FinanceGroup) {
        // Перемещаем все счета из удаляемой группы в первую доступную группу
        if let accounts = group.accounts, !accounts.isEmpty {
            // Находим первую доступную группу (не удаляемую)
            if let targetGroup = state.groups.first(where: { $0.id != group.id }) {
                for account in accounts {
                    account.group = targetGroup
                }
            } else {
                // Если нет других групп, удаляем счета вместе с группой
                // (они будут удалены каскадно через deleteRule: .cascade)
            }
        }
        
        modelContext.delete(group)
        
        do {
            try modelContext.save()
            loadGroups()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to delete group: \(error.localizedDescription)")
        }
    }
    
    private func updateGroup(name: String, colorHex: String, displayCurrency: String?) {
        let groupToUpdate: FinanceGroup
        if let existing = state.editingGroup {
            existing.name = name
            existing.colorHex = colorHex
            existing.displayCurrency = displayCurrency
            existing.updatedAt = Date()
            groupToUpdate = existing
        } else {
            // Находим максимальный order
            let maxOrder = state.groups.map { $0.order }.max() ?? -1
            let newGroup = FinanceGroup(name: name, colorHex: colorHex, order: maxOrder + 1)
            newGroup.displayCurrency = displayCurrency
            modelContext.insert(newGroup)
            groupToUpdate = newGroup
        }
        
        do {
            try modelContext.save()
            loadGroups()
            state.showGroupEditor = false
            state.editingGroup = nil
            // Пересчитываем сумму группы если изменилась валюта
            let groupID = groupToUpdate.groupUniqueID
            Task {
                let currency = displayCurrency ?? state.displayCurrency
                let total = await calculateGroupTotal(group: groupToUpdate, in: currency)
                state.groupTotals[groupID] = total
            }
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to save group: \(error.localizedDescription)")
        }
    }
    
    private func addAccountToGroup(accountType: FinanceAccountType, accountID: String, group: FinanceGroup?) {
        guard let targetGroup = group else {
            AppLogger.log(.error, category: "Finance", "Group is required")
            return
        }
        
        // Проверяем, не добавлен ли уже этот счет в любую группу
        let allAccountsDescriptor = FetchDescriptor<FinanceAccount>()
        if let allAccounts = try? modelContext.fetch(allAccountsDescriptor) {
            let existingAccount = allAccounts.first { account in
                account.accountType == accountType && account.accountID == accountID
            }
            
            if let existing = existingAccount {
                // Перемещаем счет в новую группу
                existing.group = targetGroup
                existing.updatedAt = Date()
            } else {
                // Создаем новый счет
                let account = FinanceAccount(accountType: accountType, accountID: accountID)
                account.group = targetGroup
                modelContext.insert(account)
            }
        } else {
            // Создаем новый счет
            let account = FinanceAccount(accountType: accountType, accountID: accountID)
            account.group = targetGroup
            modelContext.insert(account)
        }
        
        do {
            try modelContext.save()
            loadGroups()
            state.showAddAccountSheet = false
            state.selectedGroupForAccount = nil
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to add account: \(error.localizedDescription)")
        }
    }
    
    private func removeAccountFromGroup(_ account: FinanceAccount) {
        modelContext.delete(account)
        
        do {
            try modelContext.save()
            loadGroups()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to remove account: \(error.localizedDescription)")
        }
    }
}
