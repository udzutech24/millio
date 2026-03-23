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

    /// Закрываемое уведомление о том, что часть ручного обновления не выполнилась.
    var refreshIssueMessage: String? = nil
    var showRefreshIssue: Bool = false

    /// Последняя успешно завершенная сделка по рыночному активу.
    var tradeCelebration: FinanceTradeCelebration? = nil
}

private struct StockRefreshIssues {
    var notFoundSymbols: Set<String> = []
    var priceUnavailableSymbols: Set<String> = []
    var providerErrorSymbols: Set<String> = []
    var authErrorSymbols: Set<String> = []
    var networkErrorSymbols: Set<String> = []
    var httpErrorSymbols: Set<String> = []
    var decodingErrorSymbols: Set<String> = []
    var clientErrorSymbols: Set<String> = []

    var hasIssues: Bool {
        !notFoundSymbols.isEmpty ||
        !priceUnavailableSymbols.isEmpty ||
        !providerErrorSymbols.isEmpty ||
        !authErrorSymbols.isEmpty ||
        !networkErrorSymbols.isEmpty ||
        !httpErrorSymbols.isEmpty ||
        !decodingErrorSymbols.isEmpty ||
        !clientErrorSymbols.isEmpty
    }

    mutating func remove(symbol: String) {
        notFoundSymbols.remove(symbol)
        priceUnavailableSymbols.remove(symbol)
        providerErrorSymbols.remove(symbol)
        authErrorSymbols.remove(symbol)
        networkErrorSymbols.remove(symbol)
        httpErrorSymbols.remove(symbol)
        decodingErrorSymbols.remove(symbol)
        clientErrorSymbols.remove(symbol)
    }
}

enum InvestmentOrderSide: Hashable {
    case buy
    case sell
}

struct InvestmentOrderFunding: Equatable {
    var settlementAccountKind: CashflowSelectableAccount.Kind?
    var shouldAffectCardBalance: Bool

    static let ignored = InvestmentOrderFunding(
        settlementAccountKind: nil,
        shouldAffectCardBalance: false
    )
}

struct FinanceTradeCelebration: Equatable, Identifiable {
    let id: UUID
    let side: InvestmentOrderSide
    let investmentName: String
    let investmentCategory: InvestmentCategory
    let totalAmount: Double
    let currency: String

    init(
        id: UUID = UUID(),
        side: InvestmentOrderSide,
        investmentName: String,
        investmentCategory: InvestmentCategory,
        totalAmount: Double,
        currency: String
    ) {
        self.id = id
        self.side = side
        self.investmentName = investmentName
        self.investmentCategory = investmentCategory
        self.totalAmount = totalAmount
        self.currency = currency
    }
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
    case syncPrimaryCurrencyChange(old: String, new: String)
    case showSecondaryDisplayCurrencySheet
    case hideSecondaryDisplayCurrencySheet
    case setSecondaryDisplayCurrency(String?)
    case toggleGroupExpanded(String)
    case moveGroup(sourceGroupID: String, destinationIndex: Int)
    case moveAccount(sourceAccountID: String, destinationIndex: Int, groupID: String)
    case setGroupTotal(String, Double)
    case editAccount(FinanceAccount)
    case hideEditCardSheet
    case hideEditCreditSheet
    case hideEditInvestmentSheet
    case showQuickEditAccountSheet(FinanceAccount)
    case hideQuickEditAccountSheet
    case updateAccountAmount(FinanceAccount, Double)
    case updateCreditCardQuickFields(account: FinanceAccount, creditLimit: Double, debt: Double)
    case executeInvestmentOrder(
        account: FinanceAccount,
        side: InvestmentOrderSide,
        quantity: Double,
        unitPrice: Double,
        funding: InvestmentOrderFunding
    )
    case updateMarketInvestmentDetails(account: FinanceAccount, quantity: Double, unitPrice: Double, purchaseUnitPrice: Double?)
    case showGroupDynamics(FinanceGroup)
    case hideGroupDynamics
    case showAccountDynamics(FinanceAccount)
    case hideAccountDynamics
    case showSavingsGoalSheet
    case hideSavingsGoalSheet
    case setSavingsGoalEnabled(Bool)
    case setSavingsGoalAmount(Double)
    case toggleAmountVisibility
    case clearTradeCelebration
}

// MARK: - Finance ViewModel

@MainActor
final class FinanceViewModel: ViewModelProtocol {
    @Published var state = FinanceState()
    
    let modelContext: ModelContext

    /// Сервис курсов валют (внедряется для тестируемости)
    let currencyService: CurrencyRateServiceProtocol
    /// Клиент рыночных данных (внедряется для тестируемости)
    let marketDataClient: MarketDataClientProtocol

    private let defaults = UserDefaults.standard
    private var ungroupedGroupName: String { FinanceSystemGroups.ungroupedName }
    private var financeEventsSubscriptionID: UUID?
    private var backgroundTasks: [UUID: Task<Void, Never>] = [:]

    /// Быстрые словари для поиска счетов по ID (O(1) вместо O(n))
    private var cardByID: [String: Card] = [:]
    private var creditByID: [String: Credit] = [:]
    private var investmentByID: [String: Investment] = [:]
    private var allCardByID: [String: Card] = [:]
    private var allCreditByID: [String: Credit] = [:]
    private var allInvestmentByID: [String: Investment] = [:]
    
    private var storedSavingsGoalEnabled: Bool {
        get { defaults.bool(forKey: "finance_savings_goal_enabled") }
        set { defaults.set(newValue, forKey: "finance_savings_goal_enabled") }
    }
    
    private var storedSavingsGoalAmount: Double {
        get { defaults.double(forKey: "finance_savings_goal_amount") }
        set { defaults.set(newValue, forKey: "finance_savings_goal_amount") }
    }

    private var storedSavingsGoalCurrency: String {
        get {
            let value = defaults.string(forKey: "finance_savings_goal_currency")
            let normalized = normalizedCurrencyCode(value ?? state.displayCurrency)
            return normalized.isEmpty ? "USD" : normalized
        }
        set {
            let normalized = normalizedCurrencyCode(newValue)
            defaults.set(normalized.isEmpty ? "USD" : normalized, forKey: "finance_savings_goal_currency")
        }
    }
    
    private var storedAmountHidden: Bool {
        get { defaults.bool(forKey: "finance_amount_hidden") }
        set { defaults.set(newValue, forKey: "finance_amount_hidden") }
    }

