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

// MARK: - Conversion Error

enum CashflowScheduledEntryKind: String {
    case recurringMonthly
    case oneTimePlanned

    var sortPriority: Int {
        switch self {
        case .recurringMonthly:
            return 0
        case .oneTimePlanned:
            return 1
        }
    }
}

struct CashflowScheduledEntry: Identifiable {
    let transaction: CashflowTransaction
    let scheduledDate: Date
    let kind: CashflowScheduledEntryKind

    var id: String {
        let stamp = Int(scheduledDate.timeIntervalSince1970)
        let createdStamp = Int(transaction.createdAt.timeIntervalSince1970)
        return "\(transaction.recurrenceSeriesID ?? "one-time")-\(stamp)-\(kind.rawValue)-\(createdStamp)"
    }
}

enum ConversionError: Error {
    case rateUnavailable(from: String, to: String, date: Date)
}

extension ConversionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .rateUnavailable(let from, let to, let date):
            return "Rate unavailable: \(from) -> \(to) on \(date)"
        }
    }
}

enum CashflowBalanceUpdateError: Error {
    case insufficientFundsToRevert(accountName: String, required: Double, available: Double, currency: String)
}

// Используется также в CashflowPersistenceService (Phase 12)
enum CashflowAffectedAccountEvent: Hashable {
    case cardsUpdated
    case investmentsUpdated
}

extension CashflowBalanceUpdateError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .insufficientFundsToRevert(accountName, required, available, currency):
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.locale = .autoupdatingCurrent
            formatter.maximumFractionDigits = 2

            let requiredText = formatter.string(from: NSNumber(value: required)) ?? "\(required)"
            let availableText = formatter.string(from: NSNumber(value: available)) ?? "\(available)"

            return String(
                localized: "cashflow.history.detail.delete.balance_update_failed.message",
                defaultValue: "Cannot update balances for \"%1$@\". Required: %2$@ %4$@. Available: %3$@ %4$@.",
                comment: "Message shown when deleting a cashflow transaction with balance recalculation would make an account negative"
            )
            .replacingOccurrences(of: "%1$@", with: accountName)
            .replacingOccurrences(of: "%2$@", with: requiredText)
            .replacingOccurrences(of: "%3$@", with: availableText)
            .replacingOccurrences(of: "%4$@", with: currency)
        }
    }
}

// MARK: - Cashflow State

struct CashflowState {
    /// Все транзакции
    var transactions: [CashflowTransaction] = []
    
    /// Отфильтрованные транзакции
    var filteredTransactions: [CashflowTransaction] = []
    
    /// Показывать ли редактор транзакции
    var showTransactionEditor: Bool = false
    
    /// Редактируемая транзакция (nil = новая транзакция)
    var editingTransaction: CashflowTransaction? = nil
    
    /// Тип создаваемой транзакции
    var creatingTransactionType: CashflowTransactionType? = nil
    
    /// Доступные карты
    var availableCards: [Card] = []
    
    /// Все карты (включая архивные) для истории
    var allCards: [Card] = []

    /// Доступные счета из инвестиций для выбора в доходах.
    var availableInvestments: [Investment] = []

    /// Cashflow фильтрует по связям Финансов только cash investments.
    /// Карты идут напрямую из карточного каталога и не должны зависеть от FinanceAccount.
    var linkedInvestmentIDs: Set<String> = []

    /// Пользовательские категории операций
    var customCategories: [CashflowCustomCategory] = []

    /// Переопределения системных категорий (rename/icon/hidden)
    var systemCategoryOverrides: [CashflowSystemCategoryOverride] = []
    
    /// Период для графика
    var chartPeriod: ChartPeriod = .specificMonth
    
    /// Начальная дата для custom периода
    var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    
    /// Конечная дата для custom периода
    var customEndDate: Date = Date()
    
    /// Выбранный месяц для конкретного месяца
    var selectedMonth: Date = Date()
    
    /// Выбранный квартал для конкретного квартала
    var selectedQuarter: Date = Date()
    
    /// Выбранный год для конкретного года
    var selectedYear: Date = Date()
    
    /// Показывать ли селектор периода
    var showPeriodSelector: Bool = false
    
    /// Показывать ли историю операций
    var showTransactionsHistory: Bool = false
    
    /// Валюта для отображения
    var displayCurrency: String = "RUB"
    
    /// Доступные валюты для отображения
    var availableCurrencies: [String] = []
    
    /// Показывать ли sheet выбора валюты
    var showCurrencySelector: Bool = false
    
    /// Сумма доходов за выбранный период
    var totalIncome: Double = 0.0
    
    /// Сумма расходов за выбранный период
    var totalExpense: Double = 0.0

    /// Баланс за выбранный период (доходы - расходы)
    var periodBalance: Double = 0.0

    /// Активы на начало периода (как в Динамике/Финансах)
    var assetsAtPeriodStart: Double = 0.0

    /// Активы на конец периода (как в Динамике/Финансах)
    var assetsAtPeriodEnd: Double = 0.0

    /// Расходы внесенные (абсолютное значение)
    var contributedExpense: Double = 0.0

    /// Изменение стоимости активов по формуле
    var assetValueChange: Double = 0.0

    /// Итого за период (end-start)
    var periodTotalChange: Double = 0.0

    /// Предупреждение о конвертации валют в истории
    var currencyConversionWarning: String? = nil
    /// Дата, на которую опирается оценочный курс в предупреждении.
    var currencyConversionWarningDate: Date? = nil
    /// Признак ручного обновления курсов для CTA в баннере.
    var isRefreshingExchangeRates: Bool = false

    /// Ошибка пересчета остатков при удалении операции.
    var deleteBalanceUpdateErrorMessage: String? = nil

    /// Детализация доходов по категориям за период (по убыванию суммы)
    var incomeBreakdown: [CashflowCategoryBreakdownEntry] = []

    /// Детализация расходов по категориям за период (по убыванию суммы)
    var expenseBreakdown: [CashflowCategoryBreakdownEntry] = []

    /// Точки графика cashflow (по дням за период)
    var chartPoints: [CashflowChartPoint] = []

    /// Конвертированные доходы/расходы по операциям для агрегированного графика
    var convertedTransactions: [CashflowConvertedTransaction] = []

    /// Активный бюджет для текущего периода.
    var activeBudgetPlan: BudgetPlan? = nil

    /// Лимиты категорий активного бюджета.
    var activeBudgetCategoryLimits: [BudgetCategoryLimit] = []

