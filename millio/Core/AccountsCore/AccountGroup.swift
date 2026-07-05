import Foundation
import SwiftData

/// Группа счетов нового ядра — только ярлык, не участвует в расчёте баланса.
/// Названа AccountGroup (не Group) — конфликт имени с SwiftUI.Group.
@Model
final class AccountGroup: Persistable {
    // Без @Attribute(.unique) — см. комментарий в Account.swift (CloudKit-конфигурация не поддерживает unique).
    var id: UUID = UUID()

    var name: String = ""
    var colorHex: String?
    var displayCurrency: String?
    var order: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \Account.group)
    var accounts: [Account]? = []

    init(id: UUID = UUID(), name: String, colorHex: String? = nil, displayCurrency: String? = nil, order: Int = 0) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.displayCurrency = displayCurrency
        self.order = order
    }

    // MARK: - Backup export/import (полный CloudKit backup, спека §0.4 — НЕ путь reconciliation)

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "AccountGroup",
            "id": id.uuidString,
            "name": name,
            "colorHex": colorHex ?? NSNull(),
            "displayCurrency": displayCurrency ?? NSNull(),
            "order": order
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        // Импорт выполняется через ModelContext в AccountGroupImporter (AccountsCoreFeatureRegistration).
    }
}
