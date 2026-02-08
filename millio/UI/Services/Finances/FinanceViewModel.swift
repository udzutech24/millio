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
    
    /// Показывать ли sheet выбора дополнительной валюты для отображения
    var showSecondaryDisplayCurrencySheet: Bool = false
    
    /// Валюта для отображения
    var displayCurrency: String = "RUB"
    
    /// Дополнительная валюта для отображения
    var secondaryDisplayCurrency: String? = nil
    
    /// Общая сумма всех групп (в выбранной валюте)
    var totalAmount: Double = 0.0
    
    /// Общая сумма всех групп (в дополнительной валюте)
    var secondaryTotalAmount: Double = 0.0
    
    /// Флаг загрузки курсов
    var isLoadingRates: Bool = false
    
    /// Доступные карты
    var availableCards: [Card] = []
    
    /// Доступные кредиты
    var availableCredits: [Credit] = []
    
    /// Доступные активы
    var availableInvestments: [Investment] = []

    /// Архивные карты
    var archivedCards: [Card] = []

    /// Архивные кредиты
    var archivedCredits: [Credit] = []

    /// Архивные активы
    var archivedInvestments: [Investment] = []

    var hasArchivedAccounts: Bool {
        !archivedCards.isEmpty || !archivedCredits.isEmpty || !archivedInvestments.isEmpty
    }
    
    /// Непривязанные карты (не добавленные ни в одну группу)
    var unattachedCards: [Card] = []
    
    /// Непривязанные кредиты (не добавленные ни в одну группу)
    var unattachedCredits: [Credit] = []
    
    /// Непривязанные активы (не добавленные ни в одну группу)
    var unattachedInvestments: [Investment] = []
    
    /// Показывать ли редактор карты для редактирования
    var showEditCardSheet: Bool = false
    
    /// Показывать ли редактор кредита для редактирования
    var showEditCreditSheet: Bool = false
    
    /// Показывать ли редактор инвестиции для редактирования
    var showEditInvestmentSheet: Bool = false
    
    /// ID редактируемой карты
    var editingCardID: String? = nil
    
    /// ID редактируемого кредита
    var editingCreditID: String? = nil
    
    /// ID редактируемой инвестиции
    var editingInvestmentID: String? = nil
    
    /// Множество ID групп с открытыми аккордеонами
    var expandedGroupIDs: Set<String> = []
    
    /// Словарь сумм групп по их ID
    var groupTotals: [String: Double] = [:]
    
    /// Показывать ли sheet быстрого редактирования суммы счета
    var showQuickEditAccountSheet: Bool = false
    
    /// Счет для быстрого редактирования суммы
    var quickEditAccount: FinanceAccount? = nil
    
    /// Показывать ли динамику группы
    var showGroupDynamics: Bool = false
    
    /// Группа для отображения динамики
    var selectedGroupForDynamics: FinanceGroup? = nil
    
    /// Показывать ли динамику счета
    var showAccountDynamics: Bool = false
    
    /// Счет для отображения динамики
    var selectedAccountForDynamics: FinanceAccount? = nil
    
    /// Показывать ли sheet настроек цели накопления
    var showSavingsGoalSheet: Bool = false
    
    /// Включена ли цель накопления
    var isSavingsGoalEnabled: Bool = false
    
    /// Сумма цели накопления
    var savingsGoalAmount: Double = 0.0
    
    /// Скрыты ли суммы денег (показывать точки вместо цифр)
    var isAmountHidden: Bool = false
    
    /// Сообщение об ошибке или предупреждении при конвертации валют
    var currencyConversionWarning: String? = nil
}

// MARK: - Finance Actions

enum FinanceAction {
    case loadGroups
    case loadAccounts
    case addGroup
    case editGroup(FinanceGroup)
    case deleteGroup(FinanceGroup)
    case updateGroup(name: String, colorHex: String, displayCurrency: String?, isFavorite: Bool, priority: GroupPriority)
    case hideGroupEditor
    case showAddAccountSheet(FinanceGroup?)
    case hideAddAccountSheet
    case addAccountToGroup(accountType: FinanceAccountType, accountID: String, group: FinanceGroup?)
    case restoreArchivedAccountToGroup(accountType: FinanceAccountType, accountID: String, group: FinanceGroup?)
    case removeAccountFromGroup(FinanceAccount)
    case deleteAccountPermanently(FinanceAccount)
    case showCreateCardSheet
    case hideCreateCardSheet
    case showCreateCreditSheet
    case hideCreateCreditSheet
    case showCreateInvestmentSheet
    case hideCreateInvestmentSheet
    case showDisplayCurrencySheet
    case hideDisplayCurrencySheet
    case setDisplayCurrency(String)
    case showSecondaryDisplayCurrencySheet
    case hideSecondaryDisplayCurrencySheet
    case setSecondaryDisplayCurrency(String?)
    case toggleGroupExpanded(String)
    case toggleGroupFavorite(FinanceGroup)
    case setGroupPriority(FinanceGroup, GroupPriority)
    case setGroupTotal(String, Double)
    case editAccount(FinanceAccount)
    case hideEditCardSheet
    case hideEditCreditSheet
    case hideEditInvestmentSheet
    case showQuickEditAccountSheet(FinanceAccount)
    case hideQuickEditAccountSheet
    case updateAccountAmount(FinanceAccount, Double)
    case showGroupDynamics(FinanceGroup)
    case hideGroupDynamics
    case showAccountDynamics(FinanceAccount)
    case hideAccountDynamics
    case showSavingsGoalSheet
    case hideSavingsGoalSheet
    case setSavingsGoalEnabled(Bool)
    case setSavingsGoalAmount(Double)
    case toggleAmountVisibility
}

