import Foundation
import SwiftData

/// Счёт нового ядра event-sourcing. Хранимых числовых полей баланса НЕТ —
/// баланс всегда производная `AccountBalanceEngine.balanceAt(events:kind:on:)` (AC1, AC2, AC9).
@Model
final class Account {
    // Без @Attribute(.unique): CloudKit-конфигурация (используется по умолчанию, если не указано
    // cloudKitDatabase: .none) не поддерживает unique-констрейнты — контейнер падает с
    // loadIssueModelContainer. Ни одна модель в проекте .unique не использует (см. Card.uniqueID).
    var id: UUID = UUID()

    var name: String = ""
    var kindRaw: String = AccountKind.cash.rawValue
    var currency: String = "RUB"
    var createdAt: Date = Date()
    /// Дата закрытия/архивации. nil = активный счёт. Двухступенчатая семантика — см. спеку §«Архив».
    var archivedAt: Date?
    var includeInTotal: Bool = true
    var note: String?
    var order: Int = 0

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

    init(
        id: UUID = UUID(),
        name: String,
        kind: AccountKind,
        currency: String = "RUB",
        createdAt: Date = Date(),
        includeInTotal: Bool = true,
        order: Int = 0
    ) {
        self.id = id
        self.name = name
        self.kindRaw = kind.rawValue
        self.currency = currency
        self.createdAt = createdAt
        self.includeInTotal = includeInTotal
        self.order = order
    }

    /// Единый предикат участия в тоталах на дату (time-aware архив, AC6/AC7).
    func participates(on date: Date) -> Bool {
        guard includeInTotal else { return false }
        guard let archivedAt else { return true }
        return date < archivedAt
    }
}
