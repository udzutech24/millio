import Foundation
import SwiftData

/// Производный кэш `balanceAt` по дням, в валюте САМОГО счёта (AC8).
/// НЕ источник истины — может быть удалён и пересобран из событий в любой момент.
@Model
final class AccountDailySnapshot: Persistable {
    // Без @Attribute(.unique) — см. комментарий в Account.swift (CloudKit-конфигурация не поддерживает unique).
    var id: UUID = UUID()

    var account: Account?

    /// Календарный день кэша, формат "yyyy-MM-dd" (тот же формат, что `AccountEvent.dayKey`).
    var dayKey: String = ""
    var balance: Decimal = 0
    /// Количество актива на конец дня (только для рыночных счетов).
    var quantity: Decimal?
    /// Счёт был закрыт (архивирован) на эту дату — participates(date) == false.
    var isClosed: Bool = false
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        account: Account? = nil,
        dayKey: String,
        balance: Decimal,
        quantity: Decimal? = nil,
        isClosed: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.account = account
        self.dayKey = dayKey
        self.balance = balance
        self.quantity = quantity
        self.isClosed = isClosed
        self.updatedAt = updatedAt
    }

    // MARK: - Backup export/import (полный CloudKit backup, спека §0.4 — НЕ путь reconciliation.
    // В отличие от reconciliation, где снапшоты сознательно НЕ копируются и пересобираются из событий
    // (см. `ScopeMergeDedup.copyNewCore`), полный snapshot-бэкап их переносит — это ускоряет отображение
    // сразу после restore, не дожидаясь фонового rebuild.)

    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "AccountDailySnapshot",
            "id": id.uuidString,
            "dayKey": dayKey,
            "balance": "\(balance)",
            "isClosed": isClosed,
            "updatedAt": updatedAt.timeIntervalSince1970
        ]
        if let accountID = account?.id { dict["accountID"] = accountID.uuidString }
        if let quantity { dict["quantity"] = "\(quantity)" }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        // Импорт выполняется через ModelContext в AccountDailySnapshotImporter (AccountsCoreFeatureRegistration).
    }
}
