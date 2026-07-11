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

    /// Режим сортировки счетов внутри группы
    var accountSortMode: AccountSortMode = .amountDescending
    
    /// Сообщение об ошибке или предупреждении при конвертации валют
    var currencyConversionWarning: String? = nil

    /// Закрываемое уведомление о том, что часть ручного обновления не выполнилась.
    var refreshIssueMessage: String? = nil
    var showRefreshIssue: Bool = false

    /// Точки спарклайна для дашборда (нормализованы [0..1])
    var dashboardSparkline: [Double] = []

    /// Дельта за период спарклайна (абсолютная, процентная)
    var dashboardWeekDelta: (absolute: Double, percent: Double) = (0.0, 0.0)

    /// Кол-во дней, за которые есть реальные данные в sparkline (2..7)
    var dashboardSparklineDaysCount: Int = 7
}

// StockRefreshIssues перемещён в FinanceMarketDataService.swift

struct ArchivedFinanceAccountRow: Identifiable, Equatable {
    let id: String
    let accountType: FinanceAccountType
    let accountID: String
    let name: String
    let amount: Double
    let currency: String
    let icon: String
    let archivedAt: Date
    let groupName: String?
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
    /// Ручная зачистка: физически удалить легаси-счёт + junction + связанные операции Cashflow. Необратимо.
    case physicallyDeleteLegacyAccount(FinanceAccount)
    /// Track C: перевод легаси-счёта в новое ядро (создаёт core-двойник, скрывает легаси атомарно).
    case convertAccountToCore(FinanceAccount)
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
    case showQuickEditAccountSheet(FinanceAccount)
    case hideQuickEditAccountSheet
    case updateAccountAmount(FinanceAccount, Double)
    case updateCreditCardQuickFields(account: FinanceAccount, creditLimit: Double, debt: Double)
    case showGroupDynamics(FinanceGroup)
    case hideGroupDynamics
    case showAccountDynamics(FinanceAccount)
    case hideAccountDynamics
    case showSavingsGoalSheet
    case hideSavingsGoalSheet
    case setSavingsGoalEnabled(Bool)
    case setSavingsGoalAmount(Double)
    case toggleAmountVisibility
    case setAccountSortMode(AccountSortMode)
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
    private var rateSourceObserver: NSObjectProtocol?
    private var backgroundTasks: [UUID: Task<Void, Never>] = [:]

    /// Быстрые словари для поиска счетов по ID (O(1) вместо O(n))
    @Published private(set) var cardByID: [String: Card] = [:]
    @Published private(set) var creditByID: [String: Credit] = [:]
    @Published private(set) var investmentByID: [String: Investment] = [:]
    private var lastManualStockRefreshAt: Date?

    private static let manualStockRefreshCooldown: TimeInterval = 15

    /// Реальный источник рыночных цен нового ядра (Фаза 4) — переиспользует ТОТ ЖЕ
    /// `marketDataClient`, что и старый мир (`marketDataService` ниже), второй клиент не заводим (S9).
    private(set) lazy var accountMarketPriceService: AccountMarketPriceService = {
        AccountMarketPriceService(modelContext: self.modelContext, marketDataClient: self.marketDataClient)
    }()

