import Foundation
import SwiftData

// MARK: - Released pre-product AccountsCore graph

/// Frozen SwiftData declarations for the AccountsCore graph that shipped under schema V4/V5.
///
/// Historical schemas must never reference the mutable production `Account` type. Doing so changes
/// their runtime checksum whenever a stored property is added and makes a genuine older store an
/// "unknown model version". These declarations intentionally contain only the persisted shape from
/// the pre-product V5 source. Business behavior belongs to the current top-level models.
extension AppSchemaV5 {
    @Model
    final class Account {
        var id: UUID = UUID()

        var name: String = ""
        var kindRaw: String = AccountKind.cash.rawValue
        var currency: String = "RUB"
        var createdAt: Date = Date()
        var archivedAt: Date?
        var deletedAt: Date?
        var includeInTotal: Bool = true
        var note: String?
        var order: Int = 0

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

        init(
            id: UUID = UUID(),
            name: String,
            kindRaw: String = AccountKind.cash.rawValue,
            currency: String = "RUB",
            createdAt: Date = Date(),
            includeInTotal: Bool = true,
            order: Int = 0
        ) {
            self.id = id
            self.name = name
            self.kindRaw = kindRaw
            self.currency = currency
            self.createdAt = createdAt
            self.includeInTotal = includeInTotal
            self.order = order
        }
    }

    @Model
    final class AccountEvent {
        var id: UUID = UUID()

        var account: Account?
        var date: Date = Date()
        var createdAt: Date = Date()
        var dayKey: String = ""
        var typeRaw: String = AccountEventType.adjustment.rawValue
        var amount: Decimal?
        var quantity: Decimal?
        var unitPrice: Decimal?
        var fxRateToBase: Decimal?
        var fxProvisional: Bool = false
        var categoryID: String?
        var note: String?
        var transferID: UUID?
        var sourceTransactionID: String?
        var originalAmount: Decimal?
        var originalCurrency: String?
        var redenomRate: Decimal?
        var redenomFromCurrency: String?

        init(
            id: UUID = UUID(),
            account: Account? = nil,
            date: Date,
            createdAt: Date = Date(),
            dayKey: String = "",
            typeRaw: String = AccountEventType.adjustment.rawValue
        ) {
            self.id = id
            self.account = account
            self.date = date
            self.createdAt = createdAt
            self.dayKey = dayKey
            self.typeRaw = typeRaw
        }
    }

    @Model
    final class AccountGroup {
        var id: UUID = UUID()

        var name: String = ""
        var colorHex: String?
        var displayCurrency: String?
        var order: Int = 0
        var customIconName: String?
        var isFavorite: Bool = false
        var usesManualAccountOrdering: Bool = false
        var priorityRaw: String = "normal"
        var legacyFieldsMigratedAt: Date?

        @Relationship(deleteRule: .nullify, inverse: \Account.group)
        var accounts: [Account]? = []

        init(
            id: UUID = UUID(),
            name: String,
            colorHex: String? = nil,
            displayCurrency: String? = nil,
            order: Int = 0
        ) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
            self.displayCurrency = displayCurrency
            self.order = order
        }
    }

    @Model
    final class AccountDailySnapshot {
        var id: UUID = UUID()

        var account: Account?
        var dayKey: String = ""
        var balance: Decimal = 0
        var quantity: Decimal?
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
    }

    static let frozenAccountsCoreModels: [any PersistentModel.Type] = [
        Account.self,
        AccountEvent.self,
        AccountGroup.self,
        AccountDailySnapshot.self
    ]
}