    /// Сводка прогресса бюджета для текущего периода.
    var budgetSnapshot: BudgetProgressSnapshot? = nil
    
    /// Флаг загрузки данных
    var isLoading: Bool = false
}

// MARK: - Cashflow Category Breakdown Entry

struct CashflowCategoryBreakdownEntry: Identifiable {
    let id: String
    let title: String
    let convertedAmount: Double

    init(title: String, convertedAmount: Double) {
        self.id = title
        self.title = title
        self.convertedAmount = convertedAmount
    }
}

// MARK: - Cashflow Chart Point

struct CashflowChartPoint: Identifiable {
    let id: Date
    let date: Date
    let income: Double
    let expense: Double
    let balance: Double
}

struct CashflowCardBalanceSnapshot: Equatable {
    let currency: String
    let availableAmount: Double
    let debtAmount: Double?

    var isCreditCard: Bool {
        debtAmount != nil
    }
}

struct CashflowCategoryDeletionAmountSummary: Identifiable, Hashable {
    let currency: String
    let amount: Double

    var id: String { currency }
}

struct CashflowCategoryDeletionPreview: Identifiable, Hashable {
    let rawValue: String
    let kind: CashflowCategoryKind
    let sourceOption: CashflowCategoryOption
    let suggestedTargetOption: CashflowCategoryOption
    let availableTargetOptions: [CashflowCategoryOption]
    let linkedTransactionCount: Int
    let linkedBudgetLimitCount: Int
    let totalsByCurrency: [CashflowCategoryDeletionAmountSummary]

    var id: String { "\(kind.rawValue)|\(rawValue)" }
}

struct CashflowCustomCategorySnapshot {
    let categoryID: String
    let kind: CashflowCategoryKind
    let name: String
    let normalizedName: String
    let icon: String
    let createdAt: Date
    let updatedAt: Date
}

struct CashflowSystemCategoryOverrideSnapshot {
    let overrideID: String
    let kind: CashflowCategoryKind
    let categoryRaw: String
    let name: String
    let normalizedName: String
    let icon: String
    let isHidden: Bool
    let createdAt: Date
    let updatedAt: Date
}

struct CashflowTransactionCategoryUndoSnapshot {
    let transaction: CashflowTransaction
    let originalRawValue: String
}

struct CashflowBudgetLimitRecordSnapshot {
    let categoryLimitID: String
    let budgetID: String
    let categoryKind: CashflowCategoryKind
    let categoryRawValue: String
    let limitAmount: Double
    let createdAt: Date
    let updatedAt: Date
}

enum CashflowBudgetLimitUndoSnapshot {
    case updated(limit: BudgetCategoryLimit, originalRawValue: String, originalAmount: Double)
    case merged(source: CashflowBudgetLimitRecordSnapshot, target: BudgetCategoryLimit, targetOriginalAmount: Double)
}

struct CashflowCategoryMutationUndoAction: Identifiable {
    let kind: CashflowCategoryKind
    let sourceOption: CashflowCategoryOption
    let targetOption: CashflowCategoryOption
    let isArchive: Bool
    let customCategorySnapshot: CashflowCustomCategorySnapshot?
    let systemOverrideSnapshot: CashflowSystemCategoryOverrideSnapshot?
    let transactionSnapshots: [CashflowTransactionCategoryUndoSnapshot]
    let budgetLimitSnapshots: [CashflowBudgetLimitUndoSnapshot]
    let pinnedRawValuesBefore: Set<String>
    let merchantMappingsBefore: [String: String]?

    var id: String { "\(kind.rawValue)|\(sourceOption.rawValue)|\(targetOption.rawValue)|\(isArchive)" }
}

// MARK: - Chart Period

enum ChartPeriod: String, CaseIterable {
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"
    case specificMonth = "Specific month"
    case specificQuarter = "Specific quarter"
    case specificYear = "Specific year"
    case custom = "Custom period"
    
    var days: Int {
        switch self {
        case .month, .specificMonth: return 30
        case .quarter, .specificQuarter: return 90
        case .year, .specificYear: return 365
        case .custom: return 365 // По умолчанию, будет переопределено
        }
    }
    
    var displayName: String {
        switch self {
        case .month: return CashflowLocalization.periodMonth
        case .quarter: return CashflowLocalization.periodQuarter
        case .year: return CashflowLocalization.periodYear
        case .specificMonth: return CashflowLocalization.periodMonth
        case .specificQuarter: return CashflowLocalization.periodQuarter
        case .specificYear: return CashflowLocalization.periodYear
        case .custom: return CashflowLocalization.periodCustom
        }
    }
}

// MARK: - History Query

enum CashflowHistoryTypeFilter: CaseIterable {
    case all
    case income
    case expense
    case transfer
    case assetBalanceChange
    case accountBalanceCorrection

    var title: String {
        switch self {
        case .all:
            return AppLocalization.string("cashflow.history.filter.all", locale: AppLocalization.currentAppLocale)
        case .income:
            return AppLocalization.string("cashflow.history.filter.income", locale: AppLocalization.currentAppLocale)
        case .expense:
            return AppLocalization.string("cashflow.history.filter.expense", locale: AppLocalization.currentAppLocale)
        case .transfer:
            return AppLocalization.string("cashflow.history.filter.transfer", locale: AppLocalization.currentAppLocale)
        case .assetBalanceChange:
            return AppLocalization.string("cashflow.history.filter.asset_change", locale: AppLocalization.currentAppLocale)
        case .accountBalanceCorrection:
            return AppLocalization.string("cashflow.history.filter.account_correction", locale: AppLocalization.currentAppLocale)
        }
    }

    func matches(_ type: CashflowTransactionType) -> Bool {
        switch self {
        case .all:
            return true
        case .income:
            return type == .income
        case .expense:
            return type == .expense
        case .transfer:
            return type == .transfer
        case .assetBalanceChange:
            return type == .balanceAdjustment
        case .accountBalanceCorrection:
            return type == .cardBalanceAdjustment || type == .creditDebtAdjustment
        }
    }
}

struct CashflowHistoryQuery {
    var typeFilter: CashflowHistoryTypeFilter = .all
    var searchText: String = ""
    var startDate: Date?
    var endDate: Date?
    var cardID: String? = nil
    var categoryRawValue: String? = nil
}

// MARK: - Cashflow Actions