    /// Тотал/график нового ядра event-sourcing (Фаза 1a-ui, AC2) — единая точка для Accounts- и
    /// Analytics-тотала (см. `newCoreTotalProvider` в `totalsService` и `FinanceDynamicsViewModel`).
    private(set) lazy var accountsTotalsService: AccountsTotalsService = {
        AccountsTotalsService(
            modelContext: self.modelContext,
            rebuilder: AccountSnapshotRebuilder(modelContainer: self.modelContext.container),
            rateService: self.currencyService,
            marketPriceService: self.accountMarketPriceService
        )
    }()

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
            investmentByIDProvider: { [weak self] in self?.investmentByID ?? [:] },
            newCoreTotalProvider: { [weak self] currency in
                guard let self else { return 0 }
                return await self.accountsTotalsService.totalAt(Date(), in: currency)
            }
        )
    }()

    // snapshotService использует lazy из-за зависимости от totalsService
    private(set) lazy var snapshotService: AccountBalanceSnapshotService = {
        AccountBalanceSnapshotService(
            totalsService: self.totalsService,
            groupsProvider: { [weak self] in self?.state.groups ?? [] }
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
            coreAccountsCount: { [weak self] group in self?.newCoreAccounts(matching: group).count ?? 0 },
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

    /// Track C: конвертация легаси-счёта в новое ядро. Legacy-агностичен (сторону легаси даём замыканием).
    private(set) lazy var legacyAccountConverter: LegacyAccountConverter = {
        LegacyAccountConverter(modelContext: self.modelContext, registry: .shared)
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
            onLoadAccounts: { [weak self] in self?.loadAccounts() },
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

    private var storedAccountSortMode: AccountSortMode {
        get {
            let raw = defaults.string(forKey: "finance_account_sort_mode") ?? ""
            return AccountSortMode(rawValue: raw) ?? .amountDescending
        }
        set { defaults.set(newValue.rawValue, forKey: "finance_account_sort_mode") }
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
        state.accountSortMode = storedAccountSortMode
        subscribeToFinanceEvents()
        rateSourceObserver = NotificationCenter.default.addObserver(
            forName: .currencyRateSourceDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshRates()
            }
        }
        if !skipInitialLoad {
            FinanceSystemGroups.normalizeUngroupedGroupName(in: modelContext)
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
            if let observer = rateSourceObserver {
                NotificationCenter.default.removeObserver(observer)
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
        case .physicallyDeleteLegacyAccount(let account):
            physicallyDeleteLegacyAccount(account)
        case .convertAccountToCore(let account):
            convertAccountToCore(account)

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

        case .showGroupDynamics(let group):
            state.selectedGroupForDynamics = group
            state.showGroupDynamics = true
            
        case .hideGroupDynamics:
            state.showGroupDynamics = false
            state.selectedGroupForDynamics = nil
            
        case .showAccountDynamics(let account):
            loadAccounts()
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

        case .setAccountSortMode(let mode):
            state.accountSortMode = mode
            storedAccountSortMode = mode
            // Сбрасываем ручной порядок: пользователь выбрал критерий сортировки
            for group in state.groups where group.usesManualAccountOrdering {
                group.usesManualAccountOrdering = false
            }
            try? modelContext.save()
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

        // Снапшоты счетов — в фоне, не блокируем критический путь UI
        Task { [weak self] in
            await self?.snapshotService.snapshotIfNeeded()
        }
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

    /// Подсчитать сумму группы в указанной валюте — ОБА мира (Фаза 1.5 слияния групп): легаси-junction
    /// (`FinanceGroup.accounts` через `totalsService`) + счета нового ядра, привязанные к одноимённой
    /// `AccountGroup` (`newCoreAccounts(matching:)`). Пока легаси не снесена (Фаза 5) — читаются оба;
    /// группа целиком из core-счетов больше не даёт 0 (баг §1.3a плана unified-totals).
    ///
    /// ВАЖНО: это ДИСПЛЕЙНЫЙ per-group тотал (карточка группы/редактор/строки). Агрегат «Общий баланс»
    /// (`totalsService.calculateTotalsSnapshot`) вызывает `FinanceTotalsService.calculateGroupTotal`
    /// НАПРЯМУЮ и добавляет core одним лампом через `newCoreTotalProvider` — сюда он не заходит, поэтому
    /// core здесь НЕ задваивается в общем балансе (переключение агрегата на single-world — Фаза 2).
    func calculateGroupTotal(group: FinanceGroup, in currency: String) async -> Double {
        let legacyTotal = await totalsService.calculateGroupTotal(group: group, in: currency)
        let coreAccounts = newCoreAccounts(matching: group)
        guard !coreAccounts.isEmpty else { return legacyTotal }
        let coreTotal = await accountsTotalsService.total(for: coreAccounts, on: nowProvider(), in: currency)
        return legacyTotal + NSDecimalNumber(decimal: coreTotal).doubleValue
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

    /// Возвращает customIconName и customIconColor для счёта (если задано пользователем)
    func customIconInfo(for account: FinanceAccount) -> (iconName: String?, iconColor: String?) {
        switch account.accountType {
        case .card:
            guard let card = cardByID[account.accountID] else { return (nil, nil) }
            return (card.customIconName, card.customIconColor)
        case .credit:
            guard let credit = creditByID[account.accountID] else { return (nil, nil) }
            return (credit.customIconName, credit.customIconColor)
        case .investment:
            guard let investment = investmentByID[account.accountID] else { return (nil, nil) }
            return (investment.customIconName, investment.customIconColor)
        }
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
        groupService.orderedAccounts(
            for: group,
            sortMode: state.accountSortMode,
            amountResolver: { [weak self] account in
                self?.getAccountInfo(account: account)?.amount ?? 0
            },
            nameResolver: { [weak self] account in
                self?.getAccountInfo(account: account)?.name ?? ""
            }
        )
    }

    // MARK: - Новое ядро event-sourcing (Фаза 1a-ui) — сосуществование со старым миром

    /// Счета нового ядра, сопоставленные со старой `FinanceGroup` ПО ИМЕНИ (временный мост до
    /// Фазы 6, см. `AccountsCoreAdditionBridge`). Ungrouped — счета БЕЗ `AccountGroup`
    /// (`account.group == nil`), а не реальная группа с именем "Ungrouped".
    /// Только участвующие сегодня (`participates(on:)`) — архивные скрыты, как у старых счетов.
    func newCoreAccounts(matching group: FinanceGroup) -> [Account] {
        let descriptor: FetchDescriptor<Account>
        if group.name == FinanceSystemGroups.ungroupedName {
            descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.group == nil })
        } else {
            let targetName = group.name
            descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.group?.name == targetName })
        }
        guard let accounts = try? modelContext.fetch(descriptor) else { return [] }

        let today = nowProvider()
        return accounts
            .filter { $0.participates(on: today) }
            .sorted { lhs, rhs in
                lhs.order != rhs.order ? lhs.order < rhs.order : lhs.createdAt < rhs.createdAt
            }
    }

    /// Есть ли хоть один архивный счёт нового ядра — дешёвая проверка для показа пункта «Архив»
    /// в настройках (Фаза 5, задача 2 брифинга), без загрузки самих объектов.
    func hasArchivedNewCoreAccounts() -> Bool {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.archivedAt != nil })
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    /// Баланс счёта нового ядра «сейчас» — прямой синхронный реплей событий (список короткий,
    /// см. Т2 в плане; async-кэш через `AccountsTotalsService` подключается там, где важна
    /// производительность на длинной истории — тотал/график).
    func newCoreBalanceToday(_ account: Account) -> Decimal {
        AccountBalanceEngine.balanceAt(
            events: account.events ?? [],
            kind: account.kind,
            on: nowProvider(),
            marketMeta: account.marketMeta
        )
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
        await accountMarketPriceService.refreshTodayPrices()
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
        await accountMarketPriceService.refreshTodayPrices()
        presentRefreshIssueIfNeeded(message: message)
    }

    /// Обновляет все котировки и акции — используется в pull-to-refresh и фоновом обновлении.
    func refreshAll() async {
        state.isLoadingRates = true
        defer { state.isLoadingRates = false }
        await refreshCurrencyQuotes(forceRefresh: true)
        let stockMessage = await marketDataService.refreshStockPricesManual()
        await accountMarketPriceService.refreshTodayPrices()
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

    /// Кол-во операций Cashflow, привязанных к легаси-счёту (для алерта подтверждения удаления).
    func legacyRelatedTransactionCount(for account: FinanceAccount) -> Int {
        accountService.legacyRelatedTransactionCount(for: account)
    }

    /// Физическое удаление легаси-счёта: сам объект + junction + операции Cashflow. Необратимо.
    private func physicallyDeleteLegacyAccount(_ account: FinanceAccount) {
        let result = accountService.physicallyDeleteLegacyAccount(account)
        switch result.kind {
        case .card: EventBus.shared.publish(FinanceEvent.cardsUpdated)
        case .credit: EventBus.shared.publish(FinanceEvent.creditsUpdated)
        case .investment: EventBus.shared.publish(FinanceEvent.investmentsUpdated)
        case .none: break
        }
        // Каскад затронул операции — просим Cashflow перезагрузиться.
        EventBus.shared.publish(FinanceEvent.transactionsUpdated)
    }

    @discardableResult
    func updateUnderlyingArchiveState(for account: FinanceAccount, archivedAt: Date?) -> UnderlyingAccountKind {
        accountService.updateUnderlyingArchiveState(for: account, archivedAt: archivedAt)
    }

    private func restoreArchivedAccountToGroup(accountType: FinanceAccountType, accountID: String, group: FinanceGroup?) {
        accountService.restoreArchivedAccountToGroup(accountType: accountType, accountID: accountID, group: group)
        loadAccounts()
        loadGroups()
        calculateTotalAmount()
        if accountType == .card { EventBus.shared.publish(FinanceEvent.cardsUpdated) }
        if accountType == .credit { EventBus.shared.publish(FinanceEvent.creditsUpdated) }
    }

    // MARK: - Track C: конвертация легаси-счёта в новое ядро

    /// Уже конвертирован ли легаси-счёт (для UI: показывать «Перевести» или трактовать restore как un-convert).
    func isAccountConvertedToCore(_ account: FinanceAccount) -> Bool {
        legacyAccountConverter.isConverted(legacyUniqueID: account.accountID)
    }

    /// Перевод легаси-счёта в новое ядро (MVP: только opening-balance = текущий баланс легаси).
    /// Атомарно (риск №8): core-двойник создаётся и легаси скрывается (`archivedAt`) в одном акте,
    /// тотал до == после (двойник вносит ровно то, что вносил легаси). Обновление списков/тоталов
    /// старого и нового мира — той же D1-механикой (`investmentsUpdated` → loadAccounts + пересчёт).
    private func convertAccountToCore(_ account: FinanceAccount) {
        guard let plan = makeConversionPlan(for: account) else {
            AppLogger.log(.error, category: "Finance", "Convert to core: не удалось построить план для \(account.accountID)")
            return
        }
        let coreGroup = resolveCoreGroup(for: account)
        let input = LegacyAccountConverter.Input(
            legacyUniqueID: plan.legacyUniqueID,
            name: plan.name,
            currency: plan.currency,
            kind: plan.kind,
            openingBalance: plan.openingBalance,
            group: coreGroup,
            cardMeta: plan.cardMeta,
            loanMeta: plan.loanMeta,
            manualAssetMeta: plan.manualAssetMeta
        )
        do {
            try legacyAccountConverter.convert(input) { [weak self] in
                guard let self else { return }
                // Скрываем легаси В ТОМ ЖЕ акте: archivedAt + save (junction не удаляем — un-convert снимет archivedAt).
                self.accountService.updateUnderlyingArchiveState(for: account, archivedAt: Date())
                try self.modelContext.save()
            }
        } catch {
            AppLogger.log(.error, category: "Finance", "Convert to core failed: \(error.localizedDescription)")
            return
        }
        loadAccounts()
        loadGroups()
        calculateTotalAmount()
        EventBus.shared.publish(FinanceEvent.investmentsUpdated)
        if account.accountType == .card { EventBus.shared.publish(FinanceEvent.cardsUpdated) }
        if account.accountType == .credit { EventBus.shared.publish(FinanceEvent.creditsUpdated) }
    }

    /// Откат конвертации: удаляет core-двойник и возвращает легаси в активные (снимает `archivedAt`).
    /// Работает по (accountType, accountID) — доступен из архивного контекста без `FinanceAccount`.
    private func unconvertAccountFromCore(accountType: FinanceAccountType, accountID: String) {
        do {
            try legacyAccountConverter.unconvert(legacyUniqueID: accountID) { [weak self] in
                guard let self else { return }
                self.accountService.updateUnderlyingArchiveState(accountType: accountType, accountID: accountID, archivedAt: nil)
                try self.modelContext.save()
            }
        } catch {
            AppLogger.log(.error, category: "Finance", "Un-convert failed: \(error.localizedDescription)")
            return
        }
        loadAccounts()
        loadGroups()
        calculateTotalAmount()
        EventBus.shared.publish(FinanceEvent.investmentsUpdated)
        if accountType == .card { EventBus.shared.publish(FinanceEvent.cardsUpdated) }
        if accountType == .credit { EventBus.shared.publish(FinanceEvent.creditsUpdated) }
    }

    private func makeConversionPlan(for account: FinanceAccount) -> LegacyAccountConversion.Plan? {
        switch account.accountType {
        case .card:
            guard let card = cardByID[account.accountID] else { return nil }
            return LegacyAccountConversion.plan(for: card)
        case .credit:
            guard let credit = creditByID[account.accountID] else { return nil }
            return LegacyAccountConversion.plan(for: credit)
        case .investment:
            guard let investment = investmentByID[account.accountID] else { return nil }
            return LegacyAccountConversion.plan(for: investment, currency: resolvedInvestmentCurrency(investment))
        }
    }

    /// Core-группа для двойника: находим/создаём `AccountGroup` по имени легаси-группы (тот же
    /// мост по имени, что `newCoreAccounts(matching:)`). Ungrouped/без группы → nil.
    /// Ф5c.7.3: сведён на `AccountsCoreAdditionBridge` — единый Ungrouped-гард по `allKnownUngroupedNames`
    /// (раньше здесь был локаль-зависимый `ungroupedName`, пропускавший кросс-локальный Ungrouped).
    private func resolveCoreGroup(for account: FinanceAccount) -> AccountGroup? {
        AccountsCoreAdditionBridge.resolveAccountGroup(matching: account.group, in: modelContext)
    }

    func archivedAccountRows() -> [ArchivedFinanceAccountRow] {
        let links = fetchFinanceAccountLinks()
        let groupsByAccount = Dictionary(
            links.map { ("\($0.accountTypeRaw)|\($0.accountID)", $0.group?.name) },
            uniquingKeysWith: { first, _ in first }
        )

        let cardRows = state.archivedCards.map { card in
            let snapshot = CardSnapshotFactory.make(from: card)
            let amount = snapshot.isCreditCard ? snapshot.debtAmount : snapshot.availableAmount
            return ArchivedFinanceAccountRow(
                id: "card|\(card.cardUniqueID)",
                accountType: .card,
                accountID: card.cardUniqueID,
                name: snapshot.name,
                amount: amount,
                currency: snapshot.currency,
                icon: snapshot.icon,
                archivedAt: card.archivedAt ?? card.updatedAt,
                groupName: groupsByAccount["card|\(card.cardUniqueID)"] ?? nil
            )
        }

        let creditRows = state.archivedCredits.map { credit in
            ArchivedFinanceAccountRow(
                id: "credit|\(credit.creditUniqueID)",
                accountType: .credit,
                accountID: credit.creditUniqueID,
                name: credit.name,
                amount: credit.remainingAmount,
                currency: credit.currency,
                icon: credit.creditType.icon,
                archivedAt: credit.archivedAt ?? credit.updatedAt,
                groupName: groupsByAccount["credit|\(credit.creditUniqueID)"] ?? nil
            )
        }

        let investmentRows = state.archivedInvestments.map { investment in
            ArchivedFinanceAccountRow(
                id: "investment|\(investment.investmentUniqueID)",
                accountType: .investment,
                accountID: investment.investmentUniqueID,
                name: investmentDisplayName(investment),
                amount: investment.amount,
                currency: resolvedInvestmentCurrency(investment),
                icon: investment.category.icon,
                archivedAt: investment.archivedAt ?? investment.updatedAt,
                groupName: groupsByAccount["investment|\(investment.investmentUniqueID)"] ?? nil
            )
        }

        return (cardRows + creditRows + investmentRows).sorted { lhs, rhs in
            if lhs.archivedAt != rhs.archivedAt {
                return lhs.archivedAt > rhs.archivedAt
            }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    func restoreArchivedAccount(_ row: ArchivedFinanceAccountRow) {
        // Track C: конвертированный (не просто архивный) легаси возвращается ТОЛЬКО через un-convert —
        // он удаляет core-двойник. Обычный restore оставил бы и легаси, и двойник → двойной счёт (риск №8).
        if legacyAccountConverter.isConverted(legacyUniqueID: row.accountID) {
            unconvertAccountFromCore(accountType: row.accountType, accountID: row.accountID)
            return
        }
        let targetGroup = preferredRestoreGroup(accountType: row.accountType, accountID: row.accountID)
        handle(.restoreArchivedAccountToGroup(accountType: row.accountType, accountID: row.accountID, group: targetGroup))
    }

    private func preferredRestoreGroup(accountType: FinanceAccountType, accountID: String) -> FinanceGroup? {
        fetchFinanceAccountLinks()
            .first { $0.accountType == accountType && $0.accountID == accountID }?
            .group
    }

    private func fetchFinanceAccountLinks() -> [FinanceAccount] {
        (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []
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
