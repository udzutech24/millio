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

    /// Время последнего успешного принудительного обновления
    var lastRefreshedAt: Date? = nil

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

    /// Точки спарклайна для дашборда (нормализованы [0..1])
    var dashboardSparkline: [Double] = []

    /// Дельта за период спарклайна (абсолютная, процентная)
    var dashboardWeekDelta: (absolute: Double, percent: Double) = (0.0, 0.0)

    /// Кол-во дней, за которые есть реальные данные в sparkline (2..7)
    var dashboardSparklineDaysCount: Int = 7
}

// StockRefreshIssues перемещён в FinanceMarketDataService.swift

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
    /// Логические "сейчас" для детерминированных тестов и согласованных временных меток.
    private let nowProvider: () -> Date

    private let defaults = UserDefaults.standard
    private var ungroupedGroupName: String { FinanceSystemGroups.ungroupedName }
    private var financeEventsSubscriptionID: UUID?
    private var backgroundTasks: [UUID: Task<Void, Never>] = [:]

    /// Быстрые словари для поиска счетов по ID (O(1) вместо O(n))
    private var cardByID: [String: Card] = [:]
    private var creditByID: [String: Credit] = [:]
    private var investmentByID: [String: Investment] = [:]
    private var lastManualStockRefreshAt: Date?

    private static let manualStockRefreshCooldown: TimeInterval = 15

    // MARK: - Services
    // totalsService использует lazy из-за замыканий на self
    private(set) lazy var totalsService: FinanceTotalsService = {
        FinanceTotalsService(
            currencyService: self.currencyService,
            groupsProvider: { [weak self] in self?.state.groups ?? [] },
            displayCurrencyProvider: { [weak self] in self?.state.displayCurrency ?? "USD" },
            secondaryDisplayCurrencyProvider: { [weak self] in self?.state.secondaryDisplayCurrency },
            cardByIDProvider: { [weak self] in self?.cardByID ?? [:] },
            creditByIDProvider: { [weak self] in self?.creditByID ?? [:] },
            investmentByIDProvider: { [weak self] in self?.investmentByID ?? [:] }
        )
    }()

    // savingsGoalService использует lazy, т.к. замыкания захватывают self
    private(set) lazy var savingsGoalService: FinanceSavingsGoalService = {
        FinanceSavingsGoalService(
            defaults: self.defaults,
            currencyRateService: self.currencyService
        )
    }()

    // marketDataService использует lazy из-за замыканий на self
    private(set) lazy var marketDataService: FinanceMarketDataService = {
        FinanceMarketDataService(
            modelContext: self.modelContext,
            marketDataClient: self.marketDataClient,
            nowProvider: self.nowProvider,
            onLoadAccounts: { [weak self] in self?.loadAccounts() },
            onRefreshGroupTotals: { [weak self] in await self?.refreshGroupTotalsAndAmounts() }
        )
    }()

    // groupService использует lazy из-за замыканий на self
    private(set) lazy var groupService: FinanceGroupService = {
        FinanceGroupService(
            modelContext: self.modelContext,
            ungroupedGroupName: self.ungroupedGroupName,
            groupsProvider: { [weak self] in self?.state.groups ?? [] },
            accountInfoResolver: { [weak self] account in self?.getAccountInfo(account: account) != nil },
            onLoadGroups: { [weak self] in self?.loadGroups() },
            onLoadAccounts: { [weak self] in self?.loadAccounts() },
            onCalculateTotal: { [weak self] in self?.calculateTotalAmount() },
            onScheduleGroupTotalRefresh: { [weak self] groupID, currency in
                self?.scheduleGroupTotalRefresh(for: groupID, fallbackCurrency: currency)
            },
            onDismissGroupEditor: { [weak self] in
                self?.state.showGroupEditor = false
                self?.state.editingGroup = nil
            },
            onArchiveUnderlying: { [weak self] account, date in
                self?.accountService.updateUnderlyingArchiveState(for: account, archivedAt: date)
            }
        )
    }()

    // accountService использует lazy из-за замыканий на self
    private(set) lazy var accountService: FinanceAccountService = {
        FinanceAccountService(
            modelContext: self.modelContext,
            ungroupedGroupName: self.ungroupedGroupName,
            groupsProvider: { [weak self] in self?.state.groups ?? [] },
            nextOrderProvider: { [weak self] group in self?.groupService.nextAccountOrder(in: group) ?? 0 },
            onAccountsLoaded: { [weak self] payload in
                self?.state.availableCards = payload.availableCards
                self?.state.archivedCards = payload.archivedCards
                self?.state.availableCredits = payload.availableCredits
                self?.state.archivedCredits = payload.archivedCredits
                self?.state.availableInvestments = payload.availableInvestments
                self?.state.archivedInvestments = payload.archivedInvestments
            },
            onCachesRebuilt: { [weak self] payload in
                self?.cardByID = payload.cardByID
                self?.creditByID = payload.creditByID
                self?.investmentByID = payload.investmentByID
            },
            onLoadGroups: { [weak self] in self?.loadGroups() },
            onUpdateUnattachedItems: { [weak self] in self?.updateUnattachedItems() },
            onCalculateTotal: { [weak self] in self?.calculateTotalAmount() },
            onScheduleGroupTotalRefresh: { [weak self] groupID in
                self?.scheduleGroupTotalRefresh(for: groupID)
            },
            onDismissAddAccountSheet: { [weak self] in
                self?.state.showAddAccountSheet = false
                self?.state.selectedGroupForAccount = nil
            }
        )
    }()

    // investmentOrderService использует lazy из-за замыканий на self
    private(set) lazy var investmentOrderService: FinanceInvestmentOrderService = {
        FinanceInvestmentOrderService(
            modelContext: self.modelContext,
            nowProvider: self.nowProvider,
            investmentByIDProvider: { [weak self] in self?.investmentByID ?? [:] },
            cardByIDProvider: { [weak self] in self?.cardByID ?? [:] },
            availableCardsProvider: { [weak self] in self?.state.availableCards ?? [] },
            availableInvestmentsProvider: { [weak self] in self?.state.availableInvestments ?? [] },
            groupsProvider: { [weak self] in self?.state.groups ?? [] },
            resolvedInvestmentCurrency: { [weak self] investment in
                self?.resolvedInvestmentCurrency(investment) ?? investment.currency
            },
            normalizedConversionCurrency: { [weak self] currency in
                self?.normalizedConversionCurrency(currency) ?? currency
            },
            normalizedCurrencyCode: { [weak self] currency in
                self?.normalizedCurrencyCode(currency) ?? currency
            },
            investmentDisplayName: { [weak self] investment in
                self?.investmentDisplayName(investment) ?? investment.name
            },
            onLoadAccounts: { [weak self] in self?.loadAccounts() },
            onCalculateTotalAmount: { [weak self] in self?.calculateTotalAmount() },
            onScheduleGroupTotalRefresh: { [weak self] groupID in
                self?.scheduleGroupTotalRefresh(for: groupID)
            },
            onPublishAccountChangedEvent: { [weak self] accountType in
                self?.publishAccountChangedEvent(for: accountType)
            },
            onUpdateTradeCelebration: { [weak self] celebration in
                self?.state.tradeCelebration = celebration
            }
        )
    }()

    // Делегаты к savingsGoalService для обратной совместимости
    private var storedSavingsGoalEnabled: Bool {
        get { savingsGoalService.storedEnabled }
        set { savingsGoalService.storedEnabled = newValue }
    }

    private var storedSavingsGoalAmount: Double {
        get { savingsGoalService.storedAmount }
        set { savingsGoalService.storedAmount = newValue }
    }

    private var storedSavingsGoalCurrency: String {
        get { savingsGoalService.storedCurrency }
        set { savingsGoalService.storedCurrency = newValue }
    }

    private var storedAmountHidden: Bool {
        get { defaults.bool(forKey: "finance_amount_hidden") }
        set { defaults.set(newValue, forKey: "finance_amount_hidden") }
    }

    init(
        modelContext: ModelContext,
        currencyService: CurrencyRateServiceProtocol? = nil,
        marketDataClient: MarketDataClientProtocol = MarketAPIClient.shared,
        now: @escaping () -> Date = Date.init,
        skipInitialLoad: Bool = false
    ) {
        self.modelContext = modelContext
        self.currencyService = currencyService ?? CurrencyRateService.shared
        self.marketDataClient = marketDataClient

        // Подключаем крипто-курсы через Twelve Data (MarketAPIClient → наш бэк → Twelve Data).
        // Символ: "BTC/USD" → price в USD, инвертируется в getRate для cross-rate.
        if let rateService = self.currencyService as? CurrencyRateService {
            let client = marketDataClient
            rateService.cryptoPriceProviderUSD = { code in
                try? await client.latestPrice(symbol: "\(code)/USD", forceRefresh: false)
            }
        }
        self.nowProvider = now
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
            groupService.deleteGroup(group)

        case .updateGroup(let name, let colorHex, let displayCurrency):
            groupService.updateGroup(
                name: name,
                colorHex: colorHex,
                displayCurrency: displayCurrency,
                editingGroup: state.editingGroup,
                displayCurrencyFallback: state.displayCurrency
            )
            
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
            groupService.moveGroup(sourceGroupID: sourceGroupID, destinationIndex: destinationIndex)

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
            investmentOrderService.executeInvestmentOrder(
                account: account,
                side: side,
                quantity: quantity,
                unitPrice: unitPrice,
                funding: funding
            )

        case .updateMarketInvestmentDetails(let account, let quantity, let unitPrice, let purchaseUnitPrice):
            investmentOrderService.updateMarketInvestmentDetails(
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

    private func normalizedCurrencyCode(_ currency: String) -> String {
        currency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func convertSavingsGoalAmountIfNeeded(from sourceCurrency: String, to targetCurrency: String) async {
        guard let result = await savingsGoalService.convertIfNeeded(
            currentAmount: state.savingsGoalAmount,
            from: sourceCurrency,
            to: targetCurrency
        ) else { return }
        state.savingsGoalAmount = result.newAmount
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
            updateUnattachedItems()
            calculateTotalAmount()
        }
    }
    
    private func loadAccounts() {
        accountService.loadAccounts()
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

    
    private func calculateTotalAmount() {
        scheduleBackgroundTask { viewModel in
            await viewModel.calculateTotalAmountAsync()
        }
    }
    
    func calculateTotalAmountAsync() async {
        state.currencyConversionWarning = nil
        let snapshot = await totalsService.calculateTotalsSnapshot()
        state.totalAmount = snapshot.totalAmount
        state.secondaryTotalAmount = snapshot.secondaryTotalAmount
        if let warning = snapshot.currencyConversionWarning {
            state.currencyConversionWarning = warning
        }
        await computeDashboardSparkline()
    }

    /// Вычисляет 7-дневный спарклайн и дельту для виджета дашборда.
    /// Форма кривой — из DashboardBalanceHistoryStore (снапшоты).
    /// Дельта — через FinanceDynamicsViewModel (replay транзакций, текущие курсы),
    /// аналогично экрану Аналитики, чтобы знаки всегда совпадали.
    func computeDashboardSparkline() async {
        let displayCurrency = state.displayCurrency
        let currentTotal = state.totalAmount
        let daysCount = max(1, SettingsManager.shared.dashboardDeltaPeriodDays)

        DashboardBalanceHistoryStore.save(currentTotal, currency: displayCurrency)

        let rawPoints = DashboardBalanceHistoryStore.dailyAmounts(
            currency: displayCurrency,
            daysCount: daysCount
        )

        let validPoints = rawPoints.compactMap { $0 }
        let validCount = validPoints.count

        // Если истории меньше 2 точек — кривую не рисуем, но дельту всё равно считаем
        guard validCount >= 2 else {
            state.dashboardSparkline = []
            state.dashboardSparklineDaysCount = daysCount
            let (delta, pct) = await computeDashboardDeltaViaAnalytics(startDaysAgo: daysCount, currentTotal: currentTotal)
            state.dashboardWeekDelta = (absolute: delta, percent: pct)
            return
        }

        // Заполняем пропуски: вперёд от первого известного значения
        var filled = [Double](repeating: currentTotal, count: daysCount)
        var lastKnown: Double = validPoints.first ?? currentTotal
        for i in filled.indices {
            if let v = rawPoints[i] {
                lastKnown = v
                filled[i] = v
            } else {
                filled[i] = lastKnown
            }
        }

        let minVal = filled.min() ?? 0.0
        let maxVal = filled.max() ?? 1.0
        let range = maxVal - minVal
        let normalized: [Double]
        if range < 0.01 {
            normalized = filled.map { _ in 0.5 }
        } else {
            // Visual floor: минимальный диапазон = 2% от максимума.
            // Предотвращает визуальный "обрыв" при малых колебаниях.
            let visualRange = max(range, maxVal * 0.02)
            let mid = (minVal + maxVal) / 2.0
            let lo = mid - visualRange / 2.0
            normalized = filled.map { min(1.0, max(0.0, ($0 - lo) / visualRange)) }
        }

        state.dashboardSparkline = normalized

        // Лейбл и дельта — всегда по выбранному периоду, а не по наличию данных в store.
        // Store используется только для формы кривой (sparkline shape).
        state.dashboardSparklineDaysCount = daysCount

        // Дельта через replay транзакций — согласованно с Аналитикой
        let (delta, pct) = await computeDashboardDeltaViaAnalytics(startDaysAgo: daysCount, currentTotal: currentTotal)
        state.dashboardWeekDelta = (absolute: delta, percent: pct)
    }

    /// Вычисляет дельту баланса за период startDaysAgo→сегодня через FinanceDynamicsViewModel.
    /// Использует те же текущие курсы и replay транзакций, что и экран Аналитики.
    private func computeDashboardDeltaViaAnalytics(startDaysAgo: Int, currentTotal: Double) async -> (Double, Double) {
        guard startDaysAgo > 0 else { return (0.0, 0.0) }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let startDayBegin = calendar.date(byAdding: .day, value: -startDaysAgo, to: today),
              let startDayEnd = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: startDayBegin)
        else { return (0.0, 0.0) }

        let dynamicsVM = FinanceDynamicsViewModel(modelContext: modelContext, financeViewModel: self)
        dynamicsVM.loadData()

        let accounts = dynamicsVM.getAccountsForCalculation()
        let cardIDs = Set(accounts.compactMap { $0.accountType == .card ? $0.accountID : nil })

        let startBalance = await dynamicsVM.calculateBalanceAtDate(
            accounts: accounts,
            date: startDayEnd,
            accountCardIDs: cardIDs,
            debtAsNegative: true,
            includeInitialBeforeCreation: false
        )

        let delta = currentTotal - startBalance
        let pct = abs(startBalance) < 0.01 ? 0.0 : (delta / abs(startBalance)) * 100.0
        return (delta, pct)
    }

    /// Подсчитать сумму группы в указанной валюте
    func calculateGroupTotal(group: FinanceGroup, in currency: String) async -> Double {
        await totalsService.calculateGroupTotal(group: group, in: currency)
    }


    private func normalizedConversionCurrency(_ currency: String) -> String {
        totalsService.normalizedConversionCurrency(currency)
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
        groupService.visibleGroupsForList()
    }

    func orderedAccounts(for group: FinanceGroup) -> [FinanceAccount] {
        groupService.orderedAccounts(for: group, amountResolver: { [weak self] account in
            self?.getAccountInfo(account: account)?.amount ?? 0
        })
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
            ? L("finances.investment.unit.coins")
            : L("finances.investment.unit.shares_short")

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
        totalsService.resolvedInvestmentCurrency(investment, displayCurrency: state.displayCurrency)
    }

    static func eligibleSettlementCards(
        from cards: [Card],
        investmentCurrency: String
    ) -> [Card] {
        FinanceInvestmentOrderService.eligibleSettlementCards(from: cards, investmentCurrency: investmentCurrency)
    }

    static func eligibleSettlementAccounts(
        cards: [Card],
        investments: [Investment],
        investmentCurrency: String,
        excludingInvestmentID: String? = nil
    ) -> [CashflowSelectableAccount] {
        FinanceInvestmentOrderService.eligibleSettlementAccounts(
            cards: cards,
            investments: investments,
            investmentCurrency: investmentCurrency,
            excludingInvestmentID: excludingInvestmentID
        )
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

        return L("finances.dynamics.chart.account_fallback")
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

    /// Прогрев котировок на старте приложения без принудительного запроса в сеть.
    /// Обновление будет использовано из локального кэша, а сеть подключится только при реальной необходимости.
    func warmupRemoteDataForStartup() async {
        await refreshCurrencyQuotes(forceRefresh: false)
        await marketDataService.refreshStockPrices(forceRefresh: false)
        state.lastRefreshedAt = Date()
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
        let message = await marketDataService.refreshStockPricesManual()
        presentRefreshIssueIfNeeded(message: message)
    }

    /// Обновляет все котировки и акции — используется в pull-to-refresh и фоновом обновлении.
    func refreshAll() async {
        state.isLoadingRates = true
        defer { state.isLoadingRates = false }
        await refreshCurrencyQuotes(forceRefresh: true)
        let stockMessage = await marketDataService.refreshStockPricesManual()
        state.lastRefreshedAt = Date()
        presentRefreshIssueIfNeeded(message: stockMessage ?? state.currencyConversionWarning)
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

    private func addAccountToGroup(accountType: FinanceAccountType, accountID: String, group: FinanceGroup?) {
        accountService.addAccountToGroup(accountType: accountType, accountID: accountID, group: group)
    }

    private func removeAccountFromGroup(_ account: FinanceAccount) {
        let kind = accountService.removeAccountFromGroup(account)
        if kind == .card { EventBus.shared.publish(FinanceEvent.cardsUpdated) }
        if kind == .credit { EventBus.shared.publish(FinanceEvent.creditsUpdated) }
    }

    private func deleteAccountPermanently(_ account: FinanceAccount) {
        let kind = accountService.deleteAccountPermanently(account)
        if kind == .card { EventBus.shared.publish(FinanceEvent.cardsUpdated) }
        if kind == .credit { EventBus.shared.publish(FinanceEvent.creditsUpdated) }
    }

    @discardableResult
    func updateUnderlyingArchiveState(for account: FinanceAccount, archivedAt: Date?) -> UnderlyingAccountKind {
        accountService.updateUnderlyingArchiveState(for: account, archivedAt: archivedAt)
    }

    private func restoreArchivedAccountToGroup(accountType: FinanceAccountType, accountID: String, group: FinanceGroup?) {
        accountService.restoreArchivedAccountToGroup(accountType: accountType, accountID: accountID, group: group)
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
                            transactionNote = L("finances.transaction.note.quick_debt_change")
                            transactionType = .creditDebtAdjustment
                        } else {
                            transactionAmount = difference
                            transactionNote = L("finances.transaction.note.quick_balance_change")
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
                            note: L("finances.transaction.note.quick_remaining_debt_change")
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
                                note: L("finances.transaction.note.manual_investment_quantity_change")
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
                                note: L("finances.transaction.note.manual_investment_amount_change")
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
                    note: L("finances.transaction.note.quick_credit_card_fields_change")
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