enum CashflowAction {
    case loadTransactions
    case addTransaction(CashflowTransactionType)
    case editTransaction(CashflowTransaction)
    case deleteTransaction(CashflowTransaction, recalculate: Bool)
    case updateTransaction(CashflowTransaction)
    case hideTransactionEditor
    case setChartPeriod(ChartPeriod)
    case resetToDefaultPeriod
    case setCustomPeriod(start: Date, end: Date)
    case setSelectedMonth(Date)
    case setSelectedQuarter(Date)
    case setSelectedYear(Date)
    case showPeriodSelector
    case hidePeriodSelector
    case showTransactionsHistory
    case hideTransactionsHistory
    case showCurrencySelector
    case hideCurrencySelector
    case setDisplayCurrency(String)
    case syncDisplayCurrencyWithPrimary(String)
    case syncPrimaryCurrencyChange(old: String, new: String)
    case loadCards
    case refreshExchangeRates
    case dismissCurrencyConversionWarning
    case dismissDeleteBalanceUpdateError
}

// MARK: - Transfer Exchange Suggestion

struct TransferExchangeSuggestion: Equatable {
    let rate: Double
    let rateDate: Date
    let isLiveRate: Bool
}

// MARK: - Cashflow ViewModel

@MainActor
final class CashflowViewModel: ViewModelProtocol {
    typealias State = CashflowState
    typealias Action = CashflowAction
    
    @Published var state = CashflowState()
    
    let modelContext: ModelContext
    private let historicalRateStore: HistoricalRateStore
    private let notificationManager: NotificationManagerProtocol
    private let now: () -> Date
    private let assetsSnapshotProvider: ((Date, Date, String) async -> (start: Double, end: Double)?)?
    private let defaults: UserDefaults
    private let categoryPinPrefs: CashflowCategoryPinPrefs
    private let bulkExpenseMerchantPrefs: CashflowBulkExpenseMerchantCategoryPrefs
    private let budgetAutoRepeatPrefs = BudgetAutoRepeatPrefs()
    
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
    
