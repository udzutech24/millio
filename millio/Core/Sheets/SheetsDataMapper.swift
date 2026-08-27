import Foundation

// MARK: - Маппер SwiftData → MillioExportData

/// Преобразует загруженные SwiftData-объекты в плоские строки для отправки на backend.
/// Источник счетов — новое ядро `Account` (event-sourcing): у счёта нет хранимого баланса,
/// он выводится `AccountBalanceEngine.balanceAt` из событий. Легаси `Card`/`Investment` больше
/// не читаются (6b Ф5c.1a). Маппер не делает SwiftData-fetch — принимает готовые массивы, но
/// читает to-many `account.events` для реплея баланса/позиции (вызывать с актора контекста).
enum SheetsDataMapper {

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Публичный интерфейс

    static func buildExportData(
        transactions: [CashflowTransaction],
        accounts: [Account],
        budgets: [BudgetPlan]
    ) -> MillioExportData {
        // Индекс счетов по UUID-строке — для резолвинга имени/типа в транзакциях.
        // Ключ совпадает с `CashflowTransaction.cardID` денежных операций после ремапа миграции
        // (`LegacyAccountsMigrator.remapCashflowHistory`: легаси-uniqueID → core UUID-строка).
        let accountsByID: [String: Account] = Dictionary(
            accounts.map { ($0.id.uuidString, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Рыночные счёта уходят в лист Investments, остальные — в Accounts/Accounts_Archive
        // (тот же раздел «счета vs инвестиции», что давал легаси-сплит Card vs Investment).
        let marketAccounts = accounts.filter { $0.kind == .marketInvestment }
        let nonMarket = accounts.filter { $0.kind != .marketInvestment }
        let activeAccounts = nonMarket.filter { $0.archivedAt == nil }
        let archivedAccounts = nonMarket.filter { $0.archivedAt != nil }

        return MillioExportData(
            transactions: transactions.map { mapTransaction($0, accountsByID: accountsByID) },
            accounts: activeAccounts.map(mapAccount),
            archivedAccounts: archivedAccounts.compactMap(mapArchivedAccount),
            budgets: budgets.map(mapBudget),
            investments: marketAccounts.map(mapInvestment)
        )
    }

    // MARK: - Маппинг транзакций

    private static func mapTransaction(
        _ tx: CashflowTransaction,
        accountsByID: [String: Account]
    ) -> TransactionRow {
        let account = tx.cardID.flatMap { accountsByID[$0] }
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

        return TransactionRow(
            date: iso8601.string(from: tx.transactionDate),
            amount: abs(tx.amount),
            type: tx.transactionTypeRaw,
            category: category,
            account: account?.name,
            account_type: account?.kind.rawValue,
            note: tx.note,
            currency: tx.currency,
            is_transfer: tx.transactionType == .transfer,
            millio_id: tx.transactionUniqueID,
            updated_at: iso8601.string(from: tx.updatedAt)
        )
    }

    // MARK: - Маппинг счетов

    private static func mapAccount(_ account: Account) -> AccountRow {
        AccountRow(
            name: account.name,
            balance: balanceDouble(account, on: Date()),
            type: account.kind.rawValue,
            currency: account.currency,
            millio_id: account.id.uuidString
        )
    }

    private static func mapArchivedAccount(_ account: Account) -> AccountArchiveRow? {
        guard let archivedAt = account.archivedAt else { return nil }
        return AccountArchiveRow(
            name: account.name,
            // Финальный баланс = баланс на момент архивации (легаси хранил его в card.balance).
            final_balance: balanceDouble(account, on: archivedAt),
            archived_at: iso8601.string(from: archivedAt),
            millio_id: account.id.uuidString
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

    // MARK: - Маппинг инвестиций (рыночные счёта ядра)

    private static func mapInvestment(_ account: Account) -> InvestmentRow {
        let position = marketPosition(account)
        return InvestmentRow(
            name: account.name,
            ticker: account.marketMeta?.symbol,
            quantity: double(position.quantity),
            avg_price: position.avgPrice.map(double),
            buy_currency: account.currency,
            total_cost: double(position.totalCost),
            millio_id: account.id.uuidString
        )
    }

    /// Остаточная позиция рыночного счёта по методу скользящего среднего cost basis —
    /// точная реплика легаси `Investment.applyBuy`/`applySell` (продажа списывает стоимость
    /// пропорционально среднему, не FIFO), только источник теперь события ядра, а не хранимые поля.
    private static func marketPosition(_ account: Account) -> (quantity: Decimal, avgPrice: Decimal?, totalCost: Decimal) {
        let events = (account.events ?? []).sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var quantity: Decimal = 0
        var cost: Decimal = 0
        for event in events {
            switch event.type {
            case .buy:
                let q = event.quantity ?? 0
                quantity += q
                cost += q * (event.unitPrice ?? 0)
            case .sell:
                guard quantity > 0 else { continue }
                let q = event.quantity ?? 0
                let avg = cost / quantity
                quantity -= q
                if quantity <= 0 {
                    quantity = 0
                    cost = 0
                } else {
                    cost = max(0, cost - avg * q)
                }
            default:
                continue
            }
        }

        let avgPrice = quantity > 0 ? cost / quantity : nil
        return (quantity, avgPrice, cost)
    }

    // MARK: - Утилиты

    /// Баланс счёта на дату через движок ядра. Прайс-провайдер не передаём: рыночные счёта
    /// в Accounts-лист не попадают, а для остальных движков цена не нужна.
    private static func balanceDouble(_ account: Account, on date: Date) -> Double {
        // Ф1: экспорт отдаёт ту же подтверждённую цифру, что видит пользователь в приложении.
        let balance = AccountBalanceEngine.balanceAt(
            events: DepositConfirmedBalanceResolver.confirmedEvents(
                account.events ?? [], accountID: account.id, kind: account.kind
            ),
            kind: account.kind,
            on: date
        )
        return double(balance)
    }

    private static func double(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}
