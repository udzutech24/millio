//
//  CashflowViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Cashflow ViewModel

@MainActor
final class CashflowViewModel: ViewModelProtocol {
    typealias State = CashflowState
    typealias Action = CashflowAction
    
    @Published var state = CashflowState()
    
    let modelContext: ModelContext
    private let historicalRateStore: HistoricalRateStore
    private let notificationManager: NotificationManagerProtocol
    let now: () -> Date
    private let assetsSnapshotProvider: ((Date, Date, String) async -> (start: Double, end: Double)?)?
    private let defaults: UserDefaults
    private let categoryPinPrefs: CashflowCategoryPinPrefs
    let bulkExpenseMerchantPrefs: CashflowBulkExpenseMerchantCategoryPrefs
    let budgetAutoRepeatPrefs = BudgetAutoRepeatPrefs()
    
    private var eventSubscriptionID: UUID?
    private var restoreReloadTask: Task<Void, Never>?

    // MARK: - Services
    let historyService: CashflowHistoryService
    // currencyService использует lazy, т.к. замыкания захватывают self
    private(set) lazy var currencyService: CashflowCurrencyService = {
        CashflowCurrencyService(
            historicalRateStore: self.historicalRateStore,
            now: self.now,
            cardResolver: { [weak self] cardID in self?.card(for: cardID) },
            displayCurrencyProvider: { [weak self] in self?.state.displayCurrency ?? "" },
            onEstimatedRateWarning: { [weak self] date in self?.markEstimatedRateWarning(on: date) }
        )
    }()
    // categoryService использует lazy из-за замыканий на self
    private(set) lazy var categoryService: CashflowCategoryService = {
        CashflowCategoryService(
            modelContext: self.modelContext,
            categoryPinPrefs: self.categoryPinPrefs,
            bulkExpenseMerchantPrefs: self.bulkExpenseMerchantPrefs,
            now: self.now,
            customCategoriesProvider: { [weak self] in self?.state.customCategories ?? [] },
            systemCategoryOverridesProvider: { [weak self] in self?.state.systemCategoryOverrides ?? [] },
            onCategoriesChanged: { [weak self] in
                self?.loadCustomCategories()
                self?.loadSystemCategoryOverrides()
                self?.loadTransactions()
            }
        )
    }()
    // analyticsService использует lazy из-за замыканий на self
    private(set) lazy var analyticsService: CashflowAnalyticsService = {
        CashflowAnalyticsService(
            modelContext: self.modelContext,
            now: self.now,
            transactionsProvider: { [weak self] in self?.state.transactions ?? [] },
            convertAmountForTransaction: { [weak self] transaction, currency in
                guard let self else { return 0 }
                return await self.currencyService.convertAmountForTransaction(transaction, to: currency)
            },
            incomeCategoryDisplayNameResolver: { [weak self] raw in
                self?.incomeCategoryDisplayName(for: raw) ?? ""
            },
            expenseCategoryDisplayNameResolver: { [weak self] raw in
                self?.expenseCategoryDisplayName(for: raw) ?? ""
            },
            assetsSnapshotProvider: self.assetsSnapshotProvider,
            resolveAssetsSnapshotFromFinance: { [weak self] start, end in
                await self?.resolveAssetsSnapshotFromFinance(startDate: start, endDate: end)
            },
            onLoadBudgetPlanForCurrentPeriod: { [weak self] in self?.loadBudgetPlanForCurrentPeriod() }
        )
    }()
    // scheduledService использует lazy из-за замыканий на self
    private(set) lazy var scheduledService: CashflowScheduledService = {
        CashflowScheduledService(
            modelContext: self.modelContext,
            defaults: self.defaults,
            now: self.now,
            transactionsProvider: { [weak self] in self?.state.transactions ?? [] },
            onTransactionsMutated: { [weak self] in self?.loadTransactionsSnapshot() },
            onResolveExchangeInfo: { [weak self] transaction in
                guard let self else { return CashflowExchangeInfo(rate: nil, rateDate: nil, rateCurrency: nil) }
                return await self.currencyService.resolveExchangeInfo(for: transaction)
            },
            onApplyRecurringToCard: { [weak self] transaction in
                await self?.persistenceService.applyRecurringTransactionToCardBalance(transaction)
            },
            onApplyDuePlannedEffect: { [weak self] transaction in
                try await self?.persistenceService.applyAccountBalanceEffect(for: transaction, direction: .apply)
            }
        )
    }()
    // persistenceService использует lazy из-за замыканий на self
    private(set) lazy var persistenceService: CashflowPersistenceService = {
        CashflowPersistenceService(
            modelContext: self.modelContext,
            now: self.now,
            currencyService: self.currencyService,
            cardProvider: { [weak self] cardID in self?.card(for: cardID) },
            investmentProvider: { [weak self] investmentID in self?.investment(for: investmentID) },
            transactionsProvider: { [weak self] in self?.state.transactions ?? [] },
            editingTransactionProvider: { [weak self] in self?.state.editingTransaction },
            normalizedCurrencyCode: { [weak self] currency in self?.normalizedCurrencyCode(currency) },
            ensureSystemCategoriesVisible: { [weak self] rawValues, kind, nowDate in
                self?.categoryService.ensureSystemCategoriesVisible(
                    rawValues: rawValues.compactMap { $0 },
                    kind: kind,
                    nowDate: nowDate
                )
            },
            onTransactionsMutated: { [weak self] in self?.loadTransactions() },
            onTransactionsSnapshotMutated: { [weak self] in self?.loadTransactionsSnapshot() },
            onCardsUpdated: { [weak self] in self?.loadCards() },
            onInvestmentsUpdated: { [weak self] in self?.loadInvestments() },
            onSetDeleteErrorMessage: { [weak self] msg in self?.state.deleteBalanceUpdateErrorMessage = msg },
            onDismissEditor: { [weak self] in
                self?.state.showTransactionEditor = false
                self?.state.editingTransaction = nil
                self?.state.creatingTransactionType = nil
            },
            onEditorIsShowing: { [weak self] in self?.state.showTransactionEditor ?? false },
            onEditingTransactionMatchesExplicit: { [weak self] explicit in
                self?.state.editingTransaction?.persistentModelID == explicit.persistentModelID
            }
        )
    }()

