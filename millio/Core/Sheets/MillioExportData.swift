import Foundation

// MARK: - Контейнер экспорта

/// Полный снимок данных Millio, отправляемый на backend при fullSync.
/// Backend записывает всё в Google Sheets как отдельные листы.
struct MillioExportData: Encodable, Sendable {
    let transactions: [TransactionRow]
    let accounts: [AccountRow]
    let archivedAccounts: [AccountArchiveRow]
    let budgets: [BudgetRow]
    let investments: [InvestmentRow]

    enum CodingKeys: String, CodingKey {
        case transactions
        case accounts
        case archivedAccounts = "accounts_archive"
        case budgets
        case investments
    }
}

// MARK: - Строки листов

/// Строка листа "Transactions"
struct TransactionRow: Encodable, Sendable {
    /// Дата транзакции в формате ISO8601
    let date: String
    /// Сумма (всегда положительная)
    let amount: Double
    /// "expense" / "income" / "transfer" / "balance_adjustment" / ...
    let type: String
    let category: String?
    /// Название счёта (карты-источника)
    let account: String?
    /// Тип счёта ("debit" / "credit" / "savings" / ...)
    let account_type: String?
    let note: String?
    let currency: String
    /// true для транзакций типа transfer
    let is_transfer: Bool
    /// Стабильный ID для идемпотентного обновления
    let millio_id: String
    let updated_at: String
}

/// Строка листа "Accounts"
struct AccountRow: Encodable, Sendable {
    let name: String
    let balance: Double
    /// "debit" / "credit" / "savings" / "cash" и т.д.
    let type: String
    let currency: String
    let millio_id: String
}

/// Строка листа "Archived Accounts"
struct AccountArchiveRow: Encodable, Sendable {
    let name: String
    let final_balance: Double
    /// Дата архивирования в формате ISO8601
    let archived_at: String
    let millio_id: String
}

/// Строка листа "Budgets"
struct BudgetRow: Encodable, Sendable {
    let category: String
    let period_type: String
    let limit_amount: Double
    let currency: String
    let millio_id: String
}

/// Строка листа "Investments"
struct InvestmentRow: Encodable, Sendable {
    let name: String
    let ticker: String?
    let quantity: Double?
    let avg_price: Double?
    let buy_currency: String
    let total_cost: Double?
    let millio_id: String
}