    private func loadTransactions() {
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
    
    private func loadCards() {
        state.allCards = CardCatalog.fetchAll(in: modelContext)
        state.availableCards = state.allCards.filter { $0.archivedAt == nil }
    }

    private func loadInvestments() {
        let descriptor = FetchDescriptor<Investment>()
        let allInvestments = (try? modelContext.fetch(descriptor)) ?? []
        state.availableInvestments = allInvestments.filter { $0.archivedAt == nil }
    }

    private func loadBudgetPlanForCurrentPeriod() {
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

    private func fetchBudgetCategoryLimits(for budgetID: String) -> [BudgetCategoryLimit] {
        let descriptor = FetchDescriptor<BudgetCategoryLimit>(
            predicate: #Predicate { $0.budgetID == budgetID },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchBudgetPlan(
        matching descriptor: BudgetPeriodDescriptor,
        categoryKind: CashflowCategoryKind
    ) -> BudgetPlan? {
        let budgetFetch = FetchDescriptor<BudgetPlan>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let plans = (try? modelContext.fetch(budgetFetch)) ?? []
        return plans.first(where: { $0.matches(descriptor, categoryKind: categoryKind) })
    }

    private func currentBudgetPeriodDescriptor(calendar: Calendar = .current) -> BudgetPeriodDescriptor {
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

    private func monthlyBudgetPeriodDescriptor(for month: Date, calendar: Calendar = .current) -> BudgetPeriodDescriptor {
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

    private func nextChartUpdateRevision() -> Int {
        analyticsService.nextChartUpdateRevision()
    }

    private func isCurrentChartUpdateRevision(_ revision: Int) -> Bool {
        analyticsService.isCurrentChartUpdateRevision(revision)
    }

    // MARK: - History

    func historyTransactions(matching query: CashflowHistoryQuery) -> [CashflowTransaction] {
        historyService.historyTransactions(
            matching: query,
            in: state.filteredTransactions,
            allCards: state.allCards,
            categoryNameResolver: { [weak self] raw, type in
                guard let self else { return raw ?? "" }
                switch type {
                case .income: return self.incomeCategoryDisplayName(for: raw)
                case .expense: return self.expenseCategoryDisplayName(for: raw)
                default: return raw ?? ""
                }
            }
        )
    }
    
    private func updateChartData() {
        state.currencyConversionWarning = nil
        state.currencyConversionWarningDate = nil
        let revision = nextChartUpdateRevision()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isCurrentChartUpdateRevision(revision) else { return }
            await self.updateChartDataAsync(expectedRevision: revision)
        }
    }
    
    private func updateChartDataAsync(expectedRevision: Int? = nil) async {
        let revision = expectedRevision ?? nextChartUpdateRevision()
        guard isCurrentChartUpdateRevision(revision) else { return }

        loadBudgetPlanForCurrentPeriod()
        let input = CashflowChartInput(
            chartPeriod: state.chartPeriod,
            selectedMonth: state.selectedMonth,
            selectedQuarter: state.selectedQuarter,
            selectedYear: state.selectedYear,
            customStartDate: state.customStartDate,
            customEndDate: state.customEndDate,
            activeBudgetPlan: state.activeBudgetPlan,
            activeBudgetCategoryLimits: state.activeBudgetCategoryLimits,
            displayCurrency: state.displayCurrency
        )
        guard let snapshot = await analyticsService.updateChartDataAsync(input: input, expectedRevision: revision) else { return }
        state.totalIncome = snapshot.totalIncome
        state.totalExpense = snapshot.totalExpense
        state.periodBalance = snapshot.periodBalance
        state.incomeBreakdown = snapshot.incomeBreakdown
        state.expenseBreakdown = snapshot.expenseBreakdown
        state.budgetSnapshot = snapshot.budgetSnapshot
        state.chartPoints = snapshot.chartPoints
        state.convertedTransactions = snapshot.convertedTransactions
        state.assetsAtPeriodStart = snapshot.assetsAtPeriodStart
        state.assetsAtPeriodEnd = snapshot.assetsAtPeriodEnd
        state.contributedExpense = snapshot.contributedExpense
        state.assetValueChange = snapshot.assetValueChange
        state.periodTotalChange = snapshot.periodTotalChange
    }
    
    func currentDateRange() -> (Date, Date) {
        getDateRange()
    }

    func currentPeriodHeaderTitle() -> String {
        Self.makePeriodHeaderTitle(
            chartPeriod: state.chartPeriod,
            selectedMonth: state.selectedMonth,
            selectedQuarter: state.selectedQuarter,
            selectedYear: state.selectedYear,
            customStartDate: state.customStartDate,
            customEndDate: state.customEndDate,
            calendar: .current,
            locale: .autoupdatingCurrent
        )
    }

    static func makePeriodHeaderTitle(
        chartPeriod: ChartPeriod,
        selectedMonth: Date,
        selectedQuarter: Date,
        selectedYear: Date,
        customStartDate: Date,
        customEndDate: Date,
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale

        switch chartPeriod {
        case .custom:
            let start = min(customStartDate, customEndDate)
            let end = max(customStartDate, customEndDate)
            formatter.setLocalizedDateFormatFromTemplate("dMMM y")
            return "\(formatter.string(from: start)) — \(formatter.string(from: end))"

        case .year, .specificYear:
            formatter.setLocalizedDateFormatFromTemplate("y")
            return formatter.string(from: selectedYear)

        case .quarter, .specificQuarter:
            let components = calendar.dateComponents([.year, .month], from: selectedQuarter)
            let month = components.month ?? calendar.component(.month, from: selectedQuarter)
            let year = components.year ?? calendar.component(.year, from: selectedQuarter)
            let quarter = max(1, min(4, (month - 1) / 3 + 1))
            let format = AppLocalization.string("cashflow.period.quarter_title_format", locale: locale)
            return String(format: format, quarter, year)

        case .month, .specificMonth:
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedMonth)) ?? selectedMonth
            formatter.setLocalizedDateFormatFromTemplate("LLLL y")
            return formatter.string(from: monthStart)
        }
    }

    func monthlyIncomeTotal(for month: Date, in currency: String? = nil) async -> Double {
        await analyticsService.monthlyTotal(for: .income, month: month, displayCurrency: currency ?? state.displayCurrency)
    }

    func monthlyExpenseTotal(for month: Date, in currency: String? = nil) async -> Double {
        await analyticsService.monthlyTotal(for: .expense, month: month, displayCurrency: currency ?? state.displayCurrency)
    }

    func incomePlanSummary(
        for month: Date,
        in currency: String? = nil
    ) async -> IncomePlanProgressSnapshot? {
        let calendar = Calendar.current
        let targetCurrency = currency ?? state.displayCurrency
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) ?? monthStart
        let cutoff = min(now(), monthEnd)
        let actualTransactions = analyticsService.monthlyTransactions(for: .income, month: month)
            .filter { transaction in
                transaction.shouldAffectCashflowTotals && transaction.transactionDate <= cutoff
            }
        let plannedEntries = scheduledCalendarEntries(
            for: .income,
            month: month,
            relativeTo: cutoff
        )

        let previousWarning = state.currencyConversionWarning
        let previousWarningDate = state.currencyConversionWarningDate
        defer {
            state.currencyConversionWarning = previousWarning
            state.currencyConversionWarningDate = previousWarningDate
        }

        var actualTotal: Double = 0
        for transaction in actualTransactions {
            actualTotal += await convertAmountForTransaction(transaction, to: targetCurrency)
        }

        var plannedRemainder: Double = 0
        for entry in plannedEntries {
            plannedRemainder += await convertAmountForTransaction(entry.transaction, to: targetCurrency)
        }

        let plannedTotal = actualTotal + plannedRemainder
        guard plannedTotal > 0.0000001 else { return nil }

        return IncomePlanProgressSnapshot(
            actual: actualTotal,
            planned: plannedTotal,
            remaining: max(0, plannedRemainder),
            progress: min(max(actualTotal / plannedTotal, 0), 1)
        )
    }

    func monthlyBudgetSummary(
        for categoryKind: CashflowCategoryKind,
        month: Date,
        in currency: String? = nil
    ) async -> (plan: BudgetPlan?, snapshot: BudgetProgressSnapshot?, categoryLimits: [String: Double]) {
        let descriptor = monthlyBudgetPeriodDescriptor(for: month)
        let targetCurrency = currency ?? state.displayCurrency
        let plan = fetchBudgetPlan(matching: descriptor, categoryKind: categoryKind)
        guard let plan else {
            return (nil, nil, [:])
        }

        let limits = fetchBudgetCategoryLimits(for: plan.budgetID)
            .filter { $0.categoryKind == categoryKind }
        let categoryLimits = Dictionary(uniqueKeysWithValues: limits.map { ($0.categoryRawValue, $0.limitAmount) })
        let totals = await monthlyCategoryTotals(for: categoryKind, month: month, in: targetCurrency)
        let totalAmount = totals.values.reduce(0, +)
        let titleResolver: (String) -> String = { [weak self] raw in
            guard let self else { return raw }
            switch categoryKind {
            case .expense:
                return self.expenseCategoryDisplayName(for: raw)
            case .income:
                return self.incomeCategoryDisplayName(for: raw)
            }
        }
        let snapshot = BudgetProgressCalculator.calculate(
            totalSpent: totalAmount,
            totalLimit: plan.totalLimitAmount,
            categorySpentByRawValue: totals,
            categoryLimits: limits,
            categoryTitleResolver: titleResolver
        )
        return (plan, snapshot, categoryLimits)
    }

    func expenseBudgetSummary(
        for month: Date,
        in currency: String? = nil
    ) async -> (plan: BudgetPlan?, snapshot: BudgetProgressSnapshot?, categoryLimits: [String: Double]) {
        await monthlyBudgetSummary(for: .expense, month: month, in: currency)
    }

    func incomeBudgetSummary(
        for month: Date,
        in currency: String? = nil
    ) async -> (plan: BudgetPlan?, snapshot: BudgetProgressSnapshot?, categoryLimits: [String: Double]) {
        await monthlyBudgetSummary(for: .income, month: month, in: currency)
    }

    var isMonthlyBudgetAutoRepeatEnabled: Bool {
        get { budgetAutoRepeatPrefs.isEnabled }
        set { budgetAutoRepeatPrefs.isEnabled = newValue }
    }

    func previousMonthlyBudgetSuggestion(
        for month: Date,
        categoryKind: CashflowCategoryKind = .expense
    ) -> BudgetRepeatSuggestion? {
        let calendar = Calendar.current
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: month) else { return nil }
        let descriptor = monthlyBudgetPeriodDescriptor(for: previousMonth, calendar: calendar)
        guard let plan = fetchBudgetPlan(matching: descriptor, categoryKind: categoryKind) else { return nil }

        let limits = fetchBudgetCategoryLimits(for: plan.budgetID)
            .filter { $0.categoryKind == categoryKind }
        let categoryLimits = Dictionary(uniqueKeysWithValues: limits.map { ($0.categoryRawValue, $0.limitAmount) })

        return BudgetRepeatSuggestion(
            totalAmount: plan.totalLimitAmount,
            categoryLimits: categoryLimits,
            sourceMonth: descriptor.startDate
        )
    }

