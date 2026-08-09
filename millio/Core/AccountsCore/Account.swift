import Foundation
import SwiftData

/// Счёт нового ядра event-sourcing. Хранимых числовых полей баланса НЕТ —
/// баланс всегда производная `AccountBalanceEngine.balanceAt(events:kind:on:)` (AC1, AC2, AC9).
@Model
final class Account: Persistable {
    // Без @Attribute(.unique): CloudKit-конфигурация (используется по умолчанию, если не указано
    // cloudKitDatabase: .none) не поддерживает unique-констрейнты — контейнер падает с
    // loadIssueModelContainer. Ни одна модель в проекте .unique не использует (см. Card.uniqueID).
    var id: UUID = UUID()

    var name: String = ""
    var kindRaw: String = AccountKind.cash.rawValue
    /// Канонический финансовый продукт. `nil` допустим только для ещё не
    /// классифицированных legacy-строк. Новые writer-пути обязаны сохранять
    /// non-unknown identity после проверки `ProductDefinitionCatalog`.
    var productTypeRaw: String?
    /// Диагностика только для `unknownLegacy`. Это стабильный raw-value, а не
    /// локализованный UI-текст.
    var productMigrationReason: String?
    var currency: String = "RUB"
    var createdAt: Date = Date()
    /// Дата закрытия/архивации. nil = активный счёт. Двухступенчатая семантика — см. спеку §«Архив».
    var archivedAt: Date?
    /// Дата мягкого удаления (tombstone, Ф5/Q1). nil = не удалён. Счёт с `deletedAt` исчезает из ВСЕХ
    /// UI-списков, но его события/снапшоты сохраняются — история графика до этой даты неизменна
    /// (в отличие от каскадного `.cascade`-сноса, который переписывал прошлое). В тоталах ведёт себя
    /// как жёсткая отсечка наравне с `archivedAt` (см. `participates(on:)`).
    var deletedAt: Date?
    var includeInTotal: Bool = true
    var note: String?
    var order: Int = 0

    /// Persisted monotonic hints for valuation invalidation. They are optional so a genuine V6
    /// row migrates additively to V7 without rewriting source data. The canonical input revision
    /// still includes source values, so a saturated counter cannot hide a later correction.
    var valuationMembershipRevision: Int64?
    var valuationFinancialRevision: Int64?
    var valuationEventRevision: Int64?

    // MARK: - Метаданные по типу (заполняется только соответствующая kind)
    var cardMeta: CardMeta?
    var depositMeta: DepositMeta?
    var loanMeta: LoanMeta?
    var debtMeta: DebtMeta?
    var marketMeta: MarketMeta?
    var manualAssetMeta: ManualAssetMeta?

    var group: AccountGroup?

    @Relationship(deleteRule: .cascade, inverse: \AccountEvent.account)
    var events: [AccountEvent]? = []

    @Relationship(deleteRule: .cascade, inverse: \AccountDailySnapshot.account)
    var snapshots: [AccountDailySnapshot]? = []

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .cash }
        set { kindRaw = newValue.rawValue }
    }

    var productType: AccountProductType? {
        get { productTypeRaw.flatMap(AccountProductType.init(rawValue:)) }
        set {
            productTypeRaw = newValue?.rawValue
            if newValue != .unknownLegacy {
                productMigrationReason = nil
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        kind: AccountKind,
        productType: AccountProductType? = nil,
        currency: String = "RUB",
        createdAt: Date = Date(),
        includeInTotal: Bool = true,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.productTypeRaw = productType?.rawValue
        self.currency = currency
        self.createdAt = createdAt
        self.includeInTotal = includeInTotal
        self.order = order
    }

    /// Единый предикат участия в тоталах на дату (time-aware архив/удаление, AC6/AC7/Ф5).
    /// `archivedAt` и `deletedAt` — обе жёсткие отсечки: до наступившей даты счёт участвует, начиная
    /// с неё — нет. Берём САМУЮ РАННЮЮ из заданных (архивация и удаление могут стоять на разных датах;
    /// в текущем UI удаление доступно только для уже архивных, т.е. обычно archivedAt ≤ deletedAt).
    func participates(on date: Date) -> Bool {
        guard includeInTotal else { return false }
        return isVisible(on: date)
    }

    /// Видимость в активном списке не зависит от `includeInTotal`: исключённый из капитала
    /// продукт должен оставаться доступным для просмотра и обратного включения.
    /// Архив/удаление остаются time-aware жёсткой отсечкой.
    func isVisible(on date: Date) -> Bool {
        guard let cutoff = [archivedAt, deletedAt].compactMap({ $0 }).min() else { return true }
        return date < cutoff
    }

    // MARK: - Backup export/import (полный CloudKit backup, спека §0.4 — НЕ путь reconciliation)

    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "Account",
            "id": id.uuidString,
            "name": name,
            "kindRaw": kindRaw,
            "currency": currency,
            "createdAt": createdAt.timeIntervalSince1970,
            "includeInTotal": includeInTotal,
            "order": order
        ]
        if let productTypeRaw { dict["productTypeRaw"] = productTypeRaw }
        if let productMigrationReason { dict["productMigrationReason"] = productMigrationReason }
        if let valuationMembershipRevision { dict["valuationMembershipRevision"] = valuationMembershipRevision }
        if let valuationFinancialRevision { dict["valuationFinancialRevision"] = valuationFinancialRevision }
        if let valuationEventRevision { dict["valuationEventRevision"] = valuationEventRevision }
        if let archivedAt { dict["archivedAt"] = archivedAt.timeIntervalSince1970 }
        if let deletedAt { dict["deletedAt"] = deletedAt.timeIntervalSince1970 }
        if let note { dict["note"] = note }
        if let groupID = group?.id { dict["groupID"] = groupID.uuidString }
        if let cardMeta { dict["cardMeta"] = cardMeta.exportDict() }
        if let depositMeta { dict["depositMeta"] = depositMeta.exportDict() }
        if let loanMeta { dict["loanMeta"] = loanMeta.exportDict() }
        if let debtMeta { dict["debtMeta"] = debtMeta.exportDict() }
        if let marketMeta { dict["marketMeta"] = marketMeta.exportDict() }
        if let manualAssetMeta { dict["manualAssetMeta"] = manualAssetMeta.exportDict() }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        // Импорт выполняется через ModelContext в AccountImporter (AccountsCoreFeatureRegistration).
    }
}