// MARK: - Finance ViewModel

@MainActor
final class FinanceViewModel: ViewModelProtocol {
    @Published var state = FinanceState()
    
    let modelContext: ModelContext

    /// Сервис курсов валют (внедряется для тестируемости)
    let currencyService: CurrencyRateServiceProtocol

    private let defaults = UserDefaults.standard
    private var financeEventsSubscriptionID: UUID?

    /// Быстрые словари для поиска счетов по ID (O(1) вместо O(n))
    private var cardByID: [String: Card] = [:]
    private var creditByID: [String: Credit] = [:]
    private var investmentByID: [String: Investment] = [:]
    private var allCardByID: [String: Card] = [:]
    private var allCreditByID: [String: Credit] = [:]
    private var allInvestmentByID: [String: Investment] = [:]
    
    private var storedDisplayCurrency: String {
        get { defaults.string(forKey: "finance_display_currency") ?? SettingsManager.shared.primaryCurrencyCode }
        set { defaults.set(newValue, forKey: "finance_display_currency") }
    }
    
    private var storedSecondaryDisplayCurrency: String? {
        get {
            defaults.string(forKey: "finance_secondary_display_currency") ?? "USD"
        }
        set { defaults.set(newValue, forKey: "finance_secondary_display_currency") }
    }
    
    private var storedSavingsGoalEnabled: Bool {
        get { defaults.bool(forKey: "finance_savings_goal_enabled") }
        set { defaults.set(newValue, forKey: "finance_savings_goal_enabled") }
    }
    
    private var storedSavingsGoalAmount: Double {
        get { defaults.double(forKey: "finance_savings_goal_amount") }
        set { defaults.set(newValue, forKey: "finance_savings_goal_amount") }
    }
    
    private var storedAmountHidden: Bool {
        get { defaults.bool(forKey: "finance_amount_hidden") }
        set { defaults.set(newValue, forKey: "finance_amount_hidden") }
    }
    
    init(modelContext: ModelContext, currencyService: CurrencyRateServiceProtocol? = nil, skipInitialLoad: Bool = false) {
        self.modelContext = modelContext
        self.currencyService = currencyService ?? CurrencyRateService.shared
        state.displayCurrency = storedDisplayCurrency
        state.secondaryDisplayCurrency = storedSecondaryDisplayCurrency
        state.isSavingsGoalEnabled = storedSavingsGoalEnabled
        state.savingsGoalAmount = storedSavingsGoalAmount
        state.isAmountHidden = storedAmountHidden
        subscribeToFinanceEvents()
        if !skipInitialLoad {
            loadGroups()
            loadAccounts()
        }
    }