    init(
        modelContext: ModelContext,
        notificationManager: NotificationManagerProtocol? = nil,
        now: @escaping () -> Date = Date.init,
        assetsSnapshotProvider: ((Date, Date, String) async -> (start: Double, end: Double)?)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContext
        self.historicalRateStore = HistoricalRateStore(modelContext: modelContext)
        self.historyService = CashflowHistoryService(modelContext: modelContext)
        self.notificationManager = notificationManager ?? NotificationManager.shared
        self.now = now
        self.assetsSnapshotProvider = assetsSnapshotProvider
        self.defaults = defaults
        self.categoryPinPrefs = CashflowCategoryPinPrefs(defaults: defaults)
        self.bulkExpenseMerchantPrefs = CashflowBulkExpenseMerchantCategoryPrefs(defaults: defaults)
        state.displayCurrency = SettingsManager.shared.primaryCurrencyCode
        let nowDate = now()
        state.selectedMonth = nowDate
        state.selectedQuarter = nowDate
        state.selectedYear = nowDate
        resetToDefaultPeriodInternal(referenceDate: nowDate)
        loadCards()
        loadInvestments()
        loadLinkedInvestments()
        loadTransactions()
        loadCustomCategories()
        loadSystemCategoryOverrides()
        loadBudgetPlanForCurrentPeriod()
        loadAvailableCurrencies()
        subscribeToFinanceEvents()
    }

    deinit {
        restoreReloadTask?.cancel()
        if let id = eventSubscriptionID {
            Task { @MainActor in
                EventBus.shared.unsubscribe(id)
            }
        }
    }
    
