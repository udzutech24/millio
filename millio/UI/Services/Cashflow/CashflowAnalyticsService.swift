//
//  CashflowAnalyticsService.swift
//  millio
//
//  Создан в рамках Phase 9 декомпозиции CashflowViewModel.
//  Отвечает за вычисление графиков, аналитики категорий, bulk-expense helpers.
//

import Foundation
import SwiftData

// MARK: - CashflowChartInput

/// Снапшот состояния ViewModel, необходимый для вычисления чарта.
struct CashflowChartInput {
    let chartPeriod: ChartPeriod
    let selectedMonth: Date
    let selectedQuarter: Date
    let selectedYear: Date
    let customStartDate: Date
    let customEndDate: Date
    let activeBudgetPlan: BudgetPlan?
    let activeBudgetCategoryLimits: [BudgetCategoryLimit]
    let displayCurrency: String
}

// MARK: - CashflowChartSnapshot

/// Результат вычисления чарта — применяется VM к state.
struct CashflowChartSnapshot {
    let totalIncome: Double
    let totalExpense: Double
    let periodBalance: Double
    let incomeBreakdown: [CashflowCategoryBreakdownEntry]
    let expenseBreakdown: [CashflowCategoryBreakdownEntry]
    let budgetSnapshot: BudgetProgressSnapshot?
    let chartPoints: [CashflowChartPoint]
    let convertedTransactions: [CashflowConvertedTransaction]
    // Assets
    let assetsAtPeriodStart: Double
    let assetsAtPeriodEnd: Double
    let contributedExpense: Double
    let assetValueChange: Double
    let periodTotalChange: Double
}

// MARK: - CashflowAnalyticsService

@MainActor
final class CashflowAnalyticsService {

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let now: () -> Date

    /// Провайдер текущего снапшота транзакций
    private let transactionsProvider: () -> [CashflowTransaction]
    /// Конвертация суммы транзакции в целевую валюту
    private let convertAmountForTransaction: (CashflowTransaction, String) async -> Double
    /// Резолвер отображаемого имени категории дохода
    private let incomeCategoryDisplayNameResolver: (String?) -> String
    /// Резолвер отображаемого имени категории расхода
    private let expenseCategoryDisplayNameResolver: (String?) -> String
    /// Провайдер снапшота активов из внешней системы (опционально)
    private let assetsSnapshotProvider: ((Date, Date, String) async -> (start: Double, end: Double)?)?
    /// Резолвер снапшота активов из FinanceViewModel (fallback)
    private let resolveAssetsSnapshotFromFinance: (Date, Date) async -> (start: Double, end: Double)?
    /// Перезагрузить BudgetPlan для текущего периода (вызов VM)
    private let onLoadBudgetPlanForCurrentPeriod: () -> Void

    // MARK: - State

    private(set) var chartUpdateRevision: Int = 0

    // MARK: - Init

    init(
        modelContext: ModelContext,
        now: @escaping () -> Date,
        transactionsProvider: @escaping () -> [CashflowTransaction],
        convertAmountForTransaction: @escaping (CashflowTransaction, String) async -> Double,
        incomeCategoryDisplayNameResolver: @escaping (String?) -> String,
        expenseCategoryDisplayNameResolver: @escaping (String?) -> String,
        assetsSnapshotProvider: ((Date, Date, String) async -> (start: Double, end: Double)?)?,
        resolveAssetsSnapshotFromFinance: @escaping (Date, Date) async -> (start: Double, end: Double)?,
        onLoadBudgetPlanForCurrentPeriod: @escaping () -> Void
    ) {
        self.modelContext = modelContext
        self.now = now
        self.transactionsProvider = transactionsProvider
        self.convertAmountForTransaction = convertAmountForTransaction
        self.incomeCategoryDisplayNameResolver = incomeCategoryDisplayNameResolver
        self.expenseCategoryDisplayNameResolver = expenseCategoryDisplayNameResolver
        self.assetsSnapshotProvider = assetsSnapshotProvider
        self.resolveAssetsSnapshotFromFinance = resolveAssetsSnapshotFromFinance
        self.onLoadBudgetPlanForCurrentPeriod = onLoadBudgetPlanForCurrentPeriod
    }

    // MARK: - Revision

    func nextChartUpdateRevision() -> Int {
        chartUpdateRevision += 1
        return chartUpdateRevision
    }

    func isCurrentChartUpdateRevision(_ revision: Int) -> Bool {
        revision == chartUpdateRevision && !Task.isCancelled
    }

    // MARK: - Chart Update