    func saveMonthlyBudgetConfiguration(
        categoryKind: CashflowCategoryKind = .expense,
        month: Date,
        totalAmount: Double,
        categoryLimits: [String: Double],
        currency: String? = nil
    ) {
        saveBudgetConfiguration(
            categoryKind: categoryKind,
            descriptor: monthlyBudgetPeriodDescriptor(for: month),
            currencyCode: currency ?? state.displayCurrency,
            totalAmount: totalAmount,
            categoryLimits: categoryLimits
        )
    }

    func saveBudgetConfiguration(totalAmount: Double, categoryLimits: [String: Double]) {
        saveBudgetConfiguration(
            categoryKind: .expense,
            descriptor: currentBudgetPeriodDescriptor(),
            currencyCode: state.displayCurrency,
            totalAmount: totalAmount,
            categoryLimits: categoryLimits
        )
    }

    private func saveBudgetConfiguration(
        categoryKind: CashflowCategoryKind,
        descriptor: BudgetPeriodDescriptor,
        currencyCode: String,
        totalAmount: Double,
        categoryLimits: [String: Double]
    ) {
        let normalizedTotal = max(0, totalAmount)
        let normalizedCategoryLimits = categoryLimits
            .mapValues { max(0, $0) }
            .filter { $0.value > 0.0000001 }

        let existingPlan = fetchBudgetPlan(matching: descriptor, categoryKind: categoryKind)
        let shouldDeleteConfiguration = normalizedTotal <= 0.0000001 && normalizedCategoryLimits.isEmpty

        if shouldDeleteConfiguration {
            if let existingPlan {
                deleteBudgetPlan(existingPlan)
            } else {
                loadBudgetPlanForCurrentPeriod()
                updateChartData()
            }
            return
        }

        let plan = existingPlan ?? BudgetPlan(
            categoryKind: categoryKind,
            descriptor: descriptor,
            currencyCode: currencyCode,
            totalLimitAmount: normalizedTotal,
            isCategoryBudgetingEnabled: !normalizedCategoryLimits.isEmpty
        )
        if existingPlan == nil {
            modelContext.insert(plan)
        }
        plan.apply(
            categoryKind: categoryKind,
            descriptor: descriptor,
            currencyCode: currencyCode,
            totalLimitAmount: normalizedTotal,
            isCategoryBudgetingEnabled: !normalizedCategoryLimits.isEmpty
        )

        let existingLimits = fetchBudgetCategoryLimits(for: plan.budgetID)
        let existingByRaw = Dictionary(uniqueKeysWithValues: existingLimits.map { ($0.categoryRawValue, $0) })

        for limit in existingLimits where normalizedCategoryLimits[limit.categoryRawValue] == nil {
            modelContext.delete(limit)
        }

        for (rawValue, amount) in normalizedCategoryLimits {
            if let existing = existingByRaw[rawValue] {
                existing.limitAmount = amount
                existing.updatedAt = Date()
            } else {
                let limit = BudgetCategoryLimit(
                    budgetID: plan.budgetID,
                    categoryKind: categoryKind,
                    categoryRawValue: rawValue,
                    limitAmount: amount
                )
                modelContext.insert(limit)
            }
        }

        try? modelContext.save()
        loadBudgetPlanForCurrentPeriod()
        updateChartData()
    }

    func deleteBudgetLimit() {
        guard let plan = state.activeBudgetPlan else { return }
        deleteBudgetPlan(plan)
    }

    func deleteMonthlyBudgetLimit(month: Date, categoryKind: CashflowCategoryKind = .expense) {
        let descriptor = monthlyBudgetPeriodDescriptor(for: month)
        guard let plan = fetchBudgetPlan(matching: descriptor, categoryKind: categoryKind) else { return }
        deleteBudgetPlan(plan)
    }

    private func deleteBudgetPlan(_ plan: BudgetPlan) {
        let limits = fetchBudgetCategoryLimits(for: plan.budgetID)
        for limit in limits {
            modelContext.delete(limit)
        }
        modelContext.delete(plan)
        try? modelContext.save()
        state.activeBudgetPlan = nil
        state.activeBudgetCategoryLimits = []
        state.budgetSnapshot = nil
        updateChartData()
    }