    deinit {
        if let subscriptionID = financeEventsSubscriptionID {
            Task { @MainActor in
                EventBus.shared.unsubscribe(subscriptionID)
            }
        }
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
            
        case .updateGroup(let name, let colorHex, let displayCurrency, let isFavorite, let priority):
            updateGroup(name: name, colorHex: colorHex, displayCurrency: displayCurrency, isFavorite: isFavorite, priority: priority)
            
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

        case .restoreArchivedAccountToGroup(let accountType, let accountID, let group):
            restoreArchivedAccountToGroup(accountType: accountType, accountID: accountID, group: group)
            
        case .removeAccountFromGroup(let account):
            removeAccountFromGroup(account)
        case .deleteAccountPermanently(let account):
            deleteAccountPermanently(account)
            
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
            
        case .showSecondaryDisplayCurrencySheet:
            state.showSecondaryDisplayCurrencySheet = true
            
        case .hideSecondaryDisplayCurrencySheet:
            state.showSecondaryDisplayCurrencySheet = false
            
        case .setDisplayCurrency(let currency):
            state.displayCurrency = currency
            storedDisplayCurrency = currency
            Task {
                await refreshRates()
                await calculateTotalAmountAsync()
            }
            
        case .setSecondaryDisplayCurrency(let currency):
            state.secondaryDisplayCurrency = currency
            storedSecondaryDisplayCurrency = currency
            Task {
                await refreshRates()
                await calculateTotalAmountAsync()
            }
            
        case .toggleGroupExpanded(let groupID):
            if state.expandedGroupIDs.contains(groupID) {
                state.expandedGroupIDs.remove(groupID)
            } else {
                state.expandedGroupIDs.insert(groupID)
            }
            
        case .setGroupTotal(let groupID, let total):
            state.groupTotals[groupID] = total
            
        case .editAccount(let account):
            editAccount(account)
            
        case .hideEditCardSheet:
            state.showEditCardSheet = false
            state.editingCardID = nil
            
        case .hideEditCreditSheet:
            state.showEditCreditSheet = false
            state.editingCreditID = nil
            
        case .hideEditInvestmentSheet:
            state.showEditInvestmentSheet = false
            state.editingInvestmentID = nil
            
        case .showQuickEditAccountSheet(let account):
            state.quickEditAccount = account
            state.showQuickEditAccountSheet = true
            
        case .hideQuickEditAccountSheet:
            state.showQuickEditAccountSheet = false
            state.quickEditAccount = nil
            
        case .updateAccountAmount(let account, let newAmount):
            updateAccountAmount(account: account, newAmount: newAmount)
            
        case .toggleGroupFavorite(let group):
            group.isFavorite.toggle()
            group.updatedAt = Date()
            do {
                try modelContext.save()
                loadGroups()
            } catch {
                AppLogger.log(.error, category: "Finance", "Failed to toggle group favorite: \(error.localizedDescription)")
            }
            
        case .setGroupPriority(let group, let priority):
            group.priority = priority
            group.updatedAt = Date()
            do {
                try modelContext.save()
                loadGroups()
            } catch {
                AppLogger.log(.error, category: "Finance", "Failed to set group priority: \(error.localizedDescription)")
            }
            
        case .showGroupDynamics(let group):
            state.selectedGroupForDynamics = group
            state.showGroupDynamics = true
            
        case .hideGroupDynamics:
            state.showGroupDynamics = false
            state.selectedGroupForDynamics = nil
            
        case .showAccountDynamics(let account):
            state.selectedAccountForDynamics = account
            state.showAccountDynamics = true
            
        case .hideAccountDynamics:
            state.showAccountDynamics = false
            state.selectedAccountForDynamics = nil
            
        case .showSavingsGoalSheet:
            state.showSavingsGoalSheet = true
            
        case .hideSavingsGoalSheet:
            state.showSavingsGoalSheet = false
            
        case .setSavingsGoalEnabled(let enabled):
            state.isSavingsGoalEnabled = enabled
            storedSavingsGoalEnabled = enabled
            
        case .setSavingsGoalAmount(let amount):
            state.savingsGoalAmount = amount
            storedSavingsGoalAmount = amount
            
        case .toggleAmountVisibility:
            state.isAmountHidden.toggle()
            storedAmountHidden = state.isAmountHidden
    }
    }
    
    // MARK: - Private Methods
    
    private func loadGroups() {
        let descriptor = FetchDescriptor<FinanceGroup>()
        if let groups = try? modelContext.fetch(descriptor) {
            // Сортируем: сначала избранные, потом по приоритету, потом по дате создания
            state.groups = groups.sorted { group1, group2 in
                // Сначала избранные
                if group1.isFavorite != group2.isFavorite {
                    return group1.isFavorite
                }
                // Потом по приоритету
                if group1.priority.sortOrder != group2.priority.sortOrder {
                    return group1.priority.sortOrder < group2.priority.sortOrder
                }
                // Потом по дате создания
                return group1.createdAt < group2.createdAt
            }
            // Обновляем списки непривязанных элементов после загрузки групп
            updateUnattachedItems()
            calculateTotalAmount()
        }
    }
    
    private func loadAccounts() {
        // Загружаем карты, кредиты и активы
        let cardDescriptor = FetchDescriptor<Card>()
        let allCards = (try? modelContext.fetch(cardDescriptor)) ?? []
        state.availableCards = allCards.filter { $0.archivedAt == nil }
        state.archivedCards = allCards.filter { $0.archivedAt != nil }
        
        let creditDescriptor = FetchDescriptor<Credit>()
        let allCredits = (try? modelContext.fetch(creditDescriptor)) ?? []
        state.availableCredits = allCredits.filter { $0.archivedAt == nil }
        state.archivedCredits = allCredits.filter { $0.archivedAt != nil }
        
        let investmentDescriptor = FetchDescriptor<Investment>()
        let allInvestments = (try? modelContext.fetch(investmentDescriptor)) ?? []
        state.availableInvestments = allInvestments.filter { $0.archivedAt == nil }
        state.archivedInvestments = allInvestments.filter { $0.archivedAt != nil }

        rebuildAccountCaches()
        rebuildAllAccountCaches(
            cards: allCards,
            credits: allCredits,
            investments: allInvestments
        )
        cleanupInvalidFinanceAccounts()
        
        // Обновляем менеджеры
        CardManager.shared.setup(modelContext: modelContext)
        CreditManager.shared.setup(modelContext: modelContext)
        InvestmentManager.shared.setup(modelContext: modelContext)
        
        // Вычисляем непривязанные элементы
        updateUnattachedItems()
    }
    
    /// Обновить списки непривязанных элементов
    private func updateUnattachedItems() {
        // Получаем все привязанные счета из всех групп
        var attachedCardIDs: Set<String> = []
        var attachedCreditIDs: Set<String> = []
        var attachedInvestmentIDs: Set<String> = []
        
        for group in state.groups {
            guard let accounts = group.accounts else { continue }
            for account in accounts {
                switch account.accountType {
                case .card:
                    attachedCardIDs.insert(account.accountID)
                case .credit:
                    attachedCreditIDs.insert(account.accountID)
                case .investment:
                    attachedInvestmentIDs.insert(account.accountID)
                }
            }
        }
        
        // Фильтруем непривязанные элементы
        state.unattachedCards = state.availableCards.filter { !attachedCardIDs.contains($0.cardUniqueID) }
        state.unattachedCredits = state.availableCredits.filter { !attachedCreditIDs.contains($0.creditUniqueID) }
        state.unattachedInvestments = state.availableInvestments.filter { !attachedInvestmentIDs.contains($0.investmentUniqueID) }
    }

    private func subscribeToFinanceEvents() {
        financeEventsSubscriptionID = EventBus.shared.subscribe { [weak self] event in
            guard let self else { return }
            switch event {
            case FinanceEvent.creditsUpdated:
                self.handleCreditsUpdated()
            case FinanceEvent.cardsUpdated:
                self.loadAccounts()
                Task {
                    await self.refreshGroupTotalsAndAmounts()
                }
            case BackupEvent.restoreCompleted:
                self.loadGroups()
                self.loadAccounts()
                Task {
                    await self.refreshGroupTotalsAndAmounts()
                }
            default:
                break
            }
        }
    }

    private func handleCreditsUpdated() {
        loadAccounts()
        Task {
            await refreshGroupTotalsAndAmounts()
        }
    }

    private func refreshGroupTotalsAndAmounts() async {
        for group in state.groups {
            let currency = group.displayCurrency ?? state.displayCurrency
            let total = await calculateGroupTotal(group: group, in: currency)
            state.groupTotals[group.groupUniqueID] = total
        }
        await calculateTotalAmountAsync()
    }

    /// Перестраиваем кэш счетов по ID после загрузки данных
    private func rebuildAccountCaches() {
        cardByID = [:]
        creditByID = [:]
        investmentByID = [:]

        for card in state.availableCards {
            cardByID[card.cardUniqueID] = card
        }
        for credit in state.availableCredits {
            creditByID[credit.creditUniqueID] = credit
        }
        for investment in state.availableInvestments {
            investmentByID[investment.investmentUniqueID] = investment
        }
    }

    /// Перестраиваем кэш всех счетов (включая архивные) для валидности связей
    private func rebuildAllAccountCaches(cards: [Card], credits: [Credit], investments: [Investment]) {
        allCardByID = [:]
        allCreditByID = [:]
        allInvestmentByID = [:]
        
        for card in cards {
            allCardByID[card.cardUniqueID] = card
        }
        for credit in credits {
            allCreditByID[credit.creditUniqueID] = credit
        }
        for investment in investments {
            allInvestmentByID[investment.investmentUniqueID] = investment
        }
    }

    /// Удаляем "сиротские" связи, чтобы не накапливать мусор в базе
    private func cleanupInvalidFinanceAccounts() {
        let descriptor = FetchDescriptor<FinanceAccount>()
        guard let accounts = try? modelContext.fetch(descriptor) else { return }

        var removedCount = 0

        for account in accounts {
            // Если счет больше не связан с группой — удаляем запись связи
            if account.group == nil {
                modelContext.delete(account)
                removedCount += 1
                continue
            }

            // Если целевой объект не найден — удаляем связь
            switch account.accountType {
            case .card:
                if allCardByID[account.accountID] == nil {
                    modelContext.delete(account)
                    removedCount += 1
                }
            case .credit:
                if allCreditByID[account.accountID] == nil {
                    modelContext.delete(account)
                    removedCount += 1
                }
            case .investment:
                if allInvestmentByID[account.accountID] == nil {
                    modelContext.delete(account)
                    removedCount += 1
                }
            }
        }

        guard removedCount > 0 else { return }

        do {
            try modelContext.save()
            AppLogger.log(.info, category: "Finance", "Removed \(removedCount) invalid finance account links")
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to cleanup finance accounts: \(error.localizedDescription)")
        }
    }
    
    private func calculateTotalAmount() {
        Task {
            await calculateTotalAmountAsync()
        }
    }
    
    func calculateTotalAmountAsync() async {
        let displayCurrency = state.displayCurrency
        var total: Double = 0.0
        var warnings: [String] = []
        
        state.currencyConversionWarning = nil
        
        // Собираем все валюты из всех групп
        var allCurrenciesNeeded = Set<String>()
        for group in state.groups {
            let currencies = await collectCurrenciesFromGroup(group: group)
            allCurrenciesNeeded.formUnion(currencies)
            // Добавляем валюту группы
            let groupCurrency = group.displayCurrency ?? state.displayCurrency
            allCurrenciesNeeded.insert(groupCurrency)
        }
        // Добавляем displayCurrency
        allCurrenciesNeeded.insert(displayCurrency)
        // Добавляем secondaryDisplayCurrency, если задан
        if let secondaryCurrency = state.secondaryDisplayCurrency {
            allCurrenciesNeeded.insert(secondaryCurrency)
        }
        
        // Если есть несколько валют, обновляем курсы один раз
        if allCurrenciesNeeded.count > 1 {
            await currencyService.forceRefreshRates()
        }
        
        // Для каждого group вычисляем сумму в его валюте (или в state.displayCurrency, если не задана)
        for group in state.groups {
            let groupCurrency = group.displayCurrency ?? state.displayCurrency
            let groupTotalInGroupCurrency = await calculateGroupTotal(group: group, in: groupCurrency)
            
            // Конвертируем сумму группы в displayCurrency если нужно
            if groupCurrency == displayCurrency {
                total += groupTotalInGroupCurrency
            } else {
                if let rate = await currencyService.getRate(from: groupCurrency, to: displayCurrency), rate > 0 {
                    total += groupTotalInGroupCurrency * rate
                } else {
                    // Если курс недоступен, просто пропускаем сумму этой группы и добавляем предупреждение
                    warnings.append("Курс конвертации \(groupCurrency) → \(displayCurrency) недоступен. Некоторые суммы не учтены, потому что выбранная API не поддерживает эти валюты.")
                    AppLogger.log(
                        .warning,
                        category: "Finance",
                        "[Конвертация] Не удалось конвертировать сумму группы \"\(group.name)\" из \(groupCurrency) в \(displayCurrency). Сумма проигнорирована."
                    )
                }
            }
        }
        
        state.totalAmount = total
        
        // Рассчитываем сумму в дополнительной валюте, если она задана
        if let secondaryCurrency = state.secondaryDisplayCurrency {
            var secondaryTotal: Double = 0.0
            for group in state.groups {
                let groupCurrency = group.displayCurrency ?? state.displayCurrency
                let groupTotalInGroupCurrency = await calculateGroupTotal(group: group, in: groupCurrency)
                
                if groupCurrency == secondaryCurrency {
                    secondaryTotal += groupTotalInGroupCurrency
                } else {
                    if let rate = await currencyService.getRate(from: groupCurrency, to: secondaryCurrency), rate > 0 {
                        secondaryTotal += groupTotalInGroupCurrency * rate
                    } else {
                        warnings.append("Курс конвертации \(groupCurrency) → \(secondaryCurrency) недоступен. Некоторые суммы не учтены, потому что выбранная API не поддерживает эти валюты.")
                        AppLogger.log(
                            .warning,
                            category: "Finance",
                            "[Конвертация] Не удалось конвертировать сумму группы \"\(group.name)\" из \(groupCurrency) в \(secondaryCurrency). Сумма проигнорирована."
                        )
                    }
                }
            }
            state.secondaryTotalAmount = secondaryTotal
        } else {
            state.secondaryTotalAmount = 0.0
        }
        
        if !warnings.isEmpty {
            state.currencyConversionWarning = warnings.joined(separator: "\n")
        }
    }
    
    /// Подсчитать сумму группы в указанной валюте
    func calculateGroupTotal(group: FinanceGroup, in currency: String) async -> Double {
        var total: Double = 0.0
        
        guard let accounts = group.accounts else { return 0.0 }
        
        // Собираем все уникальные валюты из счетов группы
        let currencies = await collectCurrenciesFromGroup(group: group)
        
        // Собираем все валюты, для которых нужны курсы (включая целевую)
        var allCurrenciesNeeded = Set(currencies)
        allCurrenciesNeeded.insert(currency)
        
        // Предзагружаем курсы для всех необходимых валют через USD
        // Курсы уже обновлены на верхнем уровне, здесь только предзагрузка
        for neededCurrency in allCurrenciesNeeded {
            if neededCurrency != "USD" {
                // Запрашиваем курс, что автоматически загрузит его из API, если нужно
                _ = await currencyService.getRate(from: "USD", to: neededCurrency)
            }
        }
        
        for account in accounts {
            let amount = await getAccountAmount(account: account)
            
            // Пропускаем нулевые значения
            guard abs(amount.value) > 0.01 else { continue }
            
            if amount.currency == currency {
                // Валюта совпадает с целевой - добавляем напрямую
                total += amount.value
            } else {
                // Конвертируем валюту в целевую валюту группы
                // Сначала проверяем доступность курса
                let rate = await currencyService.getRate(from: amount.currency, to: currency)
                
                if let rate = rate, rate > 0 {
                    // Курс доступен - выполняем конвертацию
                    let converted = amount.value * rate
                    total += converted
                } else {
                    // Курс недоступен - пропускаем сумму
                }
            }
        }
        
        return total
    }
    
    /// Собрать все уникальные валюты из счетов группы
    private func collectCurrenciesFromGroup(group: FinanceGroup) async -> Set<String> {
        var currencies: Set<String> = []
        
        guard let accounts = group.accounts else { return currencies }
        
        for account in accounts {
            let amount = await getAccountAmount(account: account)
            // Добавляем валюту только если сумма не нулевая
            if abs(amount.value) > 0.01 {
                currencies.insert(amount.currency)
            }
        }
        
        return currencies
    }
    
    /// Получить сумму счета
    private func getAccountAmount(account: FinanceAccount) async -> (value: Double, currency: String) {
        switch account.accountType {
        case .card:
            if let card = cardByID[account.accountID] {
                // Учитываем только если includeInTotal = true
                guard card.includeInTotal else { return (0.0, card.currency) }
                
                // Для кредитных карт учитываем задолженность как отрицательное значение (вычитаем из общего счета)
                if card.cardType == .credit, let limit = card.creditLimit {
                    let debt = max(0, limit - card.balance)
                    // Вычитаем задолженность из общего счета
                    return (-debt, card.currency)
                }
                // Для дебетовых карт учитываем баланс как положительное значение
                return (card.balance, card.currency)
            }
            
        case .credit:
            if let credit = creditByID[account.accountID] {
                // Учитываем только если includeInTotal = true
                guard credit.includeInTotal else { return (0.0, credit.currency) }
                
                // Для кредитов учитываем остаток долга как отрицательное значение
                return (-credit.remainingAmount, credit.currency)
            }
            
        case .investment:
            if let investment = investmentByID[account.accountID] {
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
    func getAccountInfo(account: FinanceAccount) -> (name: String, amount: Double, currency: String, icon: String, isCreditCardDebt: Bool)? {
        switch account.accountType {
        case .card:
            if let card = cardByID[account.accountID] {
                // Для кредитных карт показываем задолженность (debt)
                let amount: Double
                let isCreditCardDebt: Bool
                if card.cardType == .credit, let limit = card.creditLimit {
                    // Для кредитных карт используем актуальный сохраненный баланс
                    // Задолженность = лимит - баланс
                    amount = max(0, limit - card.balance)
                    isCreditCardDebt = true
                } else {
                    // Для дебетовых карт показываем баланс
                    amount = card.balance
                    isCreditCardDebt = false
                }
                return (card.name, amount, card.currency, card.cardType.icon, isCreditCardDebt)
            }
            
        case .credit:
            if let credit = creditByID[account.accountID] {
                return (credit.name, credit.remainingAmount, credit.currency, credit.creditType.icon, false)
            }
            
        case .investment:
            if let investment = investmentByID[account.accountID] {
                return (investment.name, investment.amount, investment.currency, investment.category.icon, false)
            }
        }
        
        return nil
    }
    
    func refreshRates() async {
        state.isLoadingRates = true
        defer { state.isLoadingRates = false }
        
        _ = await currencyService.getRate(from: "USD", to: "RUB")
        await calculateTotalAmountAsync()
    }
    
    private func deleteGroup(_ group: FinanceGroup) {
        let now = Date()
        var didAffectCards = false
        var didAffectCredits = false

        if let accounts = group.accounts {
            for account in accounts {
                let kind = updateUnderlyingArchiveState(for: account, archivedAt: now)
                switch kind {
                case .card:
                    didAffectCards = true
                case .credit:
                    didAffectCredits = true
                case .investment, .none:
                    break
                }

                modelContext.delete(account)
            }
        }

        modelContext.delete(group)

        do {
            try modelContext.save()
            loadGroups()
            loadAccounts()
            calculateTotalAmount()

            if didAffectCards {
                EventBus.shared.publish(FinanceEvent.cardsUpdated)
            }
            if didAffectCredits {
                EventBus.shared.publish(FinanceEvent.creditsUpdated)
            }
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to delete group: \(error.localizedDescription)")
        }
    }
    
    private func updateGroup(name: String, colorHex: String, displayCurrency: String?, isFavorite: Bool, priority: GroupPriority) {
        let groupToUpdate: FinanceGroup
        if let existing = state.editingGroup {
            existing.name = name
            existing.colorHex = colorHex
            existing.displayCurrency = displayCurrency
            existing.isFavorite = isFavorite
            existing.priority = priority
            existing.updatedAt = Date()
            groupToUpdate = existing
        } else {
            // Находим максимальный order
            let maxOrder = state.groups.map { $0.order }.max() ?? -1
            let newGroup = FinanceGroup(name: name, colorHex: colorHex, order: maxOrder + 1, isFavorite: isFavorite, priority: priority)
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
            loadAccounts() // Обновляем список счетов
            updateUnattachedItems() // Обновляем списки непривязанных элементов
            calculateTotalAmount() // Пересчитываем общую сумму
            
            // Пересчитываем сумму группы, в которую был добавлен счет
            Task {
                let currency = targetGroup.displayCurrency ?? state.displayCurrency
                let total = await calculateGroupTotal(group: targetGroup, in: currency)
                state.groupTotals[targetGroup.groupUniqueID] = total
            }
            
            state.showAddAccountSheet = false
            state.selectedGroupForAccount = nil
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to add account: \(error.localizedDescription)")
        }
    }
    
    private func removeAccountFromGroup(_ account: FinanceAccount) {
        // Находим группу, к которой принадлежал счет
        let accountGroup = state.groups.first { group in
            group.accounts?.contains(where: { $0.accountUniqueID == account.accountUniqueID }) ?? false
        }

        let kind = updateUnderlyingArchiveState(for: account, archivedAt: Date())
        modelContext.delete(account)
        
        do {
            try modelContext.save()
            loadGroups()
            loadAccounts() // Обновляем список счетов
            updateUnattachedItems() // Обновляем списки непривязанных элементов
            calculateTotalAmount() // Пересчитываем общую сумму
            
            // Пересчитываем сумму группы, из которой был удален счет
            if let group = accountGroup {
                Task {
                    let currency = group.displayCurrency ?? state.displayCurrency
                    let total = await calculateGroupTotal(group: group, in: currency)
                    state.groupTotals[group.groupUniqueID] = total
                }
            }
            if kind == .card {
                EventBus.shared.publish(FinanceEvent.cardsUpdated)
            }
            if kind == .credit {
                EventBus.shared.publish(FinanceEvent.creditsUpdated)
            }
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to remove account: \(error.localizedDescription)")
        }
    }

    private func deleteAccountPermanently(_ account: FinanceAccount) {
        let accountGroup = state.groups.first { group in
            group.accounts?.contains(where: { $0.accountUniqueID == account.accountUniqueID }) ?? false
        }
        let kind = updateUnderlyingArchiveState(for: account, archivedAt: Date())

        do {
            try modelContext.save()
            loadGroups()
            loadAccounts()
            updateUnattachedItems()
            calculateTotalAmount()

            if let group = accountGroup {
                Task {
                    let currency = group.displayCurrency ?? state.displayCurrency
                    let total = await calculateGroupTotal(group: group, in: currency)
                    state.groupTotals[group.groupUniqueID] = total
                }
            }
            if kind == .card {
                EventBus.shared.publish(FinanceEvent.cardsUpdated)
            }
            if kind == .credit {
                EventBus.shared.publish(FinanceEvent.creditsUpdated)
            }
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to delete account permanently: \(error.localizedDescription)")
        }
    }

    private enum UnderlyingAccountKind {
        case card
        case credit
        case investment
        case none
    }

    @discardableResult
    private func updateUnderlyingArchiveState(for account: FinanceAccount, archivedAt: Date?) -> UnderlyingAccountKind {
        updateUnderlyingArchiveState(accountType: account.accountType, accountID: account.accountID, archivedAt: archivedAt)
    }

    @discardableResult
    private func updateUnderlyingArchiveState(accountType: FinanceAccountType, accountID: String, archivedAt: Date?) -> UnderlyingAccountKind {
        switch accountType {
        case .card:
            let card = allCardByID[accountID] ?? ((try? modelContext.fetch(FetchDescriptor<Card>())) ?? []).first { $0.cardUniqueID == accountID }
            if let card {
                card.archivedAt = archivedAt
                card.updatedAt = Date()
            }
            return .card
        case .credit:
            let credit = allCreditByID[accountID] ?? ((try? modelContext.fetch(FetchDescriptor<Credit>())) ?? []).first { $0.creditUniqueID == accountID }
            if let credit {
                credit.archivedAt = archivedAt
                credit.updatedAt = Date()
            }
            return .credit
        case .investment:
            let investment = allInvestmentByID[accountID] ?? ((try? modelContext.fetch(FetchDescriptor<Investment>())) ?? []).first { $0.investmentUniqueID == accountID }
            if let investment {
                investment.archivedAt = archivedAt
                investment.updatedAt = Date()
            }
            return .investment
        }
    }

    private func restoreArchivedAccountToGroup(accountType: FinanceAccountType, accountID: String, group: FinanceGroup?) {
        guard let targetGroup = group else {
            AppLogger.log(.error, category: "Finance", "Group is required")
            return
        }

        let kind = updateUnderlyingArchiveState(accountType: accountType, accountID: accountID, archivedAt: nil)
        addAccountToGroup(accountType: accountType, accountID: accountID, group: targetGroup)

        if kind == .card {
            EventBus.shared.publish(FinanceEvent.cardsUpdated)
        }
        if kind == .credit {
            EventBus.shared.publish(FinanceEvent.creditsUpdated)
        }
    }
    
    private func editAccount(_ account: FinanceAccount) {
        switch account.accountType {
        case .card:
            state.editingCardID = account.accountID
            state.showEditCardSheet = true
            
        case .credit:
            state.editingCreditID = account.accountID
            state.showEditCreditSheet = true
            
        case .investment:
            state.editingInvestmentID = account.accountID
            state.showEditInvestmentSheet = true
        }
    }
    
    private func updateAccountAmount(account: FinanceAccount, newAmount: Double) {
        // Находим группу, к которой принадлежит счет
        let accountGroup = state.groups.first { group in
            group.accounts?.contains(where: { $0.accountUniqueID == account.accountUniqueID }) ?? false
        }
        
        switch account.accountType {
        case .card:
            if let card = cardByID[account.accountID] {
                // Сохраняем старое значение для создания транзакции
                let oldBalance = card.balance
                if !card.hasInitialBalance {
                    card.initialBalance = card.balance
                    card.hasInitialBalance = true
                }
                let oldAmount: Double
                if card.cardType == .credit, let limit = card.creditLimit {
                    // Для кредитных карт старое значение - это задолженность
                    oldAmount = max(0, limit - oldBalance)
                } else {
                    // Для дебетовых карт старое значение - это баланс
                    oldAmount = oldBalance
                }
                
                // Для кредитных карт меняем задолженность (т.е. меняем balance так, чтобы debt = newAmount)
                if card.cardType == .credit, let limit = card.creditLimit {
                    // debt = limit - balance
                    // newAmount = limit - newBalance
                    // newBalance = limit - newAmount
                    card.balance = max(0, limit - newAmount)
                } else {
                    // Для дебетовых карт меняем баланс напрямую
                    card.balance = newAmount
                }
                card.updatedAt = Date()
                
                do {
                    // Создаем транзакцию для ручного изменения баланса
                    let difference = newAmount - oldAmount
                    if abs(difference) > 0.01 { // Создаем транзакцию только если есть изменение
                        // Для кредитных карт newAmount - это ДОЛГ
                        // Увеличение долга = УМЕНЬШЕНИЕ баланса = отрицательная транзакция
                        // Уменьшение долга = УВЕЛИЧЕНИЕ баланса = положительная транзакция
                        // Для дебетовых карт: положительное значение = увеличение баланса, отрицательное = уменьшение
                        let transactionAmount: Double
                        let transactionNote: String
                        let transactionType: CashflowTransactionType

                        if card.cardType == .credit {
                            transactionAmount = -difference
                            transactionNote = "Быстрое изменение задолженности"
                            transactionType = .creditDebtAdjustment
                        } else {
                            transactionAmount = difference
                            transactionNote = "Быстрое изменение баланса"
                            transactionType = .cardBalanceAdjustment
                        }

                        let transaction = CashflowTransaction(
                            transactionType: transactionType,
                            amount: transactionAmount,
                            currency: card.currency,
                            transactionDate: Date(),
                            cardID: card.cardUniqueID,
                            note: transactionNote
                        )
                        modelContext.insert(transaction)
                    }
                    
                    // Атомарное сохранение обновления карты и транзакции (если она была создана)
                    try modelContext.save()
                    
                    loadAccounts()
                    calculateTotalAmount()
                    
                    // Пересчитываем сумму группы, к которой принадлежит счет
                    if let group = accountGroup {
                        Task {
                            let currency = group.displayCurrency ?? state.displayCurrency
                            let total = await calculateGroupTotal(group: group, in: currency)
                            state.groupTotals[group.groupUniqueID] = total
                        }
                    }
                } catch {
                    AppLogger.log(.error, category: "Finance", "Failed to update card amount: \(error.localizedDescription)")
                }
            }
            
        case .credit:
            if let credit = creditByID[account.accountID] {
                // Сохраняем старое значение для создания транзакции
                let oldAmount = credit.remainingAmount
                if !credit.hasInitialRemainingAmount {
                    credit.initialRemainingAmount = credit.remainingAmount
                    credit.hasInitialRemainingAmount = true
                }
                
                credit.applyManualRemainingAmount(newAmount)
                credit.isClosed = newAmount <= 0
                credit.updatedAt = Date()
                
                do {
                    // Создаем транзакцию для ручного изменения баланса
                    let difference = newAmount - oldAmount
                    if abs(difference) > 0.01 { // Создаем транзакцию только если есть изменение
                        // Для кредитов newAmount - это ОСТАТОК ДОЛГА
                        // Увеличение долга = отрицательная транзакция
                        // Уменьшение долга (погашение) = положительная транзакция
                        // Это обеспечивает единую семантику для всех типов счетов
                        let balanceChange = -difference

                        let transaction = CashflowTransaction(
                            transactionType: .creditDebtAdjustment,
                            amount: balanceChange,
                            currency: credit.currency,
                            transactionDate: Date(),
                            creditID: credit.creditUniqueID,
                            note: "Быстрое изменение остатка долга"
                        )
                        modelContext.insert(transaction)
                    }
                    
                    // Атомарное сохранение обновления кредита и транзакции (если она была создана)
                    try modelContext.save()
                    
                    loadAccounts()
                    calculateTotalAmount()
                    
                    // Пересчитываем сумму группы, к которой принадлежит счет
                    if let group = accountGroup {
                        Task {
                            let currency = group.displayCurrency ?? state.displayCurrency
                            let total = await calculateGroupTotal(group: group, in: currency)
                            state.groupTotals[group.groupUniqueID] = total
                        }
                    }
                } catch {
                    AppLogger.log(.error, category: "Finance", "Failed to update credit amount: \(error.localizedDescription)")
                }
            }
            
        case .investment:
            if let investment = investmentByID[account.accountID] {
                // Сохраняем старое значение для создания транзакции
                let oldAmount = investment.amount
                if !investment.hasInitialAmount {
                    investment.initialAmount = investment.amount
                    investment.hasInitialAmount = true
                }
                
                investment.amount = newAmount
                investment.updatedAt = Date()
                
                do {
                    // Создаем транзакцию для ручного изменения стоимости актива
                    let difference = newAmount - oldAmount
                    if abs(difference) > 0.01 {
                        let transaction = CashflowTransaction(
                            transactionType: .balanceAdjustment,
                            amount: difference,
                            currency: investment.currency,
                            transactionDate: Date(),
                            investmentID: investment.investmentUniqueID,
                            note: "Ручное изменение стоимости актива"
                        )
                        modelContext.insert(transaction)
                    }
                    
                    // Атомарное сохранение обновления инвестиции и транзакции (если она была создана)
                    try modelContext.save()
                    
                    loadAccounts()
                    calculateTotalAmount()
                    
                    // Пересчитываем сумму группы, к которой принадлежит счет
                    if let group = accountGroup {
                        Task {
                            let currency = group.displayCurrency ?? state.displayCurrency
                            let total = await calculateGroupTotal(group: group, in: currency)
                            state.groupTotals[group.groupUniqueID] = total
                        }
                    }
                } catch {
                    AppLogger.log(.error, category: "Finance", "Failed to update investment amount: \(error.localizedDescription)")
                }
            }
        }
    }
}