    init(
        modelContext: ModelContext,
        currencyService: CurrencyRateServiceProtocol? = nil,
        marketDataClient: MarketDataClientProtocol = MarketAPIClient.shared,
        skipInitialLoad: Bool = false
    ) {
        self.modelContext = modelContext
        self.currencyService = currencyService ?? CurrencyRateService.shared
        self.marketDataClient = marketDataClient
        state.displayCurrency = SettingsManager.shared.primaryCurrencyCode
        state.secondaryDisplayCurrency = defaultSecondaryDisplayCurrency(primary: state.displayCurrency)
        state.isSavingsGoalEnabled = storedSavingsGoalEnabled
        state.savingsGoalAmount = storedSavingsGoalAmount
        let storedGoalCurrency = storedSavingsGoalCurrency
        state.isAmountHidden = storedAmountHidden
        subscribeToFinanceEvents()
        if !skipInitialLoad {
            loadGroups()
            loadAccounts()
        }
        scheduleBackgroundTask { viewModel in
            await viewModel.convertSavingsGoalAmountIfNeeded(from: storedGoalCurrency, to: viewModel.state.displayCurrency)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            cancelBackgroundTasks()
            if let subscriptionID = financeEventsSubscriptionID {
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
            scheduleBackgroundTask { viewModel in
                await viewModel.refreshGroupTotalsAndAmounts()
            }
            
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
            let oldDisplayCurrency = normalizedCurrencyCode(state.displayCurrency)
            let newDisplayCurrency = normalizedCurrencyCode(currency)
            guard !newDisplayCurrency.isEmpty else { return }
            state.displayCurrency = newDisplayCurrency
            scheduleBackgroundTask { viewModel in
                await viewModel.convertSavingsGoalAmountIfNeeded(from: oldDisplayCurrency, to: newDisplayCurrency)
                await viewModel.refreshRates()
                await viewModel.calculateTotalAmountAsync()
            }

        case .syncPrimaryCurrencyChange(let old, let new):
            let oldNormalized = normalizedCurrencyCode(old)
            let newNormalized = normalizedCurrencyCode(new)
            guard !oldNormalized.isEmpty, !newNormalized.isEmpty else { return }
            guard normalizedCurrencyCode(state.displayCurrency) == oldNormalized else { return }
            state.displayCurrency = newNormalized
            scheduleBackgroundTask { viewModel in
                await viewModel.convertSavingsGoalAmountIfNeeded(from: oldNormalized, to: newNormalized)
                await viewModel.refreshRates()
                await viewModel.calculateTotalAmountAsync()
            }
            
        case .setSecondaryDisplayCurrency(let currency):
            state.secondaryDisplayCurrency = currency?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            scheduleBackgroundTask { viewModel in
                await viewModel.refreshRates()
                await viewModel.calculateTotalAmountAsync()
            }

        case .toggleGroupExpanded(let groupID):
            if state.expandedGroupIDs.contains(groupID) {
                state.expandedGroupIDs.remove(groupID)
            } else {
                state.expandedGroupIDs.insert(groupID)
            }

        case .moveGroup(let sourceGroupID, let destinationIndex):
            moveGroup(sourceGroupID: sourceGroupID, destinationIndex: destinationIndex)

        case .moveAccount(let sourceAccountID, let destinationIndex, let groupID):
            moveAccount(sourceAccountID: sourceAccountID, destinationIndex: destinationIndex, groupID: groupID)
            
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
        case .updateCreditCardQuickFields(let account, let creditLimit, let debt):
            updateCreditCardQuickFields(account: account, creditLimit: creditLimit, debt: debt)

        case .executeInvestmentOrder(let account, let side, let quantity, let unitPrice, let funding):
            executeInvestmentOrder(
                account: account,
                side: side,
                quantity: quantity,
                unitPrice: unitPrice,
                funding: funding
            )

        case .updateMarketInvestmentDetails(let account, let quantity, let unitPrice, let purchaseUnitPrice):
            updateMarketInvestmentDetails(
                account: account,
                quantity: quantity,
                unitPrice: unitPrice,
                purchaseUnitPrice: purchaseUnitPrice
            )
            
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
            storedSavingsGoalCurrency = state.displayCurrency
            
        case .toggleAmountVisibility:
            state.isAmountHidden.toggle()
            storedAmountHidden = state.isAmountHidden

        case .clearTradeCelebration:
            state.tradeCelebration = nil
    }
    }
    
    // MARK: - Private Methods

    private func defaultSecondaryDisplayCurrency(primary: String) -> String {
        let normalizedPrimary = normalizedCurrencyCode(primary)
        let firstFavorite = SettingsManager.shared.favoriteCurrencyCodes.first(where: { $0 != normalizedPrimary })
        return firstFavorite ?? "USD"
    }

    private func scheduleBackgroundTask(_ operation: @escaping @MainActor (FinanceViewModel) async -> Void) {
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

    private func normalizedCurrencyCode(_ currency: String) -> String {
        currency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func convertSavingsGoalAmountIfNeeded(from sourceCurrency: String, to targetCurrency: String) async {
        let source = normalizedConversionCurrency(sourceCurrency)
        let target = normalizedConversionCurrency(targetCurrency)

        guard !source.isEmpty, !target.isEmpty else { return }
        guard state.savingsGoalAmount > 0 else {
            storedSavingsGoalCurrency = targetCurrency
            return
        }
        guard source != target else {
            storedSavingsGoalCurrency = targetCurrency
            return
        }

        guard let rate = await currencyService.getRate(from: source, to: target), rate > 0 else {
            AppLogger.log(
                .warning,
                category: "Finance",
                "Failed to convert savings goal amount from \(sourceCurrency) to \(targetCurrency): rate unavailable"
            )
            return
        }

        let convertedAmount = state.savingsGoalAmount * rate
        guard convertedAmount.isFinite, convertedAmount > 0 else { return }

        let roundedAmount = max(1.0, convertedAmount.rounded())
        state.savingsGoalAmount = roundedAmount
        storedSavingsGoalAmount = roundedAmount
        storedSavingsGoalCurrency = targetCurrency
    }
    
    private func loadGroups() {
        let descriptor = FetchDescriptor<FinanceGroup>()
        if let groups = try? modelContext.fetch(descriptor) {
            state.groups = groups.sorted { group1, group2 in
                if group1.order != group2.order {
                    return group1.order < group2.order
                }
                return group1.createdAt < group2.createdAt
            }
            // Пустая системная группа "Без группы" не должна отображаться в списке.
            .filter { group in
                guard group.name == ungroupedGroupName else { return true }
                return !(group.accounts?.isEmpty ?? true)
            }
            // Обновляем списки непривязанных элементов после загрузки групп
            updateUnattachedItems()
            calculateTotalAmount()
        }
    }
    
    private func loadAccounts() {
        // Загружаем карты, кредиты и активы
        let allCards = CardCatalog.fetchAll(in: modelContext)
        state.availableCards = allCards.filter { $0.archivedAt == nil }
        state.archivedCards = allCards.filter { $0.archivedAt != nil }
        
        let creditDescriptor = FetchDescriptor<Credit>()
        let allCredits = (try? modelContext.fetch(creditDescriptor)) ?? []
        state.availableCredits = allCredits.filter { $0.archivedAt == nil }
        state.archivedCredits = allCredits.filter { $0.archivedAt != nil }
        normalizeCreditsIncludeInTotal(state.availableCredits + state.archivedCredits)
        
        let investmentDescriptor = FetchDescriptor<Investment>()
        let allInvestments = (try? modelContext.fetch(investmentDescriptor)) ?? []
        normalizeMarketAssetIdentities(allInvestments)
        normalizeMarketQuoteLookupKeys(allInvestments)
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

    private func normalizeCreditsIncludeInTotal(_ credits: [Credit]) {
        var requiresSave = false
        for credit in credits where !credit.includeInTotal {
            credit.includeInTotal = true
            credit.updatedAt = Date()
            requiresSave = true
        }
        if requiresSave {
            do {
                try modelContext.save()
            } catch {
                AppLogger.log(.error, category: "Finance", "Failed to normalize credits includeInTotal: \(error.localizedDescription)")
            }
        }
    }

    private func normalizeMarketAssetIdentities(_ investments: [Investment]) {
        var requiresSave = false
        let assetCatalogStore = AssetCatalogStore(modelContext: modelContext)

        for investment in investments where investment.isMarketPriced {
            requiresSave = assetCatalogStore.migrateInvestmentIfNeeded(investment) || requiresSave
        }

        guard requiresSave else { return }
        do {
            try modelContext.save()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to normalize market asset identities: \(error.localizedDescription)")
        }
    }

    private func normalizeMarketQuoteLookupKeys(_ investments: [Investment]) {
        var requiresSave = false

        for investment in investments where investment.isMarketPriced {
            let rawSymbol = investment.marketSymbol?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            guard !rawSymbol.isEmpty else { continue }

            let normalizedKey = MarketInstrumentIdentity.canonicalQuoteLookupKey(
                symbol: rawSymbol,
                exchange: investment.marketExchange
            )
            if !normalizedKey.isEmpty, investment.marketQuoteLookupKey != normalizedKey {
                investment.marketQuoteLookupKey = normalizedKey
                requiresSave = true
            }
        }

        guard requiresSave else { return }
        do {
            try modelContext.save()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to normalize market quote lookup keys: \(error.localizedDescription)")
        }
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
            case FinanceEvent.cardsUpdated, FinanceEvent.investmentsUpdated:
                self.loadAccounts()
                self.scheduleBackgroundTask { viewModel in
                    await viewModel.refreshGroupTotalsAndAmounts()
                }
            case FinanceEvent.auditSnapshotsUpdated:
                self.loadGroups()
                self.loadAccounts()
                self.scheduleBackgroundTask { viewModel in
                    await viewModel.refreshGroupTotalsAndAmounts()
                }
            case BackupEvent.restoreCompleted:
                self.loadGroups()
                self.loadAccounts()
                self.scheduleBackgroundTask { viewModel in
                    await viewModel.refreshGroupTotalsAndAmounts()
                }
            default:
                break
            }
        }
    }

    private func handleCreditsUpdated() {
        loadGroups()
        loadAccounts()
        scheduleBackgroundTask { viewModel in
            await viewModel.refreshGroupTotalsAndAmounts()
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

        var didMutate = false
        var removedCount = 0
        var dedupedCount = 0
        var reassignedToUngroupedCount = 0
        var createdMissingCardLinksCount = 0
        var createdMissingCreditLinksCount = 0
        var createdMissingInvestmentLinksCount = 0

        var ungroupedGroup: FinanceGroup?
        func resolveUngroupedGroup() -> FinanceGroup {
            if let ungroupedGroup { return ungroupedGroup }
            let group = FinanceSystemGroups.ensureUngroupedGroup(in: modelContext)
            ungroupedGroup = group
            return group
        }

        var linkedCardIDs = Set(accounts.compactMap { account in
            account.accountType == .card ? account.accountID : nil
        })
        var linkedCreditIDs = Set(accounts.compactMap { account in
            account.accountType == .credit ? account.accountID : nil
        })
        var linkedInvestmentIDs = Set(accounts.compactMap { account in
            account.accountType == .investment ? account.accountID : nil
        })

        let groupedAccounts = Dictionary(
            grouping: accounts,
            by: { "\($0.accountTypeRaw)|\($0.accountID)" }
        )

        for duplicates in groupedAccounts.values where duplicates.count > 1 {
            let survivor = duplicates.max { lhs, rhs in
                financeAccountDeduplicationRank(lhs) < financeAccountDeduplicationRank(rhs)
            }

            for duplicate in duplicates where duplicate.persistentModelID != survivor?.persistentModelID {
                modelContext.delete(duplicate)
                dedupedCount += 1
                didMutate = true
            }
        }

        for account in accounts {
            if account.modelContext == nil {
                continue
            }
            // `group == nil` — невалидное состояние. Нормализуем в системную "Без группы",
            // иначе счет будет теряться из основного списка (это проявляется на массовом импорте акций).
            if account.group == nil {
                account.group = resolveUngroupedGroup()
                account.updatedAt = Date()
                reassignedToUngroupedCount += 1
                didMutate = true
            }

            // Если целевой объект не найден — удаляем связь
            switch account.accountType {
            case .card:
                if allCardByID[account.accountID] == nil {
                    modelContext.delete(account)
                    removedCount += 1
                    didMutate = true
                }
            case .credit:
                if allCreditByID[account.accountID] == nil {
                    modelContext.delete(account)
                    removedCount += 1
                    didMutate = true
                }
            case .investment:
                if allInvestmentByID[account.accountID] == nil {
                    modelContext.delete(account)
                    removedCount += 1
                    didMutate = true
                }
            }
        }

        // Восстанавливаем отсутствующие связи для продуктов:
        // раньше они могли "пропасть" из групп из-за cleanup/dangling links, после чего
        // счет исчезал с главного экрана и переставал влиять на Итого.
        for card in allCardByID.values where card.archivedAt == nil {
            guard !linkedCardIDs.contains(card.cardUniqueID) else { continue }
            let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
            account.group = resolveUngroupedGroup()
            modelContext.insert(account)
            linkedCardIDs.insert(card.cardUniqueID)
            createdMissingCardLinksCount += 1
            didMutate = true
        }

        for credit in allCreditByID.values where credit.archivedAt == nil {
            guard !linkedCreditIDs.contains(credit.creditUniqueID) else { continue }
            let account = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
            account.group = resolveUngroupedGroup()
            modelContext.insert(account)
            linkedCreditIDs.insert(credit.creditUniqueID)
            createdMissingCreditLinksCount += 1
            didMutate = true
        }

        for investment in allInvestmentByID.values where investment.archivedAt == nil {
            guard !linkedInvestmentIDs.contains(investment.investmentUniqueID) else { continue }
            let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
            account.group = resolveUngroupedGroup()
            modelContext.insert(account)
            linkedInvestmentIDs.insert(investment.investmentUniqueID)
            createdMissingInvestmentLinksCount += 1
            didMutate = true
        }

        guard didMutate else { return }

        do {
            try modelContext.save()
            if dedupedCount > 0 {
                AppLogger.log(.info, category: "Finance", "Removed \(dedupedCount) duplicate finance account links")
            }
            if removedCount > 0 {
                AppLogger.log(.info, category: "Finance", "Removed \(removedCount) invalid finance account links")
            }
            if reassignedToUngroupedCount > 0 {
                AppLogger.log(.info, category: "Finance", "Reassigned \(reassignedToUngroupedCount) finance account links to ungrouped group")
            }
            if createdMissingCardLinksCount > 0 {
                AppLogger.log(.info, category: "Finance", "Created \(createdMissingCardLinksCount) missing card finance account links")
            }
            if createdMissingCreditLinksCount > 0 {
                AppLogger.log(.info, category: "Finance", "Created \(createdMissingCreditLinksCount) missing credit finance account links")
            }
            if createdMissingInvestmentLinksCount > 0 {
                AppLogger.log(.info, category: "Finance", "Created \(createdMissingInvestmentLinksCount) missing investment finance account links")
            }
            loadGroups()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to cleanup finance accounts: \(error.localizedDescription)")
        }
    }

    private func financeAccountDeduplicationRank(_ account: FinanceAccount) -> (Int, Int, Date, Date) {
        let isGrouped = account.group != nil ? 1 : 0
        let isNonSystemGroup: Int = {
            guard let group = account.group else { return 0 }
            return group.name == ungroupedGroupName ? 0 : 1
        }()
        return (isNonSystemGroup, isGrouped, account.updatedAt, account.createdAt)
    }
    
    private func calculateTotalAmount() {
        scheduleBackgroundTask { viewModel in
            await viewModel.calculateTotalAmountAsync()
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
        
        // Не форсим сетевое обновление здесь: быстрые локальные правки (сумма/группа)
        // должны пересчитываться мгновенно на кэше курсов.
        
        // Для каждого group вычисляем сумму в его валюте (или в state.displayCurrency, если не задана)
        for group in state.groups {
            let groupCurrency = group.displayCurrency ?? state.displayCurrency
            let groupTotalInGroupCurrency = await calculateGroupTotal(group: group, in: groupCurrency)
            let normalizedGroupCurrency = normalizedConversionCurrency(groupCurrency)
            let normalizedDisplayCurrency = normalizedConversionCurrency(displayCurrency)
            
            // Конвертируем сумму группы в displayCurrency если нужно
            if normalizedGroupCurrency == normalizedDisplayCurrency {
                total += groupTotalInGroupCurrency
            } else {
                if let rate = await currencyService.getRate(from: normalizedGroupCurrency, to: normalizedDisplayCurrency), rate > 0 {
                    total += groupTotalInGroupCurrency * rate
                } else {
                    // Если курс недоступен, просто пропускаем сумму этой группы и добавляем предупреждение
                    warnings.append(FinancesL10n.format("finances.warning.rate_unavailable", groupCurrency, displayCurrency))
                    AppLogger.log(
                        .warning,
                        category: "Finance",
                        "[Conversion] Failed to convert group amount \"\(group.name)\" from \(groupCurrency) to \(displayCurrency). Amount ignored."
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
                let normalizedGroupCurrency = normalizedConversionCurrency(groupCurrency)
                let normalizedSecondaryCurrency = normalizedConversionCurrency(secondaryCurrency)
                
                if normalizedGroupCurrency == normalizedSecondaryCurrency {
                    secondaryTotal += groupTotalInGroupCurrency
                } else {
                    if let rate = await currencyService.getRate(from: normalizedGroupCurrency, to: normalizedSecondaryCurrency), rate > 0 {
                        secondaryTotal += groupTotalInGroupCurrency * rate
                    } else {
                        warnings.append(FinancesL10n.format("finances.warning.rate_unavailable", groupCurrency, secondaryCurrency))
                        AppLogger.log(
                            .warning,
                            category: "Finance",
                            "[Conversion] Failed to convert group amount \"\(group.name)\" from \(groupCurrency) to \(secondaryCurrency). Amount ignored."
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
        let targetCurrency = normalizedConversionCurrency(currency)
        
        guard let accounts = group.accounts else { return 0.0 }
        
        for account in accounts {
            let amount = await getAccountAmount(account: account)
            let sourceCurrency = normalizedConversionCurrency(amount.currency)
            
            // Пропускаем нулевые значения
            guard abs(amount.value) > 0.01 else { continue }
            
            if sourceCurrency == targetCurrency {
                // Валюта совпадает с целевой - добавляем напрямую
                total += amount.value
            } else {
                // Конвертируем валюту в целевую валюту группы
                // Сначала проверяем доступность курса
                let rate = await currencyService.getRate(from: sourceCurrency, to: targetCurrency)
                
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
                currencies.insert(normalizedConversionCurrency(amount.currency))
            }
        }
        
        return currencies
    }
    
    /// Получить сумму счета
    private func getAccountAmount(account: FinanceAccount) async -> (value: Double, currency: String) {
        switch account.accountType {
        case .card:
            if let card = cardByID[account.accountID] {
                let snapshot = CardSnapshotFactory.make(from: card)
                return (snapshot.netWorthAmount, snapshot.currency)
            }
            
        case .credit:
            if let credit = creditByID[account.accountID] {
                // Для кредитов учитываем остаток долга как отрицательное значение
                return (-credit.remainingAmount, credit.currency)
            }
            
        case .investment:
            if let investment = investmentByID[account.accountID] {
                // Учитываем только если includeInTotal = true
                if investment.includeInTotal {
                    let value = investment.investmentType == .positive ? investment.amount : -investment.amount
                    return (value, resolvedInvestmentCurrency(investment))
                }
            }
        }
        
        return (0.0, "RUB")
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
    
    /// Получить информацию о счете для отображения
    func getAccountInfo(account: FinanceAccount) -> (name: String, amount: Double, currency: String, icon: String, isCreditCardDebt: Bool)? {
        switch account.accountType {
        case .card:
            if let card = cardByID[account.accountID] {
                let snapshot = CardSnapshotFactory.make(from: card)
                if snapshot.isCreditCard {
                    return (snapshot.name, snapshot.debtAmount, snapshot.currency, snapshot.icon, true)
                }
                return (snapshot.name, snapshot.availableAmount, snapshot.currency, snapshot.icon, false)
            }
            
        case .credit:
            if let credit = creditByID[account.accountID] {
                return (credit.name, credit.remainingAmount, credit.currency, credit.creditType.icon, false)
            }
            
        case .investment:
            if let investment = investmentByID[account.accountID] {
                return (investmentDisplayName(investment), investment.amount, resolvedInvestmentCurrency(investment), investment.category.icon, false)
            }
        }
        
        return nil
    }

    /// Возвращает true, если продукт является обязательством и должен подсвечиваться как "кредитный" в списке.
    /// Важно: UI часто показывает сумму обязательства как положительную (долг), поэтому подсветка не может опираться на знак.
    func isAccountLiabilityForTotals(account: FinanceAccount) -> Bool {
        switch account.accountType {
        case .card:
            guard let card = cardByID[account.accountID], card.includeInTotal else { return false }
            let snapshot = CardSnapshotFactory.make(from: card)
            return snapshot.isCreditCard && snapshot.debtAmount > 0.01
        case .credit:
            guard let credit = creditByID[account.accountID] else { return false }
            guard credit.archivedAt == nil else { return false }
            return credit.remainingAmount > 0.01
        case .investment:
            guard let investment = investmentByID[account.accountID], investment.includeInTotal else { return false }
            return investment.investmentType == .negative && investment.amount > 0.01
        }
    }

    /// Группы, которые нужно показывать в списке финансов.
    /// Системная "Без группы" скрывается, если в ней нет видимых счетов.
    func visibleGroupsForList() -> [FinanceGroup] {
        state.groups.filter { !shouldHideGroupInList($0) }
    }

    private func shouldHideGroupInList(_ group: FinanceGroup) -> Bool {
        guard group.name == ungroupedGroupName else { return false }
        return visibleAccountsForGroup(group).isEmpty
    }

    private func visibleAccountsForGroup(_ group: FinanceGroup) -> [FinanceAccount] {
        orderedAccounts(for: group).filter { getAccountInfo(account: $0) != nil }
    }

    func orderedAccounts(for group: FinanceGroup) -> [FinanceAccount] {
        let accounts = (group.accounts ?? []).filter { getAccountInfo(account: $0) != nil }
        if group.usesManualAccountOrdering {
            return accounts.sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.createdAt < rhs.createdAt
            }
        }

        return accounts.sorted { lhs, rhs in
            let lhsAmount = getAccountInfo(account: lhs)?.amount ?? 0
            let rhsAmount = getAccountInfo(account: rhs)?.amount ?? 0
            if lhsAmount != rhsAmount {
                return lhsAmount > rhsAmount
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func scheduleGroupTotalRefresh(for groupUniqueID: String, fallbackCurrency: String? = nil) {
        scheduleBackgroundTask { viewModel in
            guard let group = viewModel.state.groups.first(where: { $0.groupUniqueID == groupUniqueID }) else {
                viewModel.state.groupTotals.removeValue(forKey: groupUniqueID)
                return
            }
            let currency = fallbackCurrency ?? group.displayCurrency ?? viewModel.state.displayCurrency
            let total = await viewModel.calculateGroupTotal(group: group, in: currency)
            viewModel.state.groupTotals[groupUniqueID] = total
        }
    }

    func getInvestmentPositionSubtitle(account: FinanceAccount) -> String? {
        guard account.accountType == .investment,
              let investment = investmentByID[account.accountID],
              investment.isMarketPriced,
              let quantity = investment.marketQuantity, quantity > 0,
              let unitPrice = investment.lastKnownUnitPrice, unitPrice > 0 else {
            return nil
        }

        let quantityText = formatMarketNumber(quantity, maximumFractionDigits: 8)
        let unitPriceText = formatMarketNumber(unitPrice, maximumFractionDigits: 2)
        let currencyCode = resolvedInvestmentCurrency(investment)
        let currencyLabel = MonetaCurrency(rawValue: currencyCode)?.symbol ?? currencyCode
        let quantityUnit = investment.category == .crypto
            ? String(localized: "finances.investment.unit.coins")
            : String(localized: "finances.investment.unit.shares_short")

        return FinancesL10n.format("finances.investment.position_subtitle", quantityText, quantityUnit, unitPriceText, currencyLabel)
    }

    func getInvestmentPurchaseGrowthSubtitle(account: FinanceAccount) -> (text: String, isPositive: Bool)? {
        guard account.accountType == .investment,
              let investment = investmentByID[account.accountID],
              investment.isMarketPriced,
              let purchaseUnitPrice = investment.averagePurchaseUnitPrice,
              purchaseUnitPrice > 0 else {
            return nil
        }

        let purchaseText = formatMarketNumber(purchaseUnitPrice, maximumFractionDigits: 2)
        let currencyCode = resolvedInvestmentCurrency(investment)
        let currencyLabel = MonetaCurrency(rawValue: currencyCode)?.symbol ?? currencyCode
        let growthPercent = investment.positionGrowthPercent ?? 0
        let growthText = formatSignedPercent(growthPercent)
        let isPositive = growthPercent >= 0

        return (FinancesL10n.format("finances.investment.purchase_growth_subtitle", purchaseText, currencyLabel, growthText), isPositive)
    }

    /// Для кредитных карт возвращает остаток лимита, чтобы показывать под суммой долга.
    func getCreditCardLimitRemaining(account: FinanceAccount) -> (amount: Double, currency: String)? {
        guard account.accountType == .card,
              let card = cardByID[account.accountID] else {
            return nil
        }

        let snapshot = CardSnapshotFactory.make(from: card)
        guard snapshot.isCreditCard else { return nil }
        return (snapshot.availableAmount, snapshot.currency)
    }

    func getCreditCardDebt(account: FinanceAccount) -> (amount: Double, currency: String)? {
        guard account.accountType == .card,
              let card = cardByID[account.accountID] else {
            return nil
        }

        let snapshot = CardSnapshotFactory.make(from: card)
        guard snapshot.isCreditCard, snapshot.debtAmount > 0.01 else { return nil }
        return (snapshot.debtAmount, snapshot.currency)
    }

    func getMarketInvestment(account: FinanceAccount) -> Investment? {
        guard account.accountType == .investment else {
            return nil
        }
        guard let investment = investmentByID[account.accountID], investment.isMarketPriced else {
            return nil
        }
        return investment
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

        if let marketSymbol = investment.marketSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
           !marketSymbol.isEmpty {
            if marketSymbol.contains("/") {
                let parts = marketSymbol.split(separator: "/").map(String.init)
                if let quote = parts.last, !quote.isEmpty {
                    return quote
                }
            }
            if marketSymbol.contains("-") {
                let parts = marketSymbol.split(separator: "-").map(String.init)
                if let quote = parts.last, !quote.isEmpty {
                    return quote
                }
            }
        }

        return state.displayCurrency
    }

    static func eligibleSettlementCards(
        from cards: [Card],
        investmentCurrency: String
    ) -> [Card] {
        let normalizedInvestmentCurrency = investmentCurrency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        return cards.filter { card in
            card.archivedAt == nil
                && card.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedInvestmentCurrency
        }
    }

    static func eligibleSettlementAccounts(
        cards: [Card],
        investments: [Investment],
        investmentCurrency: String,
        excludingInvestmentID: String? = nil
    ) -> [CashflowSelectableAccount] {
        let cardOptions = eligibleSettlementCards(
            from: cards,
            investmentCurrency: investmentCurrency
        ).map {
            CashflowSelectableAccount(
                kind: .card(cardID: $0.cardUniqueID),
                title: $0.name,
                currency: $0.currency,
                isFavorite: $0.isFavorite,
                prioritySortOrder: $0.priority.sortOrder,
                updatedAt: $0.updatedAt
            )
        }

        let normalizedCurrency = investmentCurrency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let investmentOptions = investments
            .filter { investment in
                investment.archivedAt == nil
                    && investment.isCashflowAccount
                    && investment.investmentUniqueID != excludingInvestmentID
                    && investment.currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == normalizedCurrency
            }
            .map {
                CashflowSelectableAccount(
                    kind: .investment(investmentID: $0.investmentUniqueID),
                    title: $0.name,
                    currency: $0.currency,
                    isFavorite: $0.isFavorite,
                    prioritySortOrder: $0.priority.sortOrder,
                    updatedAt: $0.updatedAt
                )
            }

        return (cardOptions + investmentOptions).sorted { lhs, rhs in
            if lhs.prioritySortOrder != rhs.prioritySortOrder {
                return lhs.prioritySortOrder < rhs.prioritySortOrder
            }
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite
            }
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private func normalizedInvestmentOrderFunding(
        _ funding: InvestmentOrderFunding,
        cards: [Card],
        investments: [Investment],
        investmentID: String,
        investmentCurrency: String
    ) -> InvestmentOrderFunding {
        guard funding.shouldAffectCardBalance else {
            return .ignored
        }

        let eligibleAccounts = Self.eligibleSettlementAccounts(
            cards: cards,
            investments: investments,
            investmentCurrency: investmentCurrency,
            excludingInvestmentID: investmentID
        )
        guard !eligibleAccounts.isEmpty else {
            return .ignored
        }

        if let settlementAccountKind = funding.settlementAccountKind,
           eligibleAccounts.contains(where: { $0.kind == settlementAccountKind }) {
            return InvestmentOrderFunding(
                settlementAccountKind: settlementAccountKind,
                shouldAffectCardBalance: true
            )
        }

        let preferredAccount = eligibleAccounts.first
        return InvestmentOrderFunding(
            settlementAccountKind: preferredAccount?.kind,
            shouldAffectCardBalance: preferredAccount != nil
        )
    }

    private enum InvestmentSettlementAccount {
        case card(Card)
        case investment(Investment)

        var accountType: FinanceAccountType {
            switch self {
            case .card:
                return .card
            case .investment:
                return .investment
            }
        }

        var accountID: String {
            switch self {
            case .card(let card):
                return card.cardUniqueID
            case .investment(let investment):
                return investment.investmentUniqueID
            }
        }

        var currency: String {
            switch self {
            case .card(let card):
                return card.currency
            case .investment(let investment):
                return investment.currency
            }
        }

        var availableAmount: Double {
            switch self {
            case .card(let card):
                return card.balance
            case .investment(let investment):
                return investment.amount
            }
        }
    }

    private func settlementAccount(
        for funding: InvestmentOrderFunding,
        investmentCurrency: String
    ) -> InvestmentSettlementAccount? {
        guard funding.shouldAffectCardBalance,
              let settlementAccountKind = funding.settlementAccountKind else {
            return nil
        }

        let normalizedInvestmentCurrency = normalizedCurrencyCode(investmentCurrency)
        switch settlementAccountKind {
        case .card(let cardID):
            guard let card = cardByID[cardID],
                  normalizedCurrencyCode(card.currency) == normalizedInvestmentCurrency else {
                return nil
            }
            return .card(card)
        case .investment(let investmentID):
            guard let investment = investmentByID[investmentID],
                  investment.isCashflowAccount,
                  normalizedCurrencyCode(investment.currency) == normalizedInvestmentCurrency else {
                return nil
            }
            return .investment(investment)
        }
    }

    private func stampFrozenRate(on transaction: CashflowTransaction, targetCurrency: String) {
        let normalizedSource = normalizedConversionCurrency(transaction.currency)
        let normalizedTarget = normalizedConversionCurrency(targetCurrency)
        transaction.currency = normalizedSource
        transaction.exchangeRateCurrency = normalizedTarget
        transaction.exchangeRateDate = Calendar.current.startOfDay(for: transaction.transactionDate)
        if normalizedSource == normalizedTarget {
            transaction.exchangeRate = 1.0
        }
    }

    private func formatMarketNumber(_ value: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func formatSignedPercent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: abs(value))) ?? "0"
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(number)%"
    }

    func investmentDisplayName(_ investment: Investment) -> String {
        if let symbol = normalizedInvestmentDisplaySymbol(for: investment), !symbol.isEmpty {
            return symbol
        }

        let trimmedName = investment.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        return String(localized: "finances.dynamics.chart.account_fallback")
    }

    private func normalizedInvestmentDisplaySymbol(for investment: Investment) -> String? {
        guard let rawSymbol = investment.marketSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
              !rawSymbol.isEmpty else {
            return nil
        }

        let withoutPrefix = rawSymbol.split(separator: ":").last.map(String.init) ?? rawSymbol
        guard investment.category == .stocks else {
            return withoutPrefix
        }

        let parts = withoutPrefix.split(separator: ".").map(String.init)
        guard parts.count == 2,
              let suffix = parts.last,
              suffix.count >= 2,
              suffix.count <= 5 else {
            return withoutPrefix
        }

        return parts[0]
    }

    private func executeInvestmentOrder(
        account: FinanceAccount,
        side: InvestmentOrderSide,
        quantity: Double,
        unitPrice: Double,
        funding: InvestmentOrderFunding
    ) {
        guard quantity > 0, unitPrice >= 0 else {
            return
        }
        guard account.accountType == .investment,
              let investment = investmentByID[account.accountID],
              investment.isMarketPriced else {
            return
        }

        let investmentCurrency = resolvedInvestmentCurrency(investment)
        let totalAmount = quantity * unitPrice
        let normalizedFunding = normalizedInvestmentOrderFunding(
            funding,
            cards: state.availableCards,
            investments: state.availableInvestments,
            investmentID: investment.investmentUniqueID,
            investmentCurrency: investmentCurrency
        )
        guard !normalizedFunding.shouldAffectCardBalance || normalizedFunding.settlementAccountKind != nil else {
            return
        }
        let settlementAccountForOrder = settlementAccount(
            for: normalizedFunding,
            investmentCurrency: investmentCurrency
        )
        if normalizedFunding.shouldAffectCardBalance, settlementAccountForOrder == nil {
            return
        }
        if let settlementAccountForOrder,
           side == .buy,
           settlementAccountForOrder.availableAmount + 0.0000001 < totalAmount {
            return
        }

        let oldAmount = investment.amount
        if !investment.hasInitialAmount {
            investment.initialAmount = investment.amount
            investment.hasInitialAmount = true
        }

        let snapshotBefore = marketAssetSnapshot(for: investment)
        let settlementAmountBefore = settlementAccountForOrder?.availableAmount
        let didApply: Bool
        switch side {
        case .buy:
            didApply = investment.applyBuy(quantity: quantity, unitPrice: unitPrice)
        case .sell:
            didApply = investment.applySell(quantity: quantity, unitPrice: unitPrice)
        }
        guard didApply else {
            return
        }
        investment.updatedAt = Date()

        if let settlementAccountForOrder {
            switch settlementAccountForOrder {
            case .card(let card):
                if !card.hasInitialBalance {
                    card.initialBalance = card.balance
                    card.hasInitialBalance = true
                }
                switch side {
                case .buy:
                    card.balance = max(0, card.balance - totalAmount)
                case .sell:
                    card.balance += totalAmount
                }
                card.updatedAt = Date()
            case .investment(let settlementInvestment):
                if !settlementInvestment.hasInitialAmount {
                    settlementInvestment.initialAmount = settlementInvestment.amount
                    settlementInvestment.hasInitialAmount = true
                }
                switch side {
                case .buy:
                    settlementInvestment.amount = max(0, settlementInvestment.amount - totalAmount)
                case .sell:
                    settlementInvestment.amount += totalAmount
                }
                settlementInvestment.updatedAt = Date()
            }
        }

        do {
            var didCreateTransaction = false
            var changedAccountTypes: Set<FinanceAccountType> = [.investment]
            let difference = investment.amount - oldAmount
            let operationGroupID = UUID().uuidString
            if abs(difference) > 0.01 {
                let note = side == .buy
                    ? String(localized: "finances.transaction.note.investment_buy")
                    : String(localized: "finances.transaction.note.investment_sell")
                let transaction = CashflowTransaction(
                    transactionType: .balanceAdjustment,
                    amount: difference,
                    currency: investment.currency,
                    transactionDate: Date(),
                    investmentID: investment.investmentUniqueID,
                    note: note,
                    operationGroupID: operationGroupID
                )
                transaction.applyAssetChangeSnapshot(
                    before: snapshotBefore,
                    after: marketAssetSnapshot(for: investment)
                )
                stampFrozenRate(on: transaction, targetCurrency: investmentCurrency)
                transaction.hasAppliedBalanceEffect = true
                modelContext.insert(transaction)
                didCreateTransaction = true
            }

            if let settlementAccountForOrder {
                let note = side == .buy
                    ? String(localized: "finances.transaction.note.investment_buy")
                    : String(localized: "finances.transaction.note.investment_sell")
                let settlementCardID: String?
                switch settlementAccountForOrder {
                case .card(let card):
                    settlementCardID = card.cardUniqueID
                case .investment:
                    settlementCardID = nil
                }
                let settlementTransaction = CashflowTransaction(
                    transactionType: side == .buy ? .expense : .income,
                    amount: totalAmount,
                    currency: investmentCurrency,
                    transactionDate: Date(),
                    cardID: settlementCardID,
                    // Keep the order leg attached to the traded investment so
                    // audit/history queries can reconstruct the full operation.
                    investmentID: investment.investmentUniqueID,
                    incomeCategory: side == .sell ? .investment : nil,
                    expenseCategory: side == .buy ? .other : nil,
                    note: note,
                    operationGroupID: operationGroupID,
                    affectsCashflowTotals: false
                )
                stampFrozenRate(on: settlementTransaction, targetCurrency: settlementAccountForOrder.currency)
                settlementTransaction.hasAppliedBalanceEffect = true
                modelContext.insert(settlementTransaction)
                didCreateTransaction = true
                changedAccountTypes.insert(settlementAccountForOrder.accountType)
            }

            try modelContext.save()
            loadAccounts()
            calculateTotalAmount()
            state.tradeCelebration = FinanceTradeCelebration(
                side: side,
                investmentName: investmentDisplayName(investment),
                investmentCategory: investment.category,
                totalAmount: totalAmount,
                currency: investmentCurrency
            )

            var affectedGroupIDs: Set<String> = []
            for group in state.groups {
                guard let groupAccounts = group.accounts else { continue }
                if groupAccounts.contains(where: { $0.accountType == .investment && $0.accountID == account.accountID }) {
                    affectedGroupIDs.insert(group.groupUniqueID)
                }
                if let settlementAccountForOrder,
                   groupAccounts.contains(where: {
                       $0.accountType == settlementAccountForOrder.accountType
                           && $0.accountID == settlementAccountForOrder.accountID
                   }) {
                    affectedGroupIDs.insert(group.groupUniqueID)
                }
            }
            for groupID in affectedGroupIDs {
                scheduleGroupTotalRefresh(for: groupID)
            }

            for accountType in changedAccountTypes {
                publishAccountChangedEvent(for: accountType)
            }

            if didCreateTransaction {
                EventBus.shared.publish(FinanceEvent.transactionsUpdated)
            }
        } catch {
            if let settlementAccountForOrder, let settlementAmountBefore {
                switch settlementAccountForOrder {
                case .card(let card):
                    card.balance = settlementAmountBefore
                case .investment(let settlementInvestment):
                    settlementInvestment.amount = settlementAmountBefore
                }
            }
            AppLogger.log(.error, category: "Finance", "Failed to execute market order: \(error.localizedDescription)")
        }
    }

    private func updateMarketInvestmentDetails(
        account: FinanceAccount,
        quantity: Double,
        unitPrice: Double,
        purchaseUnitPrice: Double?
    ) {
        guard account.accountType == .investment,
              let investment = investmentByID[account.accountID],
              investment.isMarketPriced,
              quantity > 0,
              unitPrice > 0 else {
            return
        }

        let snapshotBefore = marketAssetSnapshot(for: investment)
        let oldAmount = investment.amount
        if !investment.hasInitialAmount {
            investment.initialAmount = investment.amount
            investment.hasInitialAmount = true
        }

        investment.marketQuantity = quantity
        investment.lastKnownUnitPrice = unitPrice
        investment.lastKnownPriceUpdatedAt = Date()

        if let purchaseUnitPrice, purchaseUnitPrice > 0 {
            investment.averagePurchaseUnitPrice = purchaseUnitPrice
            investment.totalPurchaseCost = purchaseUnitPrice * quantity
        } else {
            investment.averagePurchaseUnitPrice = nil
            investment.totalPurchaseCost = nil
        }

        investment.recalculateAmountFromPosition()
        investment.updatedAt = Date()

        do {
            var didCreateTransaction = false
            let difference = investment.amount - oldAmount
            if abs(difference) > 0.01 {
                let transaction = CashflowTransaction(
                    transactionType: .balanceAdjustment,
                    amount: difference,
                    currency: investment.currency,
                    transactionDate: Date(),
                    investmentID: investment.investmentUniqueID,
                    note: String(localized: "finances.transaction.note.market_position_edit")
                )
                transaction.applyAssetChangeSnapshot(
                    before: snapshotBefore,
                    after: marketAssetSnapshot(for: investment)
                )
                stampFrozenRate(on: transaction, targetCurrency: resolvedInvestmentCurrency(investment))
                transaction.hasAppliedBalanceEffect = true
                modelContext.insert(transaction)
                didCreateTransaction = true
            }

            try modelContext.save()
            loadAccounts()
            calculateTotalAmount()

            if let accountGroupID = state.groups.first(where: { group in
                group.accounts?.contains(where: { $0.id == account.id }) == true
            })?.groupUniqueID {
                scheduleGroupTotalRefresh(for: accountGroupID)
            }

            if didCreateTransaction {
                EventBus.shared.publish(FinanceEvent.transactionsUpdated)
            }
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to update market investment details: \(error.localizedDescription)")
        }
    }
    
    /// Прогрев котировок на старте приложения без принудительного запроса в сеть.
    /// Обновление будет использовано из локального кэша, а сеть подключится только при реальной необходимости.
    func warmupRemoteDataForStartup() async {
        await refreshCurrencyQuotes(forceRefresh: false)
        await refreshStockPrices(forceRefresh: false)
    }

    private func marketAssetSnapshot(
        for investment: Investment
    ) -> CashflowAssetChangeSnapshot {
        marketAssetSnapshot(
            quantity: investment.marketQuantity,
            unitPrice: investment.lastKnownUnitPrice,
            purchaseUnitPrice: investment.averagePurchaseUnitPrice,
            purchaseCost: investment.totalPurchaseCost,
            totalAmount: investment.amount
        )
    }

    private func marketAssetSnapshot(
        quantity: Double?,
        unitPrice: Double?,
        purchaseUnitPrice: Double?,
        purchaseCost: Double?,
        totalAmount: Double
    ) -> CashflowAssetChangeSnapshot {
        CashflowAssetChangeSnapshot(
            quantity: quantity,
            unitPrice: unitPrice,
            purchaseUnitPrice: purchaseUnitPrice,
            purchaseCost: purchaseCost,
            totalAmount: totalAmount
        )
    }

    func refreshCurrencyQuotes() async {
        state.isLoadingRates = true
        defer { state.isLoadingRates = false }
        await refreshCurrencyQuotes(forceRefresh: true)
        presentRefreshIssueIfNeeded(message: state.currencyConversionWarning)
    }

    private func refreshCurrencyQuotes(forceRefresh: Bool) async {
        if forceRefresh {
            await currencyService.forceRefreshRates()
        } else {
            // getRate сам решит, нужен ли сетевой refresh по внутреннему TTL.
            _ = await currencyService.getRate(from: "USD", to: "RUB")
        }
        await refreshGroupTotalsAndAmounts()
    }

    /// Обновляет рыночные цены только для акций, не создавая транзакций.
    func refreshStockPrices() async {
        state.isLoadingRates = true
        defer { state.isLoadingRates = false }
        let issues = await refreshStockPrices(forceRefresh: true)
        presentRefreshIssueIfNeeded(message: stockRefreshIssueMessage(for: issues))
    }

    /// Лимит символов в одном запросе к backend (market/quotes).
    private static let quoteBatchSize = 8

    @discardableResult
    private func refreshStockPrices(forceRefresh: Bool) async -> StockRefreshIssues {
        let descriptor = FetchDescriptor<Investment>()
        let activeStocks = ((try? modelContext.fetch(descriptor)) ?? []).filter {
            $0.archivedAt == nil && $0.category == .stocks && $0.isMarketPriced
        }

        guard !activeStocks.isEmpty else {
            await refreshGroupTotalsAndAmounts()
            return StockRefreshIssues()
        }

        var didUpdateAnyPrice = false
        var issues = StockRefreshIssues()

        // Собираем уникальные символы и отображение символ -> бумаги (для ошибок по батчу)
        var stockToLookupSymbols: [(stock: Investment, symbols: [String])] = []
        var symbolToStocks: [String: [Investment]] = [:]
        var allSymbolsOrdered: [String] = []
        var seenSymbols: Set<String> = []

        for stock in activeStocks {
            let lookupSymbols = stockQuoteLookupSymbols(for: stock)
            guard !lookupSymbols.isEmpty else {
                issues.notFoundSymbols.insert(stock.name.trimmingCharacters(in: .whitespacesAndNewlines))
                continue
            }
            stockToLookupSymbols.append((stock, lookupSymbols))
            for s in lookupSymbols {
                let key = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !seenSymbols.contains(key) {
                    seenSymbols.insert(key)
                    allSymbolsOrdered.append(key)
                }
                symbolToStocks[key, default: []].append(stock)
            }
        }

        var quotesBySymbol: [String: AssetSummary] = [:]
        var aborted = false
        var stocksAssignedIssueInCatch = Set<ObjectIdentifier>()

        for chunkStart in stride(from: 0, to: allSymbolsOrdered.count, by: Self.quoteBatchSize) {
            guard !aborted else { break }
            let chunk = Array(allSymbolsOrdered[chunkStart ..< min(chunkStart + Self.quoteBatchSize, allSymbolsOrdered.count)])
            do {
                let quotes = try await marketDataClient.fetchQuotes(symbols: chunk)
                for (symbol, quote) in zip(chunk, quotes) {
                    quotesBySymbol[symbol] = quote
                }
            } catch {
                let issueCategory = stockRefreshIssueCategory(for: error)
                let requestID = MarketDataErrorPresentation.requestID(for: error) ?? "none"
                AppLogger.log(
                    .warning,
                    category: "Finance",
                    "Batch quote failed: category=\(issueCategory.rawValue) requestId=\(requestID) error=\(error.localizedDescription)"
                )
                if shouldAbortQuoteAliasRefresh(after: error) {
                    aborted = true
                }
                for symbol in chunk {
                    for stock in symbolToStocks[symbol] ?? [] {
                        if stocksAssignedIssueInCatch.insert(ObjectIdentifier(stock)).inserted {
                            assignStockRefreshIssue(issueCategory, symbol: stockDisplaySymbol(stock), to: &issues)
                        }
                    }
                }
            }
        }

        for (stock, lookupSymbols) in stockToLookupSymbols {
            var refreshed = false
            var lastIssueCategory: MarketDataIssueCategory?
            for symbol in lookupSymbols {
                let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard let quote = quotesBySymbol[key] else { continue }
                switch quote.resolutionStatus {
                case .fresh, .stale:
                    guard let price = quote.price, price > 0 else {
                        if lastIssueCategory == nil {
                            lastIssueCategory = MarketDataErrorPresentation.category(for: quote) ?? .priceUnavailable
                        }
                        continue
                    }
                    stock.lastKnownUnitPrice = price
                    stock.lastKnownPriceUpdatedAt = quote.updatedAtDate ?? Date()
                    stock.marketQuoteLookupKey = quote.canonicalQuoteLookupKey
                    stock.marketExchange = quote.exchange ?? stock.marketExchange
                    stock.marketMICCode = quote.micCode ?? stock.marketMICCode
                    stock.marketCurrency = quote.currency ?? stock.marketCurrency
                    stock.marketProviderRaw = quote.providerSymbol == nil ? stock.marketProviderRaw : "market-backend"
                    stock.recalculateAmountFromPosition()
                    stock.updatedAt = Date()
                    didUpdateAnyPrice = true
                    refreshed = true
                    issues.remove(symbol: stockDisplaySymbol(stock))
                    break
                case .notFound:
                    if lastIssueCategory == nil {
                        lastIssueCategory = .notFound
                    }
                    continue
                case .providerError:
                    if lastIssueCategory == nil {
                        lastIssueCategory = .providerError
                    }
                    AppLogger.log(.warning, category: "Finance", "Provider error while refreshing stock quote for \(symbol)")
                    continue
                }
            }
            if !refreshed, !stocksAssignedIssueInCatch.contains(ObjectIdentifier(stock)) {
                assignStockRefreshIssue(lastIssueCategory, symbol: stockDisplaySymbol(stock), to: &issues)
            }
        }

        if didUpdateAnyPrice {
            do {
                try modelContext.save()
            } catch {
                AppLogger.log(.error, category: "Finance", "Failed to save refreshed stock quotes: \(error.localizedDescription)")
            }
        }

        loadAccounts()
        await refreshGroupTotalsAndAmounts()
        return normalizedStockRefreshIssues(issues)
    }

    /// Backward-compatible alias. Prefer `refreshCurrencyQuotes()`.

    private func shouldAbortQuoteAliasRefresh(after error: Error) -> Bool {
        guard let marketError = error as? MarketAPIClientError else {
            return false
        }

        switch marketError {
        case .backend(let statusCode, let message, _):
            return statusCode == 429 || message.localizedCaseInsensitiveContains("Too Many Requests")
        case .transport(let message):
            return message.localizedCaseInsensitiveContains("Too Many Requests")
        default:
            return false
        }
    }
    func refreshRates() async {
        await refreshCurrencyQuotes()
    }

    func dismissRefreshIssue() {
        state.showRefreshIssue = false
        state.refreshIssueMessage = nil
    }

    private func presentRefreshIssueIfNeeded(message: String?) {
        guard let normalizedMessage = normalizedRefreshIssueMessage(message) else {
            dismissRefreshIssue()
            return
        }
        state.refreshIssueMessage = normalizedMessage
        state.showRefreshIssue = true
    }

    private func normalizedRefreshIssueMessage(_ message: String?) -> String? {
        guard let message else { return nil }
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func normalizedStockRefreshIssues(_ issues: StockRefreshIssues) -> StockRefreshIssues {
        StockRefreshIssues(
            notFoundSymbols: normalizedStockRefreshSymbols(issues.notFoundSymbols),
            priceUnavailableSymbols: normalizedStockRefreshSymbols(issues.priceUnavailableSymbols),
            providerErrorSymbols: normalizedStockRefreshSymbols(issues.providerErrorSymbols),
            authErrorSymbols: normalizedStockRefreshSymbols(issues.authErrorSymbols),
            networkErrorSymbols: normalizedStockRefreshSymbols(issues.networkErrorSymbols),
            httpErrorSymbols: normalizedStockRefreshSymbols(issues.httpErrorSymbols),
            decodingErrorSymbols: normalizedStockRefreshSymbols(issues.decodingErrorSymbols),
            clientErrorSymbols: normalizedStockRefreshSymbols(issues.clientErrorSymbols)
        )
    }

    private func normalizedStockRefreshSymbols(_ values: Set<String>) -> Set<String> {
        Set(
            values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    private func stockRefreshIssueMessage(for issues: StockRefreshIssues) -> String? {
        guard issues.hasIssues else { return nil }

        let notFoundSymbols = issues.notFoundSymbols.sorted()
        let priceUnavailableSymbols = issues.priceUnavailableSymbols.sorted()
        let providerErrorSymbols = issues.providerErrorSymbols.sorted()
        let authErrorSymbols = issues.authErrorSymbols.sorted()
        let networkErrorSymbols = issues.networkErrorSymbols.sorted()
        let httpErrorSymbols = issues.httpErrorSymbols.sorted()
        let decodingErrorSymbols = issues.decodingErrorSymbols.sorted()
        let clientErrorSymbols = issues.clientErrorSymbols.sorted()
        var parts: [String] = []

        if !notFoundSymbols.isEmpty {
            let label = MarketDataErrorPresentation.listLabel(for: .notFound, locale: .current)
            parts.append("\(label): \(notFoundSymbols.joined(separator: ", "))")
        }

        appendStockRefreshSymbols(priceUnavailableSymbols, category: .priceUnavailable, to: &parts)
        appendStockRefreshSymbols(providerErrorSymbols, category: .providerError, to: &parts)
        appendStockRefreshSymbols(authErrorSymbols, category: .authError, to: &parts)
        appendStockRefreshSymbols(networkErrorSymbols, category: .networkError, to: &parts)
        appendStockRefreshSymbols(httpErrorSymbols, category: .httpError, to: &parts)
        appendStockRefreshSymbols(decodingErrorSymbols, category: .decodeError, to: &parts)
        appendStockRefreshSymbols(clientErrorSymbols, category: .clientError, to: &parts)

        return parts.joined(separator: ". ")
    }

    private func appendStockRefreshSymbols(
        _ values: [String],
        category: MarketDataIssueCategory,
        to parts: inout [String]
    ) {
        guard !values.isEmpty else { return }
        let label = MarketDataErrorPresentation.listLabel(for: category, locale: .current)
        parts.append("\(label): \(values.joined(separator: ", "))")
    }

    private func stockRefreshIssueCategory(for error: Error) -> MarketDataIssueCategory {
        MarketDataErrorPresentation.category(for: error)
    }

    private func assignStockRefreshIssue(
        _ category: MarketDataIssueCategory?,
        symbol: String,
        to issues: inout StockRefreshIssues
    ) {
        switch category ?? .notFound {
        case .notFound:
            issues.notFoundSymbols.insert(symbol)
        case .priceUnavailable:
            issues.priceUnavailableSymbols.insert(symbol)
        case .providerError:
            issues.providerErrorSymbols.insert(symbol)
        case .authError:
            issues.authErrorSymbols.insert(symbol)
        case .networkError:
            issues.networkErrorSymbols.insert(symbol)
        case .httpError:
            issues.httpErrorSymbols.insert(symbol)
        case .decodeError:
            issues.decodingErrorSymbols.insert(symbol)
        case .clientError:
            issues.clientErrorSymbols.insert(symbol)
        }
    }

    private func stockQuoteLookupSymbols(for investment: Investment) -> [String] {
        ProviderInstrumentResolver(modelContext: modelContext).quoteLookupSymbols(for: investment)
    }

    private func stockDisplaySymbol(_ investment: Investment) -> String {
        investment.marketSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
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
    
    private func updateGroup(name: String, colorHex: String, displayCurrency: String?) {
        let groupToUpdate: FinanceGroup
        if let existing = state.editingGroup {
            existing.name = name
            existing.colorHex = colorHex
            existing.displayCurrency = displayCurrency
            existing.updatedAt = Date()
            groupToUpdate = existing
        } else {
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
            scheduleGroupTotalRefresh(
                for: groupToUpdate.groupUniqueID,
                fallbackCurrency: displayCurrency ?? state.displayCurrency
            )
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to save group: \(error.localizedDescription)")
        }
    }

    private func moveGroup(sourceGroupID: String, destinationIndex: Int) {
        var groups = visibleGroupsForList()
        guard let sourceIndex = groups.firstIndex(where: { $0.groupUniqueID == sourceGroupID }) else {
            return
        }

        let movedGroup = groups.remove(at: sourceIndex)
        let boundedDestination = min(max(destinationIndex, 0), groups.count)
        groups.insert(movedGroup, at: boundedDestination)

        for (index, group) in groups.enumerated() {
            group.order = index
            group.updatedAt = Date()
        }

        normalizeHiddenGroupOrders(excluding: groups.map(\.groupUniqueID))

        do {
            try modelContext.save()
            loadGroups()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to reorder groups: \(error.localizedDescription)")
        }
    }

    private func moveAccount(sourceAccountID: String, destinationIndex: Int, groupID: String) {
        guard let group = state.groups.first(where: { $0.groupUniqueID == groupID }) else {
            return
        }

        var accounts = orderedAccounts(for: group)
        guard let sourceIndex = accounts.firstIndex(where: { $0.accountUniqueID == sourceAccountID }) else {
            return
        }

        let movedAccount = accounts.remove(at: sourceIndex)
        let boundedDestination = min(max(destinationIndex, 0), accounts.count)
        accounts.insert(movedAccount, at: boundedDestination)
        group.usesManualAccountOrdering = true

        for (index, account) in accounts.enumerated() {
            account.order = index
            account.updatedAt = Date()
        }
        group.updatedAt = Date()

        do {
            try modelContext.save()
            loadGroups()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to reorder accounts: \(error.localizedDescription)")
        }
    }

    private func normalizeHiddenGroupOrders(excluding visibleGroupIDs: [String]) {
        let hiddenGroups = state.groups
            .filter { !visibleGroupIDs.contains($0.groupUniqueID) }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.createdAt < rhs.createdAt
            }

        let startIndex = visibleGroupIDs.count
        for (offset, group) in hiddenGroups.enumerated() {
            group.order = startIndex + offset
        }
    }

    private func nextAccountOrder(in group: FinanceGroup) -> Int {
        ((group.accounts ?? []).map(\.order).max() ?? -1) + 1
    }

    private func addAccountToGroup(accountType: FinanceAccountType, accountID: String, group: FinanceGroup?) {
        let targetGroup = group ?? FinanceSystemGroups.ensureUngroupedGroup(in: modelContext)
        let nextOrder = nextAccountOrder(in: targetGroup)
        
        // Проверяем, не добавлен ли уже этот счет в любую группу
        let allAccountsDescriptor = FetchDescriptor<FinanceAccount>()
        if let allAccounts = try? modelContext.fetch(allAccountsDescriptor) {
            let existingAccount = allAccounts.first { account in
                account.accountType == accountType && account.accountID == accountID
            }
            
            if let existing = existingAccount {
                // Перемещаем счет в новую группу
                existing.group = targetGroup
                if targetGroup.usesManualAccountOrdering {
                    existing.order = nextOrder
                }
                existing.updatedAt = Date()
            } else {
                // Создаем новый счет
                let account = FinanceAccount(accountType: accountType, accountID: accountID)
                account.group = targetGroup
                account.order = nextOrder
                modelContext.insert(account)
            }
        } else {
            // Создаем новый счет
            let account = FinanceAccount(accountType: accountType, accountID: accountID)
            account.group = targetGroup
            account.order = nextOrder
            modelContext.insert(account)
        }
        
        do {
            try modelContext.save()
            loadGroups()
            loadAccounts() // Обновляем список счетов
            updateUnattachedItems() // Обновляем списки непривязанных элементов
            calculateTotalAmount() // Пересчитываем общую сумму
            
            // Пересчитываем сумму группы, в которую был добавлен счет
            scheduleGroupTotalRefresh(for: targetGroup.groupUniqueID)
            
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
            if let groupID = accountGroup?.groupUniqueID {
                scheduleGroupTotalRefresh(for: groupID)
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

            if let groupID = accountGroup?.groupUniqueID {
                scheduleGroupTotalRefresh(for: groupID)
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
        let kind = updateUnderlyingArchiveState(accountType: accountType, accountID: accountID, archivedAt: nil)
        addAccountToGroup(accountType: accountType, accountID: accountID, group: group)

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
                    var didCreateTransaction = false
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
                            transactionNote = String(localized: "finances.transaction.note.quick_debt_change")
                            transactionType = .creditDebtAdjustment
                        } else {
                            transactionAmount = difference
                            transactionNote = String(localized: "finances.transaction.note.quick_balance_change")
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
                        stampFrozenRate(on: transaction, targetCurrency: card.currency)
                        transaction.hasAppliedBalanceEffect = true
                        modelContext.insert(transaction)
                        didCreateTransaction = true
                    }
                    
                    // Атомарное сохранение обновления карты и транзакции (если она была создана)
                    try modelContext.save()
                    
                    loadAccounts()
                    calculateTotalAmount()
                    
                    // Пересчитываем сумму группы, к которой принадлежит счет
                    if let groupID = accountGroup?.groupUniqueID {
                        scheduleGroupTotalRefresh(for: groupID)
                    }
                    publishAccountChangedEvent(for: .card)
                    if didCreateTransaction {
                        EventBus.shared.publish(FinanceEvent.transactionsUpdated)
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
                    var didCreateTransaction = false
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
                            note: String(localized: "finances.transaction.note.quick_remaining_debt_change")
                        )
                        stampFrozenRate(on: transaction, targetCurrency: credit.currency)
                        transaction.hasAppliedBalanceEffect = true
                        modelContext.insert(transaction)
                        didCreateTransaction = true
                    }
                    
                    // Атомарное сохранение обновления кредита и транзакции (если она была создана)
                    try modelContext.save()
                    
                    loadAccounts()
                    calculateTotalAmount()
                    
                    // Пересчитываем сумму группы, к которой принадлежит счет
                    if let groupID = accountGroup?.groupUniqueID {
                        scheduleGroupTotalRefresh(for: groupID)
                    }
                    publishAccountChangedEvent(for: .credit)
                    if didCreateTransaction {
                        EventBus.shared.publish(FinanceEvent.transactionsUpdated)
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

                if investment.isMarketPriced {
                    let previousQuantity = investment.marketQuantity ?? 0
                    let oldUnitPrice = investment.lastKnownUnitPrice
                    investment.marketQuantity = newAmount

                    if let unitPrice = investment.lastKnownUnitPrice, unitPrice > 0 {
                        investment.amount = newAmount * unitPrice
                    } else if previousQuantity > 0 {
                        let inferredUnitPrice = oldAmount / previousQuantity
                        investment.amount = newAmount * inferredUnitPrice
                    }

                    investment.updatedAt = Date()

                    do {
                        var didCreateTransaction = false
                        let difference = investment.amount - oldAmount
                        if abs(difference) > 0.01 {
                            let transaction = CashflowTransaction(
                                transactionType: .balanceAdjustment,
                                amount: difference,
                                currency: investment.currency,
                                transactionDate: Date(),
                                investmentID: investment.investmentUniqueID,
                                note: String(localized: "finances.transaction.note.manual_investment_quantity_change")
                            )
                            transaction.applyAssetChangeSnapshot(
                                before: marketAssetSnapshot(
                                    quantity: previousQuantity,
                                    unitPrice: oldUnitPrice,
                                    purchaseUnitPrice: investment.averagePurchaseUnitPrice,
                                    purchaseCost: investment.totalPurchaseCost,
                                    totalAmount: oldAmount
                                ),
                                after: marketAssetSnapshot(for: investment)
                            )
                            stampFrozenRate(on: transaction, targetCurrency: resolvedInvestmentCurrency(investment))
                            transaction.hasAppliedBalanceEffect = true
                            modelContext.insert(transaction)
                            didCreateTransaction = true
                        }

                        try modelContext.save()

                        loadAccounts()
                        calculateTotalAmount()

                        if let groupID = accountGroup?.groupUniqueID {
                            scheduleGroupTotalRefresh(for: groupID)
                        }
                        publishAccountChangedEvent(for: .investment)
                        if didCreateTransaction {
                            EventBus.shared.publish(FinanceEvent.transactionsUpdated)
                        }
                    } catch {
                        AppLogger.log(.error, category: "Finance", "Failed to update investment quantity: \(error.localizedDescription)")
                    }
                } else {
                    investment.amount = newAmount
                    investment.updatedAt = Date()
                    
                    do {
                        var didCreateTransaction = false
                        // Создаем транзакцию для ручного изменения стоимости актива
                        let difference = newAmount - oldAmount
                        if abs(difference) > 0.01 {
                            let transaction = CashflowTransaction(
                                transactionType: .balanceAdjustment,
                                amount: difference,
                                currency: investment.currency,
                                transactionDate: Date(),
                                investmentID: investment.investmentUniqueID,
                                note: String(localized: "finances.transaction.note.manual_investment_amount_change")
                            )
                            transaction.applyAssetChangeSnapshot(
                                before: marketAssetSnapshot(
                                    quantity: investment.marketQuantity,
                                    unitPrice: investment.lastKnownUnitPrice,
                                    purchaseUnitPrice: investment.averagePurchaseUnitPrice,
                                    purchaseCost: investment.totalPurchaseCost,
                                    totalAmount: oldAmount
                                ),
                                after: marketAssetSnapshot(for: investment)
                            )
                            stampFrozenRate(on: transaction, targetCurrency: resolvedInvestmentCurrency(investment))
                            transaction.hasAppliedBalanceEffect = true
                            modelContext.insert(transaction)
                            didCreateTransaction = true
                        }
                        
                        // Атомарное сохранение обновления инвестиции и транзакции (если она была создана)
                        try modelContext.save()
                        
                        loadAccounts()
                        calculateTotalAmount()
                        
                        // Пересчитываем сумму группы, к которой принадлежит счет
                        if let groupID = accountGroup?.groupUniqueID {
                            scheduleGroupTotalRefresh(for: groupID)
                        }
                        publishAccountChangedEvent(for: .investment)
                        if didCreateTransaction {
                            EventBus.shared.publish(FinanceEvent.transactionsUpdated)
                        }
                    } catch {
                        AppLogger.log(.error, category: "Finance", "Failed to update investment amount: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func updateCreditCardQuickFields(account: FinanceAccount, creditLimit: Double, debt: Double) {
        guard account.accountType == .card,
              let card = cardByID[account.accountID],
              card.cardType == .credit else {
            return
        }

        let accountGroup = state.groups.first { group in
            group.accounts?.contains(where: { $0.accountUniqueID == account.accountUniqueID }) ?? false
        }

        let normalizedLimit = max(0, creditLimit)
        let normalizedDebt = min(max(0, debt), normalizedLimit)

        let oldDebt = max(0, (card.creditLimit ?? 0) - card.balance)
        if !card.hasInitialBalance {
            card.initialBalance = card.balance
            card.hasInitialBalance = true
        }

        card.creditLimit = normalizedLimit
        card.balance = max(0, normalizedLimit - normalizedDebt)
        card.updatedAt = Date()

        do {
            var didCreateTransaction = false
            let difference = normalizedDebt - oldDebt
            if abs(difference) > 0.01 {
                let transaction = CashflowTransaction(
                    transactionType: .creditDebtAdjustment,
                    amount: -difference,
                    currency: card.currency,
                    transactionDate: Date(),
                    cardID: card.cardUniqueID,
                    note: String(localized: "finances.transaction.note.quick_credit_card_fields_change")
                )
                stampFrozenRate(on: transaction, targetCurrency: card.currency)
                transaction.hasAppliedBalanceEffect = true
                modelContext.insert(transaction)
                didCreateTransaction = true
            }

            try modelContext.save()

            loadAccounts()
            calculateTotalAmount()

            if let groupID = accountGroup?.groupUniqueID {
                scheduleGroupTotalRefresh(for: groupID)
            }
            publishAccountChangedEvent(for: .card)
            if didCreateTransaction {
                EventBus.shared.publish(FinanceEvent.transactionsUpdated)
            }
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to update credit card quick fields: \(error.localizedDescription)")
        }
    }

    private func publishAccountChangedEvent(for accountType: FinanceAccountType) {
        switch accountType {
        case .card:
            EventBus.shared.publish(FinanceEvent.cardsUpdated)
        case .credit:
            EventBus.shared.publish(FinanceEvent.creditsUpdated)
        case .investment:
            EventBus.shared.publish(FinanceEvent.investmentsUpdated)
        }
    }
}