    func persistBulkExpenseImport(_ request: CashflowBulkExpensePersistRequest) async throws -> Int {
        guard !request.entries.isEmpty else {
            throw CashflowBulkExpenseImportError.noRowsToSave
        }
        guard let card = state.availableCards.first(where: { $0.cardUniqueID == request.cardID }) else {
            throw CashflowBulkExpenseImportError.cardNotFound
        }

        let sortedEntries = request.entries.sorted { $0.sourceOrderIndex < $1.sourceOrderIndex }
        let existingTransactions = analyticsService.bulkExpenseImportTransactions(
            cardID: request.cardID,
            month: request.month,
            affectsCardBalance: request.shouldAffectCardBalance
        )
        let nowDate = now()
        let transactionDates = CashflowAnalyticsService.bulkExpenseTransactionDates(
            for: request.month,
            count: sortedEntries.count,
            referenceDate: nowDate,
            calendar: Calendar.current
        )

        let existingAffectingTotal = existingTransactions
            .filter(\.affectsCardBalance)
            .reduce(0) { $0 + $1.amount }
        let newAffectingTotal = request.shouldAffectCardBalance
            ? sortedEntries.reduce(0) { $0 + $1.amount }
            : 0
        let availableBalanceBeforeImport = card.balance + existingAffectingTotal

        if newAffectingTotal - availableBalanceBeforeImport > 0.0000001 {
            throw CashflowBulkExpenseImportError.insufficientFunds(
                required: newAffectingTotal,
                available: availableBalanceBeforeImport,
                currency: card.currency
            )
        }

        var existingByReferenceKey: [String: CashflowTransaction] = [:]
        for transaction in existingTransactions {
            guard let categoryRaw = transaction.expenseCategoryRaw else { continue }
            for key in CashflowAnalyticsService.bulkExpenseImportLookupKeys(
                cardID: request.cardID,
                month: request.month,
                categoryRaw: categoryRaw,
                affectsCardBalance: transaction.affectsCardBalance,
                calendar: Calendar.current
            ) {
                existingByReferenceKey[key] = transaction
            }
            if let key = transaction.importReferenceKey {
                existingByReferenceKey[key] = transaction
            }
        }

        var seenReferenceKeys = Set<String>()
        categoryService.ensureSystemCategoriesVisible(
            rawValues: sortedEntries.map(\.expenseCategoryRaw),
            kind: .expense,
            nowDate: nowDate
        )

        for (index, entry) in sortedEntries.enumerated() {
            let referenceKey = CashflowAnalyticsService.bulkExpenseImportReferenceKey(
                cardID: request.cardID,
                month: request.month,
                categoryRaw: entry.expenseCategoryRaw,
                affectsCardBalance: request.shouldAffectCardBalance
            )
            seenReferenceKeys.insert(referenceKey)

            let transaction = existingByReferenceKey[referenceKey] ?? CashflowTransaction(
                transactionType: .expense,
                amount: entry.amount,
                currency: card.currency,
                transactionDate: transactionDates[index],
                cardID: request.cardID,
                expenseCategoryRaw: entry.expenseCategoryRaw,
                note: entry.note,
                importSourceRaw: CashflowBulkExpenseImportTransactionSource.monthlyCategoryRollup.rawValue,
                importReferenceKey: referenceKey,
                affectsCardBalance: request.shouldAffectCardBalance
            )
            transaction.amount = entry.amount
            transaction.currency = card.currency
            transaction.transactionDate = transactionDates[index]
            transaction.cardID = request.cardID
            transaction.expenseCategoryRaw = entry.expenseCategoryRaw
            transaction.note = entry.note
            transaction.importSourceRaw = CashflowBulkExpenseImportTransactionSource.monthlyCategoryRollup.rawValue
            transaction.importReferenceKey = referenceKey
            transaction.affectsCardBalance = request.shouldAffectCardBalance
            transaction.hasAppliedBalanceEffect = request.shouldAffectCardBalance
            transaction.updatedAt = nowDate

            let exchangeInfo = await resolveExchangeInfo(for: transaction)
            transaction.exchangeRate = exchangeInfo.rate
            transaction.exchangeRateDate = exchangeInfo.rateDate
            transaction.exchangeRateCurrency = exchangeInfo.rateCurrency
            if existingByReferenceKey[referenceKey] == nil {
                modelContext.insert(transaction)
            }
        }

        for transaction in existingTransactions where !seenReferenceKeys.contains(transaction.importReferenceKey ?? "") {
            modelContext.delete(transaction)
        }

        let adjustedBalance = max(0, availableBalanceBeforeImport - newAffectingTotal)
        if abs(adjustedBalance - card.balance) > 0.0000001 {
            card.balance = adjustedBalance
            card.updatedAt = Date()
        }

        do {
            try modelContext.save()
            loadCards()
            loadTransactions()
            return sortedEntries.count
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to save bulk expenses: \(error.localizedDescription)")
            throw error
        }
    }

    func bulkExpenseImportStoredEntries(
        cardID: String,
        month: Date,
        affectsCardBalance: Bool
    ) -> [CashflowBulkExpenseStoredCategoryEntry] {
        analyticsService.bulkExpenseImportStoredEntries(cardID: cardID, month: month, affectsCardBalance: affectsCardBalance)
    }

    func bulkExpenseImportBaselineCategoryTotals(
        cardID: String,
        month: Date,
        affectsCardBalance: Bool
    ) -> [String: Double] {
        analyticsService.bulkExpenseImportBaselineCategoryTotals(cardID: cardID, month: month, affectsCardBalance: affectsCardBalance)
    }

    func learnedBulkExpenseCategoryRaw(for merchantTitle: String) -> String? {
        bulkExpenseMerchantPrefs.categoryRaw(for: merchantTitle)
    }

    func rememberBulkExpenseCategory(categoryRaw: String, for merchantTitle: String) {
        bulkExpenseMerchantPrefs.remember(categoryRaw: categoryRaw, for: merchantTitle)
    }

