import Foundation
import SwiftData

// MARK: - Released product-identity AccountsCore graph

/// Frozen SwiftData declarations for the AccountsCore graph accepted under schema V6.
///
/// V6 owns the optional product-identity columns and nothing from valuation storage. Keeping the
/// declarations frozen is mandatory: referencing the mutable production `Account` here would
/// change the V6 checksum as soon as V7 adds valuation revision columns, making a genuine V6 store
/// an unknown model version instead of a migration source.
extension AppSchemaV6 {
    @Model
    final class Account {
        var id: UUID = UUID()

        var name: String = ""
        var kindRaw: String = AccountKind.cash.rawValue
        var productTypeRaw: String?
        var productMigrationReason: String?
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
            productTypeRaw: String? = nil,
            productMigrationReason: String? = nil,
            currency: String = "RUB",
            createdAt: Date = Date(),
            includeInTotal: Bool = true,
            order: Int = 0
        ) {
            self.id = id
            self.name = name
            self.kindRaw = kindRaw
            self.productTypeRaw = productTypeRaw
            self.productMigrationReason = productMigrationReason
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

    /// Frozen copy of the price-evidence entity owned by V6. Historical schemas must not point at
    /// the mutable production model: adding a future evidence column would otherwise retroactively
    /// change the accepted V6 checksum and make a genuine V6 store unopenable.
    @Model
    final class HistoricalAssetPrice {
        var id: UUID = UUID()
        var symbol: String = ""
        var assetClassRaw: String = MarketAssetClass.stock.rawValue
        var dayKey: String = ""
        var price: Decimal = 0
        var source: String = ""
        var fetchedAt: Date = Date()

        init(
            id: UUID = UUID(),
            symbol: String,
            assetClassRaw: String,
            dayKey: String,
            price: Decimal,
            source: String,
            fetchedAt: Date
        ) {
            self.id = id
            self.symbol = symbol
            self.assetClassRaw = assetClassRaw
            self.dayKey = dayKey
            self.price = price
            self.source = source
            self.fetchedAt = fetchedAt
        }
    }

    static let frozenAccountsCoreModels: [any PersistentModel.Type] = [
        Account.self,
        AccountEvent.self,
        AccountGroup.self,
        AccountDailySnapshot.self,
        HistoricalAssetPrice.self
    ]
}
