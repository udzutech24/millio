//
//  CashflowHistoryService.swift
//  millio
//
//  Сервис фильтрации и поиска в истории транзакций.
//  Выделен из CashflowViewModel (Phase 1 декомпозиции).
//

import Foundation
import SwiftData

// MARK: - CashflowHistoryService

@MainActor
final class CashflowHistoryService {

    // MARK: - Init

    init(modelContext: ModelContext) {
        // modelContext зарезервирован для будущих SwiftData-запросов
        _ = modelContext
    }

    // MARK: - Public API

    /// Фильтрует список транзакций по критериям запроса.
    ///
    /// - Parameters:
    ///   - query: Параметры фильтрации (тип, текст, диапазон дат, карта, категория).
    ///   - transactions: Все предварительно отфильтрованные транзакции (filteredTransactions из state).
    ///   - allCards: Все карты для построения индекса имён.
    ///   - categoryNameResolver: Замыкание, возвращающее отображаемое имя категории по rawValue и типу транзакции.
    func historyTransactions(
        matching query: CashflowHistoryQuery,
        in transactions: [CashflowTransaction],
        allCards: [Card],
        categoryNameResolver: (String?, CashflowTransactionType) -> String
    ) -> [CashflowTransaction] {
        let normalizedQuery = query.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let cardsByID = Dictionary(
            uniqueKeysWithValues: allCards.map { ($0.cardUniqueID, $0.name.lowercased()) }
        )
        let dateRange = normalizedHistoryDateRange(start: query.startDate, end: query.endDate)
        let normalizedCategoryRawValue = query.categoryRawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let usesCategoryFilter = !(normalizedCategoryRawValue?.isEmpty ?? true)

        return transactions.filter { transaction in
            // Recurring-шаблоны отображаются только в экране «Повторяющиеся», не в истории.
            if transaction.isRecurringTemplate { return false }
            if shouldHideLinkedSettlementTransactionInHistory(transaction, in: transactions) {
                return false
            }
            guard query.typeFilter.matches(transaction.transactionType) else {
                return false
            }
            if (query.typeFilter == .income || query.typeFilter == .expense)
                && !transaction.shouldAffectCashflowTotals {
                return false
            }

            if let cardID = query.cardID,
               !historyTransactionMatchesCardFilter(transaction, cardID: cardID, in: transactions) {
                return false
            }

            if usesCategoryFilter,
               !historyTransactionMatchesCategoryFilter(
                transaction,
                categoryRawValue: normalizedCategoryRawValue,
                typeFilter: query.typeFilter
               ) {
                return false
            }

            if let dateRange {
                let transactionDate = Calendar.current.startOfDay(for: transaction.transactionDate)
                guard transactionDate >= dateRange.start && transactionDate <= dateRange.end else {
                    return false
                }
            }

            guard !normalizedQuery.isEmpty else {
                return true
            }
            return historyTransactionMatchesSearch(
                transaction,
                query: normalizedQuery,
                cardsByID: cardsByID,
                in: transactions,
                categoryNameResolver: categoryNameResolver
            )
        }
    }

    // MARK: - Private Helpers

    private func shouldHideLinkedSettlementTransactionInHistory(
        _ transaction: CashflowTransaction,
        in transactions: [CashflowTransaction]
    ) -> Bool {
        guard let operationGroupID = transaction.operationGroupID,
              !operationGroupID.isEmpty else {
            return false
        }
        guard transaction.transactionType == .expense || transaction.transactionType == .income else {
            return false
        }
        guard transaction.shouldAffectCashflowTotals == false else {
            return false
        }

        return transactions.contains { candidate in
            candidate.operationGroupID == operationGroupID
                && candidate.hasAssetChangeSnapshot
        }
    }

    private func historyTransactionMatchesCardFilter(
        _ transaction: CashflowTransaction,
        cardID: String,
        in transactions: [CashflowTransaction]
    ) -> Bool {
        switch transaction.transactionType {
        case .income, .expense, .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            if transaction.cardID == cardID {
                return true
            }
            return linkedHistoryTransactions(for: transaction, in: transactions).contains { linked in
                linked.cardID == cardID || linked.toCardID == cardID
            }
        case .transfer:
            return transaction.cardID == cardID || transaction.toCardID == cardID
        }
    }

