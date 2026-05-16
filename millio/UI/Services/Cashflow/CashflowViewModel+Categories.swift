//
//  CashflowViewModel+Categories.swift
//  millio
//
//  Extension: Categories — управление категориями, периоды, ассеты, карты.
//  Вынесено из CashflowViewModel.swift для уменьшения размера основного файла.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

extension CashflowViewModel {

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
        includeHiddenSystem: Bool = false
    ) -> [CashflowCategoryOption] {
        categoryService.orderedCategoryOptions(
            for: kind,
            matching: query,
            includeHiddenSystem: includeHiddenSystem
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
        pinnedRawValues: Set<String>
    ) -> [CashflowCategoryOption] {
        CashflowCategoryService.sortCategoryOptions(options, pinnedRawValues: pinnedRawValues)
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

    func getDateRange() -> (Date, Date) {
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

    func resetToDefaultPeriodInternal(referenceDate: Date) {
        let range = Self.defaultPeriodRange(referenceDate: referenceDate, calendar: .current)
        state.selectedMonth = range.end
        state.customStartDate = range.start
        state.customEndDate = range.end
        state.chartPeriod = .specificMonth
    }

    func resolveAssetsSnapshotFromFinance(startDate: Date, endDate: Date) async -> (start: Double, end: Double)? {
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

    func card(for cardID: String) -> Card? {
        let descriptor = FetchDescriptor<Card>()
        let allCards = CardCatalog.deduped((try? modelContext.fetch(descriptor)) ?? [])
        if let fetched = allCards.first(where: { $0.cardUniqueID == cardID }) {
            return fetched
        }
        return CardCatalog.deduped(state.availableCards).first(where: { $0.cardUniqueID == cardID })
    }

    func investment(for investmentID: String) -> Investment? {
        if let cached = state.availableInvestments.first(where: { $0.investmentUniqueID == investmentID }) {
            return cached
        }
        let descriptor = FetchDescriptor<Investment>()
        let allInvestments = (try? modelContext.fetch(descriptor)) ?? []
        return allInvestments.first(where: { $0.investmentUniqueID == investmentID })
    }

}
