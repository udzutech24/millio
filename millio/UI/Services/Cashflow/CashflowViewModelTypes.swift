//
//  CashflowViewModelTypes.swift
//  millio
//
//  Типы, вынесенные из CashflowViewModel.swift для уменьшения размера файла.
//  Не изменяй публичные интерфейсы — они используются во всём проекте.
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

    /// Снапшот бюджета расходов для карточки на главном экране Cashflow (Фаза 1 редизайна add-flow).
    /// В отличие от `budgetSnapshot` (привязан к `chartPeriod`, только expense), считается строго
    /// по календарному месяцу через `monthlyBudgetSummary` и `nil`, если выбранный период — не
    /// конкретный месяц (`chartPeriod != .specificMonth`) либо бюджет не настроен.
    var dashboardExpenseBudgetSnapshot: BudgetProgressSnapshot? = nil

    /// Аналогичный снапшот для доходного плана — доходы никогда не считались в `budgetSnapshot`.
    var dashboardIncomeBudgetSnapshot: BudgetProgressSnapshot? = nil

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