    func updateChartDataAsync(input: CashflowChartInput, expectedRevision: Int? = nil) async -> CashflowChartSnapshot? {
        let revision = expectedRevision ?? nextChartUpdateRevision()
        guard isCurrentChartUpdateRevision(revision) else { return nil }

        onLoadBudgetPlanForCurrentPeriod()
        let (startDate, endDate) = getDateRange(input: input)
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay

        var totalIncome: Double = 0.0
        var totalExpense: Double = 0.0
        var incomeByCategory: [String: Double] = [:]
        var expenseByCategory: [String: Double] = [:]
        var expenseByCategoryRaw: [String: Double] = [:]
        var incomeByDay: [Date: Double] = [:]
        var expenseByDay: [Date: Double] = [:]
        var convertedTransactions: [CashflowConvertedTransaction] = []

        for transaction in transactionsProvider() {
            switch transaction.transactionType {
            case .income:
                guard transaction.shouldAffectCashflowTotals else { continue }
                let converted = await convertAmountForTransaction(transaction, input.displayCurrency)
                convertedTransactions.append(CashflowConvertedTransaction(
                    id: transaction.transactionUniqueID,
                    date: transaction.transactionDate,
                    income: converted,
                    expense: 0
                ))
                if transaction.transactionDate >= startDay && transaction.transactionDate < endExclusive {
                    totalIncome += converted
                    let day = calendar.startOfDay(for: transaction.transactionDate)
                    incomeByDay[day, default: 0.0] += converted
                    let title = incomeCategoryDisplayNameResolver(transaction.incomeCategoryRaw)
                    incomeByCategory[title, default: 0.0] += converted
                }

            case .expense:
                guard transaction.shouldAffectCashflowTotals else { continue }
                let converted = await convertAmountForTransaction(transaction, input.displayCurrency)
                convertedTransactions.append(CashflowConvertedTransaction(
                    id: transaction.transactionUniqueID,
                    date: transaction.transactionDate,
                    income: 0,
                    expense: converted
                ))
                if transaction.transactionDate >= startDay && transaction.transactionDate < endExclusive {
                    totalExpense += converted
                    let day = calendar.startOfDay(for: transaction.transactionDate)
                    expenseByDay[day, default: 0.0] += converted
                    let title = expenseCategoryDisplayNameResolver(transaction.expenseCategoryRaw)
                    expenseByCategory[title, default: 0.0] += converted
                    let raw = transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue
                    expenseByCategoryRaw[raw, default: 0.0] += converted
                }

            case .transfer, .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
                break
            }
        }

        guard isCurrentChartUpdateRevision(revision) else { return nil }

        let budgetSnapshot: BudgetProgressSnapshot? = {
            guard let plan = input.activeBudgetPlan else { return nil }
            return BudgetProgressCalculator.calculate(
                totalSpent: totalExpense,
                totalLimit: plan.totalLimitAmount,
                categorySpentByRawValue: expenseByCategoryRaw,
                categoryLimits: input.activeBudgetCategoryLimits,
                categoryTitleResolver: { [weak self] raw in
                    self?.expenseCategoryDisplayNameResolver(raw) ?? raw
                }
            )
        }()

        var points: [CashflowChartPoint] = []
        var cursor = startDay
        while cursor <= endDay {
            let income = incomeByDay[cursor, default: 0.0]
            let expense = expenseByDay[cursor, default: 0.0]
            points.append(CashflowChartPoint(
                id: cursor,
                date: cursor,
                income: income,
                expense: expense,
                balance: income - expense
            ))
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }

        guard isCurrentChartUpdateRevision(revision) else { return nil }

        let snapshotEndDate = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDay) ?? endDay
        let assetsResult = await updateAssetsBreakdown(
            startDate: startDay,
            endDate: snapshotEndDate,
            displayCurrency: input.displayCurrency,
            totalIncome: totalIncome,
            totalExpense: totalExpense,
            expectedRevision: revision
        )

        guard isCurrentChartUpdateRevision(revision) else { return nil }