    /// Возвращает суммы по категориям за выбранный месяц для типа операции.
    /// Ключ словаря — `rawValue` категории (`IncomeCategory` / `ExpenseCategory` / `custom:*`).
    func monthlyCategoryTotals(
        for kind: CashflowCategoryKind,
        month: Date,
        in currency: String? = nil
    ) async -> [String: Double] {
        await analyticsService.monthlyCategoryTotals(for: kind, month: month, displayCurrency: currency ?? state.displayCurrency)
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

    // MARK: - Categories

    func categoryOptions(
        for kind: CashflowCategoryKind,
        matching query: String = "",
        includeHiddenSystem: Bool = false
    ) -> [CashflowCategoryOption] {
        categoryService.categoryOptions(for: kind, matching: query, includeHiddenSystem: includeHiddenSystem)
    }

    func orderedCategoryOptions(
        for kind: CashflowCategoryKind,
        matching query: String = "",
        includeHiddenSystem: Bool = false,
        totalsByCategory: [String: Double] = [:]
    ) -> [CashflowCategoryOption] {
        categoryService.orderedCategoryOptions(
            for: kind,
            matching: query,
            includeHiddenSystem: includeHiddenSystem,
            totalsByCategory: totalsByCategory
        )
    }

    func isCategoryPinned(rawValue: String, kind: CashflowCategoryKind) -> Bool {
        categoryService.isCategoryPinned(rawValue: rawValue, kind: kind)
    }

    func setCategoryPinned(rawValue: String, kind: CashflowCategoryKind, isPinned: Bool) {
        categoryService.setCategoryPinned(rawValue: rawValue, kind: kind, isPinned: isPinned)
        objectWillChange.send()
    }

    func setCategoryOrder(_ rawValues: [String], for kind: CashflowCategoryKind) {
        categoryService.categoryOrderPrefs.setOrder(rawValues, for: kind)
        objectWillChange.send()
    }

    func clearCategoryOrder(for kind: CashflowCategoryKind) {
        categoryService.categoryOrderPrefs.clearOrder(for: kind)
        objectWillChange.send()
    }

    func categoryCustomOrder(for kind: CashflowCategoryKind) -> [String]? {
        categoryService.categoryOrderPrefs.customOrder(for: kind)
    }

    static func sortCategoryOptions(
        _ options: [CashflowCategoryOption],
        totalsByCategory: [String: Double],
        pinnedRawValues: Set<String>
    ) -> [CashflowCategoryOption] {
        CashflowCategoryService.sortCategoryOptions(options, totalsByCategory: totalsByCategory, pinnedRawValues: pinnedRawValues)
    }

    func categoryOption(for raw: String, kind: CashflowCategoryKind, fallbackName: String = "") -> CashflowCategoryOption {
        categoryService.categoryOption(for: raw, kind: kind, fallbackName: fallbackName)
    }

    func incomeCategoryDisplayName(for raw: String?) -> String {
        categoryService.incomeCategoryDisplayName(for: raw)
    }

    func expenseCategoryDisplayName(for raw: String?) -> String {
        categoryService.expenseCategoryDisplayName(for: raw)
    }

    func incomeCategoryIcon(for raw: String?) -> String {
        categoryService.incomeCategoryIcon(for: raw)
    }

    func expenseCategoryIcon(for raw: String?) -> String {
        categoryService.expenseCategoryIcon(for: raw)
    }

    func historySummary(
        matching query: CashflowHistoryQuery,
        mode: CashflowHistorySummaryMode
    ) async -> CashflowHistorySummaryModel {
        let targetType: CashflowTransactionType = mode == .expense ? .expense : .income
        let transactions = historyTransactions(matching: query).filter {
            $0.transactionType == targetType && $0.shouldAffectCashflowTotals
        }
        let targetCurrency = state.displayCurrency

        let previousWarning = state.currencyConversionWarning
        let previousWarningDate = state.currencyConversionWarningDate
        defer {
            state.currencyConversionWarning = previousWarning
            state.currencyConversionWarningDate = previousWarningDate
        }

        var totalsByRawValue: [String: Double] = [:]
        for transaction in transactions {
            let rawValue = mode == .expense
                ? (transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue)
                : (transaction.incomeCategoryRaw ?? IncomeCategory.other.rawValue)
            let converted = await convertAmountForTransaction(transaction, to: targetCurrency)
            guard converted.isFinite else { continue }
            totalsByRawValue[rawValue, default: 0] += converted
        }

        let entries = CashflowHistorySummaryBuilder.build(
            totalsByRawValue: totalsByRawValue,
            mode: mode,
            resolver: { [weak self] rawValue in
                guard let self else {
                    return CashflowHistorySummaryResolvedCategory(rawValue: rawValue, title: rawValue, icon: "•")
                }
                switch mode {
                case .expense:
                    return CashflowHistorySummaryResolvedCategory(
                        rawValue: rawValue,
                        title: self.expenseCategoryDisplayName(for: rawValue),
                        icon: self.expenseCategoryIcon(for: rawValue)
                    )
                case .income:
                    return CashflowHistorySummaryResolvedCategory(
                        rawValue: rawValue,
                        title: self.incomeCategoryDisplayName(for: rawValue),
                        icon: self.incomeCategoryIcon(for: rawValue)
                    )
                }
            }
        )

        return CashflowHistorySummaryModel(
            mode: mode,
            totalAmount: entries.reduce(0) { $0 + $1.amount },
            currencyCode: targetCurrency,
            entries: entries
        )
    }

    @discardableResult
    func createCustomCategory(
        kind: CashflowCategoryKind,
        name: String,
        icon: String = CashflowCustomCategory.defaultIcon
    ) -> CashflowCategoryOption? {
        categoryService.createCustomCategory(kind: kind, name: name, icon: icon)
    }

    @discardableResult
    func renameCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        newName: String,
        newIcon: String? = nil
    ) -> Bool {
        categoryService.renameCategory(rawValue: rawValue, kind: kind, newName: newName, newIcon: newIcon)
    }

    @discardableResult
    func deleteCategory(rawValue: String, kind: CashflowCategoryKind) -> Bool {
        categoryService.deleteCategory(rawValue: rawValue, kind: kind)
    }