    func handle(_ action: CashflowAction) {
        switch action {
        case .loadTransactions:
            loadTransactions()
            
        case .addTransaction(let type):
            // Обновляем список карт перед открытием редактора, чтобы видеть актуальные данные
            loadCards()
            loadInvestments()
            loadLinkedInvestments()
            state.creatingTransactionType = type
            state.editingTransaction = nil
            state.showTransactionEditor = true
            
        case .editTransaction(let transaction):
            // Обновляем список карт перед редактированием на случай изменений в финансах
            loadCards()
            loadInvestments()
            loadLinkedInvestments()
            state.editingTransaction = transaction
            state.creatingTransactionType = nil
            state.showTransactionEditor = true
            
        case .deleteTransaction(let transaction, let recalculate):
            state.deleteBalanceUpdateErrorMessage = nil
            if recalculate {
                Task(priority: .userInitiated) { @MainActor in
                    await persistenceService.deleteTransactionAsync(transaction, recalculate: true)
                }
            } else {
                persistenceService.deleteTransactionWithoutRecalculation(transaction)
            }

        case .updateTransaction(let transaction):
            Task(priority: .userInitiated) { @MainActor in
                await persistenceService.persistTransaction(transaction)
            }
            
        case .hideTransactionEditor:
            state.showTransactionEditor = false
            state.editingTransaction = nil
            state.creatingTransactionType = nil
            
        case .setChartPeriod(let period):
            state.chartPeriod = period
            loadBudgetPlanForCurrentPeriod()
            updateChartData()

        case .resetToDefaultPeriod:
            resetToDefaultPeriodInternal(referenceDate: now())
            loadBudgetPlanForCurrentPeriod()
            updateChartData()

        case .setCustomPeriod(let start, let end):
            let calendar = Calendar.current
            state.customStartDate = calendar.startOfDay(for: start)
            state.customEndDate = calendar.startOfDay(for: end)
            state.chartPeriod = .custom
            loadBudgetPlanForCurrentPeriod()
            updateChartData()
            
        case .setSelectedMonth(let date):
            state.selectedMonth = date
            state.chartPeriod = .specificMonth
            loadBudgetPlanForCurrentPeriod()
            updateChartData()
            
        case .setSelectedQuarter(let date):
            state.selectedQuarter = date
            state.chartPeriod = .specificQuarter
            loadBudgetPlanForCurrentPeriod()
            updateChartData()
            
        case .setSelectedYear(let date):
            state.selectedYear = date
            state.chartPeriod = .specificYear
            loadBudgetPlanForCurrentPeriod()
            updateChartData()
            
        case .showPeriodSelector:
            state.showPeriodSelector = true
            
        case .hidePeriodSelector:
            state.showPeriodSelector = false
            
        case .showTransactionsHistory:
            state.showTransactionsHistory = true
            
        case .hideTransactionsHistory:
            state.showTransactionsHistory = false
            
        case .showCurrencySelector:
            state.showCurrencySelector = true
            
        case .hideCurrencySelector:
            state.showCurrencySelector = false
            
        case .setDisplayCurrency(let currency):
            state.displayCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            updateChartData()

        case .syncDisplayCurrencyWithPrimary(let primaryCurrency):
            let normalized = primaryCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty else { return }
            guard state.displayCurrency != normalized else { return }
            state.displayCurrency = normalized
            updateChartData()

        case .syncPrimaryCurrencyChange(let old, let new):
            let oldNormalized = old.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let newNormalized = new.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !oldNormalized.isEmpty, !newNormalized.isEmpty else { return }
            state.displayCurrency = newNormalized
            updateChartData()
            
        case .loadCards:
            loadCards()

        case .refreshExchangeRates:
            guard !state.isRefreshingExchangeRates else { return }
            state.isRefreshingExchangeRates = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                await CurrencyRateService.shared.forceRefreshRates()
                CurrencyRateService.shared.resetHistoricalUnavailableRequestCache()
                self.historicalRateStore.resetUnavailableRequestCache()
                self.state.isRefreshingExchangeRates = false
                self.updateChartData()
            }

        case .dismissCurrencyConversionWarning:
            state.currencyConversionWarning = nil
            state.currencyConversionWarningDate = nil

        case .dismissDeleteBalanceUpdateError:
            state.deleteBalanceUpdateErrorMessage = nil
        }
    }
    
    func loadTransactions() {
        loadTransactionsSnapshot()
        scheduleDueAutoApplyIfNeeded()
        scheduleRecurringGeneration()
    }

    private func loadTransactionsSnapshot() {
        let descriptor = FetchDescriptor<CashflowTransaction>(
            sortBy: [SortDescriptor(\.transactionDate, order: .reverse)]
        )
        state.transactions = (try? modelContext.fetch(descriptor)) ?? []
        Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self else { return }
            await self.notificationManager.scheduleCashflowScheduledReminders(for: self.state.transactions)
        }
        applyFilters()
        loadAvailableCurrencies()
        updateChartData()
    }

    /// Stable UI sync signature for Cashflow screens that depend on live card balances.
    /// Includes fields that change account availability, picker eligibility, or visible balance copy.
    static func cardSyncSignature(for cards: [Card]) -> [String] {
        cards.map { card in
            [
                card.cardUniqueID,
                card.currency,
                card.cardTypeRaw,
                String(card.balance),
                String(card.creditLimit ?? 0),
                String(card.isFavorite),
                String(card.archivedAt?.timeIntervalSince1970 ?? 0),
                String(card.updatedAt.timeIntervalSince1970)
            ].joined(separator: "_")
        }
    }

    private func scheduleRecurringGeneration() {
        scheduledService.scheduleRecurringGeneration()
    }

    private func scheduleDueAutoApplyIfNeeded() {
        scheduledService.scheduleDueAutoApplyIfNeeded()
    }
    
    func loadCards() {
        state.allCards = CardCatalog.fetchAll(in: modelContext)
        state.availableCards = state.allCards.filter { $0.archivedAt == nil }
    }

    private func loadInvestments() {
        let descriptor = FetchDescriptor<Investment>()
        let allInvestments = (try? modelContext.fetch(descriptor)) ?? []
        state.availableInvestments = allInvestments.filter { $0.archivedAt == nil }
    }

    func loadBudgetPlanForCurrentPeriod() {
        let descriptor = currentBudgetPeriodDescriptor()
        let budgetFetch = FetchDescriptor<BudgetPlan>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let plans = (try? modelContext.fetch(budgetFetch)) ?? []
        let activePlan = plans.first(where: { $0.matches(descriptor, categoryKind: .expense) })
        state.activeBudgetPlan = activePlan
        if let activePlan {
            state.activeBudgetCategoryLimits = fetchBudgetCategoryLimits(for: activePlan.budgetID)
        } else {
            state.activeBudgetCategoryLimits = []
        }
    }

    func fetchBudgetCategoryLimits(for budgetID: String) -> [BudgetCategoryLimit] {
        let descriptor = FetchDescriptor<BudgetCategoryLimit>(
            predicate: #Predicate { $0.budgetID == budgetID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func fetchBudgetPlan(
        matching descriptor: BudgetPeriodDescriptor,
        categoryKind: CashflowCategoryKind
    ) -> BudgetPlan? {
        let budgetFetch = FetchDescriptor<BudgetPlan>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let plans = (try? modelContext.fetch(budgetFetch)) ?? []
        return plans.first(where: { $0.matches(descriptor, categoryKind: categoryKind) })
    }

    func currentBudgetPeriodDescriptor(calendar: Calendar = .current) -> BudgetPeriodDescriptor {
        let range = getDateRange()
        let start = calendar.startOfDay(for: min(range.0, range.1))
        let end = calendar.startOfDay(for: max(range.0, range.1))

        switch state.chartPeriod {
        case .year, .specificYear:
            return BudgetPeriodDescriptor(
                type: .year,
                startDate: start,
                endDate: end,
                anchorYear: calendar.component(.year, from: state.selectedYear),
                anchorMonth: 1
            )
        case .quarter, .specificQuarter:
            let month = calendar.component(.month, from: state.selectedQuarter)
            let quarterStartMonth = ((max(1, month) - 1) / 3) * 3 + 1
            return BudgetPeriodDescriptor(
                type: .quarter,
                startDate: start,
                endDate: end,
                anchorYear: calendar.component(.year, from: state.selectedQuarter),
                anchorMonth: quarterStartMonth
            )
        case .custom:
            return BudgetPeriodDescriptor(
                type: .custom,
                startDate: start,
                endDate: end,
                anchorYear: calendar.component(.year, from: start),
                anchorMonth: calendar.component(.month, from: start)
            )
        case .month, .specificMonth:
            return BudgetPeriodDescriptor(
                type: .month,
                startDate: start,
                endDate: end,
                anchorYear: calendar.component(.year, from: state.selectedMonth),
                anchorMonth: calendar.component(.month, from: state.selectedMonth)
            )
        }
    }

    func monthlyBudgetPeriodDescriptor(for month: Date, calendar: Calendar = .current) -> BudgetPeriodDescriptor {
        let monthStart = Self.monthStart(for: month, calendar: calendar)
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart
        return BudgetPeriodDescriptor(
            type: .month,
            startDate: monthStart,
            endDate: calendar.startOfDay(for: monthEnd),
            anchorYear: calendar.component(.year, from: monthStart),
            anchorMonth: calendar.component(.month, from: monthStart)
        )
    }

    private func loadLinkedInvestments() {
        let descriptor = FetchDescriptor<FinanceAccount>()
        let allAccounts = (try? modelContext.fetch(descriptor)) ?? []
        state.linkedInvestmentIDs = Set(
            allAccounts.compactMap { account in
                guard account.group != nil, account.accountType == .investment else { return nil }
                return account.accountID
            }
        )
    }

    private func loadCustomCategories() {
        let descriptor = FetchDescriptor<CashflowCustomCategory>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        state.customCategories = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func loadSystemCategoryOverrides() {
        let descriptor = FetchDescriptor<CashflowSystemCategoryOverride>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        state.systemCategoryOverrides = (try? modelContext.fetch(descriptor)) ?? []
    }

    private func reloadAfterRestoreCompleted() {
        restoreReloadTask?.cancel()
        // Decouple restore refresh from synchronous EventBus delivery to avoid
        // doing a full SwiftData reload inline on the publisher's QoS.
        restoreReloadTask = Task(priority: .userInitiated) { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            self.loadTransactions()
            self.loadCards()
            self.loadInvestments()
            self.loadLinkedInvestments()
            self.loadCustomCategories()
            self.loadSystemCategoryOverrides()
        }
    }

    private func subscribeToFinanceEvents() {
        eventSubscriptionID = EventBus.shared.subscribe { [weak self] event in
            guard let self else { return }
            switch event {
            case FinanceEvent.cardsUpdated:
                self.loadCards()
            case FinanceEvent.investmentsUpdated:
                self.loadInvestments()
                self.loadLinkedInvestments()
            case FinanceEvent.transactionsUpdated:
                self.loadTransactions()
            case BackupEvent.restoreCompleted:
                self.reloadAfterRestoreCompleted()
            default:
                break
            }
        }
    }
    
    private func loadAvailableCurrencies() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            var extraCodes = Set<String>()
            for transaction in state.transactions {
                extraCodes.insert(transaction.currency)
            }
            extraCodes.insert(state.displayCurrency)
            state.availableCurrencies = CurrencySelectionSupport.pickerCodes(extraCodes: Array(extraCodes))
        }
    }
    
    private func applyFilters() {
        state.filteredTransactions = state.transactions
    }

    func nextChartUpdateRevision() -> Int {
        analyticsService.nextChartUpdateRevision()
    }

    func isCurrentChartUpdateRevision(_ revision: Int) -> Bool {
        analyticsService.isCurrentChartUpdateRevision(revision)
    }

    // MARK: - Scheduled Transactions

    func recurringTemplates(
        for kind: CashflowCategoryKind,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowTransaction] {
        scheduledService.recurringTemplates(for: kind, relativeTo: referenceDate)
    }

    func plannedOneTimeTransactions(
        for kind: CashflowCategoryKind,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowTransaction] {
        scheduledService.plannedOneTimeTransactions(for: kind, relativeTo: referenceDate)
    }

    func scheduledPlannerEntries(
        for kind: CashflowCategoryKind,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowScheduledEntry] {
        scheduledService.scheduledPlannerEntries(for: kind, relativeTo: referenceDate)
    }

    func scheduledCalendarEntries(
        for kind: CashflowCategoryKind,
        month: Date,
        relativeTo referenceDate: Date? = nil
    ) -> [CashflowScheduledEntry] {
        scheduledService.scheduledCalendarEntries(for: kind, month: month, relativeTo: referenceDate)
    }

    func nextOccurrenceDate(
        for template: CashflowTransaction,
        relativeTo referenceDate: Date? = nil
    ) -> Date? {
        scheduledService.nextOccurrenceDate(for: template, relativeTo: referenceDate)
    }

    private func monthlyTotal(
        for type: CashflowTransactionType,
        month: Date,
        in currency: String? = nil
    ) async -> Double {
        await analyticsService.monthlyTotal(for: type, month: month, displayCurrency: currency ?? state.displayCurrency)
    }

    private func monthlyTransactions(for type: CashflowTransactionType, month: Date) -> [CashflowTransaction] {
        analyticsService.monthlyTransactions(for: type, month: month)
    }

    // MARK: - Persistence: thin wrappers → CashflowPersistenceService

    @discardableResult
    func persistTransaction(
        _ transaction: CashflowTransaction,
        replacing existingTransaction: CashflowTransaction? = nil,
        dismissEditorOnSuccess: Bool = true
    ) async -> Bool {
        await persistenceService.persistTransaction(
            transaction,
            replacing: existingTransaction,
            dismissEditorOnSuccess: dismissEditorOnSuccess
        )
    }

    func isAmountAvailable(
        amount: Double,
        currency: String,
        fromCardID: String,
        on date: Date,
        replacing existingTransaction: CashflowTransaction? = nil
    ) async throws -> Bool {
        try await persistenceService.isAmountAvailable(
            amount: amount,
            currency: currency,
            fromCardID: fromCardID,
            on: date,
            replacing: existingTransaction
        )
    }

    // MARK: - Currency helpers (thin wrappers → CashflowCurrencyService)

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    static func endOfDay(for date: Date, calendar: Calendar) -> Date {
        let startOfDay = calendar.startOfDay(for: date)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return date
        }
        return nextDay.addingTimeInterval(-0.001)
    }

    private func convertAmount(value: Double, from: String, to: String) async -> Double {
        await currencyService.convertAmount(value: value, from: from, to: to)
    }

    func suggestedTransferExchangeInfo(
        from sourceCurrency: String,
        to targetCurrency: String,
        on date: Date
    ) async -> TransferExchangeSuggestion? {
        await currencyService.suggestedTransferExchangeInfo(
            from: sourceCurrency,
            to: targetCurrency,
            on: date
        )
    }

    private func normalizedCurrencyCode(_ currency: String?) -> String? {
        currencyService.normalizedCurrencyCode(currency)
    }

    func resolveExchangeInfo(for transaction: CashflowTransaction) async -> CashflowExchangeInfo {
        await currencyService.resolveExchangeInfo(for: transaction)
    }

    func convertAmountForTransaction(_ transaction: CashflowTransaction, to currency: String) async -> Double {
        await currencyService.convertAmountForTransaction(transaction, to: currency)
    }

    private func markEstimatedRateWarning(on date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        if let existing = state.currencyConversionWarningDate {
            state.currencyConversionWarningDate = max(existing, day)
        } else {
            state.currencyConversionWarningDate = day
        }

        let warningDate = state.currencyConversionWarningDate ?? day
        state.currencyConversionWarning = Self.estimatedRateWarningText(asOf: warningDate)
    }

    static func estimatedRateWarningText(
        asOf date: Date,
        locale: Locale = AppLocalization.currentAppLocale
    ) -> String {
        CashflowCurrencyService.estimatedRateWarningText(asOf: date, locale: locale)
    }

    // MARK: - Category: System Visibility (thin wrapper)

    @discardableResult
    func setSystemCategoryHidden(
        kind: CashflowCategoryKind,
        categoryRaw: String,
        isHidden: Bool
    ) -> Bool {
        categoryService.setSystemCategoryHidden(kind: kind, categoryRaw: categoryRaw, isHidden: isHidden)
    }

    // MARK: - Category: Static Utils (backward compat)

    private static func customRawValue(from categoryID: String) -> String {
        CashflowCategoryService.customRawValue(from: categoryID)
    }

    private static func customCategoryID(from rawValue: String) -> String? {
        CashflowCategoryService.customCategoryID(from: rawValue)
    }
}
