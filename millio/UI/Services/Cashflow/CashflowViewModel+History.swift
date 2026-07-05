//
//  CashflowViewModel+History.swift
//  millio
//
//  Extension: History — аналитика, графики, бюджеты, bulk-import.
//  Вынесено из CashflowViewModel.swift для уменьшения размера основного файла.
//

import Foundation
import SwiftData
import SwiftUI

extension CashflowViewModel {

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

    func updateChartData() {
        state.currencyConversionWarning = nil
        state.currencyConversionWarningDate = nil
        let revision = nextChartUpdateRevision()
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isCurrentChartUpdateRevision(revision) else { return }
            await self.updateChartDataAsync(expectedRevision: revision)
        }
    }

    func updateChartDataAsync(expectedRevision: Int? = nil) async {
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

        let limits = BudgetCategoryLimit.dedupedByCategoryRawValue(
            fetchBudgetCategoryLimits(for: plan.budgetID).filter { $0.categoryKind == categoryKind }
        )
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

        let limits = BudgetCategoryLimit.dedupedByCategoryRawValue(
            fetchBudgetCategoryLimits(for: plan.budgetID).filter { $0.categoryKind == categoryKind }
        )
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

    func saveBudgetConfiguration(
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

        let existingLimits = BudgetCategoryLimit.dedupedByCategoryRawValue(fetchBudgetCategoryLimits(for: plan.budgetID))
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

    func deleteBudgetPlan(_ plan: BudgetPlan) {
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

}