    @discardableResult
    func deleteCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        targetRawValue: String?
    ) -> Bool {
        categoryService.deleteCategory(rawValue: rawValue, kind: kind, targetRawValue: targetRawValue)
    }

    func performCategoryRemoval(
        rawValue: String,
        kind: CashflowCategoryKind,
        targetRawValue: String?
    ) -> CashflowCategoryMutationUndoAction? {
        categoryService.performCategoryRemoval(rawValue: rawValue, kind: kind, targetRawValue: targetRawValue)
    }

    @discardableResult
    func undoCategoryMutation(_ action: CashflowCategoryMutationUndoAction) -> Bool {
        categoryService.undoCategoryMutation(action)
    }

    func canDeleteCategory(rawValue: String, kind: CashflowCategoryKind) -> Bool {
        categoryService.canDeleteCategory(rawValue: rawValue, kind: kind)
    }

    @discardableResult
    func renameCustomCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        newName: String,
        newIcon: String? = nil
    ) -> Bool {
        categoryService.renameCustomCategory(rawValue: rawValue, kind: kind, newName: newName, newIcon: newIcon)
    }

    @discardableResult
    func deleteCustomCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        targetRawValue: String? = nil
    ) -> CashflowCategoryMutationUndoAction? {
        categoryService.deleteCustomCategory(rawValue: rawValue, kind: kind, targetRawValue: targetRawValue)
    }

    func categoryDeletionPreview(
        rawValue: String,
        kind: CashflowCategoryKind
    ) -> CashflowCategoryDeletionPreview? {
        // categoryDeletionPreview в сервисе не имеет state.displayCurrency — передадим через другой метод
        guard categoryService.canDeleteCategory(rawValue: rawValue, kind: kind) else {
            return nil
        }

        let sourceOption = categoryService.categoryOption(for: rawValue, kind: kind)
        let availableTargetOptions = categoryService.categoryOptions(
            for: kind,
            includeHiddenSystem: true
        ).filter { $0.rawValue != sourceOption.rawValue }

        let fallbackRaw: String
        switch kind {
        case .income: fallbackRaw = IncomeCategory.other.rawValue
        case .expense: fallbackRaw = ExpenseCategory.other.rawValue
        }

        guard let suggestedTargetOption = availableTargetOptions.first(where: {
            $0.rawValue == fallbackRaw
        }) ?? availableTargetOptions.first else {
            return nil
        }

        let descriptor = FetchDescriptor<CashflowTransaction>()
        let linked = ((try? modelContext.fetch(descriptor)) ?? []).filter {
            switch kind {
            case .income: return $0.incomeCategoryRaw == rawValue
            case .expense: return $0.expenseCategoryRaw == rawValue
            }
        }
        let budgetDescriptor = FetchDescriptor<BudgetCategoryLimit>()
        let linkedBudgetLimits = ((try? modelContext.fetch(budgetDescriptor)) ?? []).filter {
            $0.categoryKind == kind && $0.categoryRawValue == rawValue
        }
        let totalsByCurrency = Dictionary(grouping: linked, by: \.currency)
            .map { currency, transactions in
                CashflowCategoryDeletionAmountSummary(
                    currency: currency,
                    amount: transactions.reduce(0) { $0 + $1.amount }
                )
            }
            .sorted {
                let lhsIsPrimary = $0.currency == state.displayCurrency
                let rhsIsPrimary = $1.currency == state.displayCurrency
                if lhsIsPrimary != rhsIsPrimary {
                    return lhsIsPrimary && !rhsIsPrimary
                }
                return $0.currency.localizedCaseInsensitiveCompare($1.currency) == .orderedAscending
            }

        return CashflowCategoryDeletionPreview(
            rawValue: rawValue,
            kind: kind,
            sourceOption: sourceOption,
            suggestedTargetOption: suggestedTargetOption,
            availableTargetOptions: availableTargetOptions,
            linkedTransactionCount: linked.count,
            linkedBudgetLimitCount: linkedBudgetLimits.count,
            totalsByCurrency: totalsByCurrency
        )
    }

    private func getDateRange() -> (Date, Date) {
        let input = CashflowChartInput(
            chartPeriod: state.chartPeriod,
            selectedMonth: state.selectedMonth,
            selectedQuarter: state.selectedQuarter,
            selectedYear: state.selectedYear,
            customStartDate: state.customStartDate,
            customEndDate: state.customEndDate,
            activeBudgetPlan: state.activeBudgetPlan,
            activeBudgetCategoryLimits: state.activeBudgetCategoryLimits,
            displayCurrency: state.displayCurrency
        )
        return analyticsService.getDateRange(input: input)
    }

    /// Дефолтный период Cashflow: текущий календарный месяц до сегодняшнего дня.
    ///
    /// Пример: для 09.03.2026 вернет 01.03.2026—09.03.2026.
    nonisolated static func defaultPeriodRange(
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let end = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: end)) ?? end
        return (calendar.startOfDay(for: start), end)
    }

    /// Полный календарный месяц для истории категории.
    /// Не обрезаем конец "сегодня", иначе monthly total и history смотрят на разные диапазоны.
    nonisolated static func monthHistoryRange(
        for month: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        return (calendar.startOfDay(for: start), calendar.startOfDay(for: monthEnd))
    }

    /// Нормализует и ограничивает пользовательский диапазон дат:
    /// - `start <= end`
    /// - обе даты приведены к `startOfDay`
    /// - `end` не выходит за `referenceDate` (обычно "сегодня")
    nonisolated static func clampCustomPeriodRange(
        start: Date,
        end: Date,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        let normalizedStart = min(start, end)
        let normalizedEnd = max(start, end)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let clampedEnd = min(calendar.startOfDay(for: normalizedEnd), referenceDay)
        let clampedStart = min(calendar.startOfDay(for: normalizedStart), clampedEnd)
        return (clampedStart, clampedEnd)
    }

    private func resetToDefaultPeriodInternal(referenceDate: Date) {
        let range = Self.defaultPeriodRange(referenceDate: referenceDate, calendar: .current)
        state.selectedMonth = range.end
        state.customStartDate = range.start
        state.customEndDate = range.end
        state.chartPeriod = .specificMonth
    }

    private func resolveAssetsSnapshotFromFinance(startDate: Date, endDate: Date) async -> (start: Double, end: Double)? {
        do {
            _ = try modelContext.fetch(FetchDescriptor<FinanceGroup>())
        } catch {
            return nil
        }

        let financeViewModel = FinanceViewModel(modelContext: modelContext, skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel
        )
        dynamicsViewModel.state.displayCurrency = state.displayCurrency
        dynamicsViewModel.loadData()

        let accounts = dynamicsViewModel.getAccountsForCalculation()
        let accountCardIDs = Set(accounts.compactMap { $0.accountType == .card ? $0.accountID : nil })
        let calendar = Calendar.current
        let normalizedStartDate = calendar.startOfDay(for: startDate)
        let normalizedEndDate = Self.endOfDay(for: endDate, calendar: calendar)

        let start = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: accounts,
            date: normalizedStartDate,
            accountCardIDs: accountCardIDs,
            debtAsNegative: true,
            includeInitialBeforeCreation: false
        )
        let end = await dynamicsViewModel.calculateBalanceAtDate(
            accounts: accounts,
            date: normalizedEndDate,
            accountCardIDs: accountCardIDs,
            debtAsNegative: true,
            includeInitialBeforeCreation: false
        )
        return (start, end)
    }

    func cardBalanceSnapshot(for cardID: String) -> CashflowCardBalanceSnapshot? {
        guard let card = card(for: cardID) else { return nil }
        let snapshot = CardSnapshotFactory.make(from: card)
        return CashflowCardBalanceSnapshot(
            currency: snapshot.currency,
            availableAmount: snapshot.availableAmount,
            debtAmount: snapshot.isCreditCard ? snapshot.debtAmount : nil
        )
    }

    private func card(for cardID: String) -> Card? {
        let descriptor = FetchDescriptor<Card>()
        let allCards = CardCatalog.deduped((try? modelContext.fetch(descriptor)) ?? [])
        if let fetched = allCards.first(where: { $0.cardUniqueID == cardID }) {
            return fetched
        }
        return CardCatalog.deduped(state.availableCards).first(where: { $0.cardUniqueID == cardID })
    }

    private func investment(for investmentID: String) -> Investment? {
        if let cached = state.availableInvestments.first(where: { $0.investmentUniqueID == investmentID }) {
            return cached
        }
        let descriptor = FetchDescriptor<Investment>()
        let allInvestments = (try? modelContext.fetch(descriptor)) ?? []
        return allInvestments.first(where: { $0.investmentUniqueID == investmentID })
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

    private static func endOfDay(for date: Date, calendar: Calendar) -> Date {
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

    private func resolveExchangeInfo(for transaction: CashflowTransaction) async -> CashflowExchangeInfo {
        await currencyService.resolveExchangeInfo(for: transaction)
    }

    private func convertAmountForTransaction(_ transaction: CashflowTransaction, to currency: String) async -> Double {
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
