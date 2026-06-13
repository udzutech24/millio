import Foundation

// MARK: - Маппер SwiftData → MillioExportData

/// Преобразует загруженные SwiftData-объекты в плоские строки для отправки на backend.
/// Не обращается к SwiftData напрямую — принимает готовые массивы для тестируемости.
enum SheetsDataMapper {

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Публичный интерфейс

    static func buildExportData(
        transactions: [CashflowTransaction],
        cards: [Card],
        budgets: [BudgetPlan],
        investments: [Investment]
    ) -> MillioExportData {
        // Индекс карт по uniqueID — для резолвинга account name в транзакциях
        let cardsByID: [String: Card] = Dictionary(
            uniqueKeysWithValues: cards.map { ($0.uniqueID, $0) }
        )

        let activeCards = cards.filter { $0.archivedAt == nil }
        let archivedCards = cards.filter { $0.archivedAt != nil }

        return MillioExportData(
            transactions: transactions.map { mapTransaction($0, cardsByID: cardsByID) },
            accounts: activeCards.map(mapAccount),
            archivedAccounts: archivedCards.compactMap(mapArchivedAccount),
            budgets: budgets.map(mapBudget),
            investments: investments.map(mapInvestment)
        )
    }

    // MARK: - Маппинг транзакций

    private static func mapTransaction(
        _ tx: CashflowTransaction,
        cardsByID: [String: Card]
    ) -> TransactionRow {
        let accountName = tx.cardID.flatMap { cardsByID[$0]?.name }
        let category: String?
        switch tx.transactionType {
        case .income:
            category = tx.incomeCategoryRaw
        case .expense:
            category = tx.expenseCategoryRaw
        case .transfer, .balanceAdjustment, .cardBalanceAdjustment, .creditDebtAdjustment:
            // Служебные типы — категория не применима
            category = nil
        }

        let accountType = tx.cardID.flatMap { cardsByID[$0]?.cardTypeRaw }

        return TransactionRow(
            date: iso8601.string(from: tx.transactionDate),
            amount: abs(tx.amount),
            type: tx.transactionTypeRaw,
            category: category,
            account: accountName,
            account_type: accountType,
            note: tx.note,
            currency: tx.currency,
            is_transfer: tx.transactionType == .transfer,
            millio_id: tx.transactionUniqueID,
            updated_at: iso8601.string(from: tx.updatedAt)
        )
    }

    // MARK: - Маппинг счетов

    private static func mapAccount(_ card: Card) -> AccountRow {
        AccountRow(
            name: card.name,
            balance: card.balance,
            type: card.cardTypeRaw,
            currency: card.currency,
            millio_id: card.uniqueID
        )
    }

    private static func mapArchivedAccount(_ card: Card) -> AccountArchiveRow? {
        guard let archivedAt = card.archivedAt else { return nil }
        return AccountArchiveRow(
            name: card.name,
            final_balance: card.balance,
            archived_at: iso8601.string(from: archivedAt),
            millio_id: card.uniqueID
        )
    }

    // MARK: - Маппинг бюджетов

    private static func mapBudget(_ budget: BudgetPlan) -> BudgetRow {
        BudgetRow(
            category: budget.categoryKindRaw,
            period_type: budget.periodTypeRaw,
            limit_amount: budget.totalLimitAmount,
            currency: budget.currencyCode,
            millio_id: budget.budgetID
        )
    }

    // MARK: - Маппинг инвестиций

    private static func mapInvestment(_ inv: Investment) -> InvestmentRow {
        InvestmentRow(
            name: inv.name,
            ticker: inv.marketSymbol,
            quantity: inv.marketQuantity,
            avg_price: inv.averagePurchaseUnitPrice,
            buy_currency: inv.currency,
            total_cost: inv.totalPurchaseCost,
            millio_id: inv.uniqueID
        )
    }
}