        return CashflowChartSnapshot(
            totalIncome: totalIncome,
            totalExpense: totalExpense,
            periodBalance: totalIncome - totalExpense,
            incomeBreakdown: incomeByCategory
                .map { CashflowCategoryBreakdownEntry(title: $0.key, convertedAmount: $0.value) }
                .sorted { $0.convertedAmount > $1.convertedAmount },
            expenseBreakdown: expenseByCategory
                .map { CashflowCategoryBreakdownEntry(title: $0.key, convertedAmount: $0.value) }
                .sorted { $0.convertedAmount > $1.convertedAmount },
            budgetSnapshot: budgetSnapshot,
            chartPoints: points,
            convertedTransactions: convertedTransactions.sorted { $0.date < $1.date },
            assetsAtPeriodStart: assetsResult?.start ?? 0,
            assetsAtPeriodEnd: assetsResult?.end ?? 0,
            contributedExpense: totalExpense,
            assetValueChange: (assetsResult.map { $0.end - $0.start } ?? 0) - totalIncome + totalExpense,
            periodTotalChange: assetsResult.map { $0.end - $0.start } ?? 0
        )
    }

    // MARK: - Analytics Queries

    func monthlyCategoryTotals(
        for kind: CashflowCategoryKind,
        month: Date,
        displayCurrency: String
    ) async -> [String: Double] {
        let targetType: CashflowTransactionType = kind == .income ? .income : .expense
        let filtered = monthlyTransactions(for: targetType, month: month)
            .filter(\.shouldAffectCashflowTotals)
        var totals: [String: Double] = [:]
        for transaction in filtered {
            let categoryRaw: String = {
                switch kind {
                case .income: return transaction.incomeCategoryRaw ?? IncomeCategory.other.rawValue
                case .expense: return transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue
                }
            }()
            let converted = await convertAmountForTransaction(transaction, displayCurrency)
            totals[categoryRaw, default: 0] += converted
        }
        return totals
    }

    func monthlyTotal(
        for type: CashflowTransactionType,
        month: Date,
        displayCurrency: String
    ) async -> Double {
        let filtered = monthlyTransactions(for: type, month: month)
            .filter(\.shouldAffectCashflowTotals)
        var total: Double = 0
        for transaction in filtered {
            total += await convertAmountForTransaction(transaction, displayCurrency)
        }
        return total
    }

    func monthlyTransactions(for type: CashflowTransactionType, month: Date) -> [CashflowTransaction] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) ?? monthStart
        return transactionsProvider().filter { transaction in
            transaction.transactionType == type
            && transaction.transactionDate >= monthStart
            && transaction.transactionDate <= monthEnd
        }
    }

    // MARK: - Date Range

    func getDateRange(input: CashflowChartInput) -> (Date, Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now())

        switch input.chartPeriod {
        case .month:
            let reference = now()
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: reference)) ?? reference
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? reference
            return (startOfMonth, min(endOfMonth, today))

        case .quarter:
            let reference = now()
            let components = calendar.dateComponents([.year, .month], from: reference)
            let month = components.month ?? calendar.component(.month, from: reference)
            let year = components.year ?? calendar.component(.year, from: reference)
            let quarter = (month - 1) / 3
            let startMonth = quarter * 3 + 1
            let startOfQuarter = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? reference
            let endOfQuarter = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: startOfQuarter) ?? reference
            return (startOfQuarter, endOfQuarter)

        case .year:
            let reference = now()
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: reference)) ?? reference
            let endOfYear = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: startOfYear) ?? reference
            return (startOfYear, endOfYear)

        case .specificMonth:
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: input.selectedMonth)) ?? input.selectedMonth
            let endOfMonth = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startOfMonth) ?? input.selectedMonth
            if calendar.isDate(startOfMonth, equalTo: today, toGranularity: .month) {
                return (startOfMonth, today)
            }
            return (startOfMonth, endOfMonth)

        case .specificQuarter:
            let month = calendar.component(.month, from: input.selectedQuarter)
            let quarter = (month - 1) / 3
            let startMonth = quarter * 3 + 1
            let startOfQuarter = calendar.date(from: DateComponents(year: calendar.component(.year, from: input.selectedQuarter), month: startMonth, day: 1)) ?? input.selectedQuarter
            let endOfQuarter = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: startOfQuarter) ?? input.selectedQuarter
            return (startOfQuarter, endOfQuarter)

        case .specificYear:
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: input.selectedYear)) ?? input.selectedYear
            let endOfYear = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: startOfYear) ?? input.selectedYear
            return (startOfYear, endOfYear)

        case .custom:
            let start = min(input.customStartDate, input.customEndDate)
            let end = max(input.customStartDate, input.customEndDate)
            return (calendar.startOfDay(for: start), calendar.startOfDay(for: end))
        }
    }

    // MARK: - Bulk Expense Import Helpers

    func bulkExpenseImportTransactions(
        cardID: String,
        month: Date,
        affectsCardBalance: Bool? = nil
    ) -> [CashflowTransaction] {
        let calendar = Calendar.current
        let monthStart = Self.monthStart(for: month, calendar: calendar)
        let descriptor = FetchDescriptor<CashflowTransaction>()
        let allTransactions = (try? modelContext.fetch(descriptor)) ?? []
        return allTransactions.filter { transaction in
            guard transaction.transactionType == .expense,
                  transaction.cardID == cardID,
                  transaction.importSourceRaw == CashflowBulkExpenseImportTransactionSource.monthlyCategoryRollup.rawValue,
                  Self.isSameMonth(transaction.transactionDate, monthStart, calendar: calendar) else {
                return false
            }
            guard let affectsCardBalance else { return true }
            return transaction.affectsCardBalance == affectsCardBalance
        }
    }

    func bulkExpenseImportStoredEntries(
        cardID: String,
        month: Date,
        affectsCardBalance: Bool
    ) -> [CashflowBulkExpenseStoredCategoryEntry] {
        bulkExpenseImportTransactions(cardID: cardID, month: month, affectsCardBalance: affectsCardBalance)
            .compactMap { transaction in
                guard let categoryRaw = transaction.expenseCategoryRaw else { return nil }
                return CashflowBulkExpenseStoredCategoryEntry(
                    categoryRaw: categoryRaw,
                    amount: transaction.amount,
                    note: transaction.note,
                    affectsCardBalance: transaction.affectsCardBalance
                )
            }
            .sorted { lhs, rhs in
                if lhs.categoryRaw == rhs.categoryRaw { return lhs.amount > rhs.amount }
                return lhs.categoryRaw < rhs.categoryRaw
            }
    }

    func bulkExpenseImportBaselineCategoryTotals(
        cardID: String,
        month: Date,
        affectsCardBalance: Bool
    ) -> [String: Double] {
        monthlyTransactions(for: .expense, month: month)
            .filter { transaction in
                transaction.cardID == cardID
                    && transaction.affectsCardBalance == affectsCardBalance
                    && transaction.shouldAffectCashflowTotals
                    && transaction.importSourceRaw != CashflowBulkExpenseImportTransactionSource.monthlyCategoryRollup.rawValue
            }
            .reduce(into: [String: Double]()) { result, transaction in
                let categoryRaw = transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue
                result[categoryRaw, default: 0] += transaction.amount
            }
    }

    static func bulkExpenseTransactionDates(
        for month: Date,
        count: Int,
        referenceDate: Date,
        calendar: Calendar
    ) -> [Date] {
        guard count > 0 else { return [] }
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) ?? monthStart
        let isCurrentMonth = calendar.isDate(monthStart, equalTo: referenceDate, toGranularity: .month)
        let anchor = isCurrentMonth ? min(referenceDate, monthEnd) : monthEnd
        return (0..<count).map { offset in
            calendar.date(byAdding: .minute, value: -offset, to: anchor) ?? anchor
        }.sorted()
    }

    static func bulkExpenseImportReferenceKey(
        cardID: String,
        month: Date,
        categoryRaw: String,
        affectsCardBalance: Bool,
        calendar: Calendar = .current
    ) -> String {
        let monthStart = Self.monthStart(for: month, calendar: calendar)
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let balanceMode = affectsCardBalance ? "balance-on" : "balance-off"
        return "bulk-expense|\(cardID)|\(year)-\(String(format: "%02d", month))|\(balanceMode)|\(categoryRaw)"
    }

    static func bulkExpenseImportLookupKeys(
        cardID: String,
        month: Date,
        categoryRaw: String,
        affectsCardBalance: Bool,
        calendar: Calendar = .current
    ) -> [String] {
        let monthStart = Self.monthStart(for: month, calendar: calendar)
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        let year = components.year ?? 0
        let monthNum = components.month ?? 0
        let legacyKey = "bulk-expense|\(cardID)|\(year)-\(String(format: "%02d", monthNum))|\(categoryRaw)"
        return [
            bulkExpenseImportReferenceKey(
                cardID: cardID,
                month: monthStart,
                categoryRaw: categoryRaw,
                affectsCardBalance: affectsCardBalance,
                calendar: calendar
            ),
            legacyKey
        ]
    }

    // MARK: - Private: Assets

    private func updateAssetsBreakdown(
        startDate: Date,
        endDate: Date,
        displayCurrency: String,
        totalIncome: Double,
        totalExpense: Double,
        expectedRevision: Int? = nil
    ) async -> (start: Double, end: Double)? {
        let revision = expectedRevision ?? chartUpdateRevision
        guard isCurrentChartUpdateRevision(revision) else { return nil }

        let snapshot: (start: Double, end: Double)?
        if let assetsSnapshotProvider {
            snapshot = await assetsSnapshotProvider(startDate, endDate, displayCurrency)
        } else {
            snapshot = await resolveAssetsSnapshotFromFinance(startDate, endDate)
        }
        guard isCurrentChartUpdateRevision(revision) else { return nil }
        return snapshot
    }

    // MARK: - Private: Helpers

    private static func monthStart(for date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func isSameMonth(_ lhs: Date, _ rhs: Date, calendar: Calendar) -> Bool {
        let left = calendar.dateComponents([.year, .month], from: lhs)
        let right = calendar.dateComponents([.year, .month], from: rhs)
        return left.year == right.year && left.month == right.month
    }
}