    func normalizedHistoryDateRange(start: Date?, end: Date?) -> (start: Date, end: Date)? {
        let calendar = Calendar.current
        switch (start, end) {
        case let (startDate?, endDate?):
            let normalizedStart = calendar.startOfDay(for: min(startDate, endDate))
            let normalizedEnd = calendar.startOfDay(for: max(startDate, endDate))
            return (start: normalizedStart, end: normalizedEnd)
        case let (startDate?, nil):
            let normalized = calendar.startOfDay(for: startDate)
            return (start: normalized, end: normalized)
        case let (nil, endDate?):
            let normalized = calendar.startOfDay(for: endDate)
            return (start: normalized, end: normalized)
        case (nil, nil):
            return nil
        }
    }

    private func historyTransactionMatchesCategoryFilter(
        _ transaction: CashflowTransaction,
        categoryRawValue: String?,
        typeFilter: CashflowHistoryTypeFilter
    ) -> Bool {
        guard let categoryRawValue, !categoryRawValue.isEmpty else {
            return true
        }

        switch typeFilter {
        case .income:
            return transaction.transactionType == .income
                && (transaction.incomeCategoryRaw ?? IncomeCategory.other.rawValue) == categoryRawValue
        case .expense:
            return transaction.transactionType == .expense
                && (transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue) == categoryRawValue
        case .all:
            switch transaction.transactionType {
            case .income:
                return (transaction.incomeCategoryRaw ?? IncomeCategory.other.rawValue) == categoryRawValue
            case .expense:
                return (transaction.expenseCategoryRaw ?? ExpenseCategory.other.rawValue) == categoryRawValue
            case .transfer, .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
                return false
            }
        case .transfer, .assetBalanceChange, .accountBalanceCorrection:
            return false
        }
    }

    private func historyTransactionMatchesSearch(
        _ transaction: CashflowTransaction,
        query: String,
        cardsByID: [String: String],
        in transactions: [CashflowTransaction],
        categoryNameResolver: (String?, CashflowTransactionType) -> String
    ) -> Bool {
        if let note = transaction.note?.lowercased(), note.contains(query) {
            return true
        }

        let incomeCategory = categoryNameResolver(
            transaction.incomeCategoryRaw,
            .income
        ).lowercased()
        if incomeCategory.contains(query) {
            return true
        }
        // Поиск по raw-значению категории (для кроссязычного поиска)
        if let incomeCategoryRaw = transaction.incomeCategoryRaw?.lowercased(), incomeCategoryRaw.contains(query) {
            return true
        }

        let expenseCategory = categoryNameResolver(
            transaction.expenseCategoryRaw,
            .expense
        ).lowercased()
        if expenseCategory.contains(query) {
            return true
        }
        // Поиск по raw-значению категории (для кроссязычного поиска)
        if let expenseCategoryRaw = transaction.expenseCategoryRaw?.lowercased(), expenseCategoryRaw.contains(query) {
            return true
        }

        if transaction.transactionType.displayName.lowercased().contains(query) {
            return true
        }

        let amountWithoutFraction = String(format: "%.0f", transaction.amount)
        if amountWithoutFraction.contains(query) {
            return true
        }

        let fromCardName = cardsByID[transaction.cardID ?? ""]
        if let fromCardName, fromCardName.contains(query) {
            return true
        }

        let toCardName = cardsByID[transaction.toCardID ?? ""]
        if let toCardName, toCardName.contains(query) {
            return true
        }

        let linkedTransactions = linkedHistoryTransactions(for: transaction, in: transactions)
        for linked in linkedTransactions {
            let linkedFromCardName = cardsByID[linked.cardID ?? ""]
            if let linkedFromCardName, linkedFromCardName.contains(query) {
                return true
            }

            let linkedToCardName = cardsByID[linked.toCardID ?? ""]
            if let linkedToCardName, linkedToCardName.contains(query) {
                return true
            }
        }

        return false
    }

    private func linkedHistoryTransactions(
        for transaction: CashflowTransaction,
        in transactions: [CashflowTransaction]
    ) -> [CashflowTransaction] {
        guard let operationGroupID = transaction.operationGroupID,
              !operationGroupID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return transactions.filter {
            $0.persistentModelID != transaction.persistentModelID
                && $0.operationGroupID == operationGroupID
        }
    }
}
