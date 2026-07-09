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

    // Поля, унаследованные от легаси-`FinanceGroup` при слиянии моделей (Фаза 1.5 плана 6b «Путь B»).
    // Все три — аддитивные с дефолтами → lightweight-миграция схемы (V6 не требуется).
    /// Избранная группа.
    var isFavorite: Bool = false
    /// Включён ли ручной порядок счетов внутри группы.
    var usesManualAccountOrdering: Bool = false
    /// Приоритет группы (raw `GroupPriority`). Тип String — как в легаси-`FinanceGroup`, чтобы
    /// перенос был байт-в-байт без потери (не Int).
    var priorityRaw: String = "normal"

    /// Постоянный маркер «поля легаси-группы уже перенесены на эту `AccountGroup`» (SwiftData,
    /// переносится при restore). Гарант идемпотентности `GroupsMigrator` — по тому же принципу, что
    /// `archivedAt` у легаси-счетов в Фазе 1: не UserDefaults-флаг, а хранимый признак, переживающий
    /// restore на новом устройстве. nil = перенос ещё не выполнялся.
    var legacyFieldsMigratedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \Account.group)
    var accounts: [Account]? = []

    var priority: GroupPriority {
        get { GroupPriority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        displayCurrency: String? = nil,
        order: Int = 0,
        isFavorite: Bool = false,
        usesManualAccountOrdering: Bool = false,
        priorityRaw: String = "normal"
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.displayCurrency = displayCurrency
        self.order = order
        self.isFavorite = isFavorite
        self.usesManualAccountOrdering = usesManualAccountOrdering
        self.priorityRaw = priorityRaw
    }

    // MARK: - Backup export/import (полный CloudKit backup, спека §0.4 — НЕ путь reconciliation)

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "AccountGroup",
            "id": id.uuidString,
            "name": name,
            "colorHex": colorHex ?? NSNull(),
            "displayCurrency": displayCurrency ?? NSNull(),
            "order": order,
            "isFavorite": isFavorite,
            "usesManualAccountOrdering": usesManualAccountOrdering,
            "priorityRaw": priorityRaw
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        // Импорт выполняется через ModelContext в AccountGroupImporter (AccountsCoreFeatureRegistration).
    }
}
