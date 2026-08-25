import Foundation
import SwiftData

// MARK: - Замороженный AccountsCore-граф версий V7/V8/V9

/// Замороженные SwiftData-декларации графа AccountsCore, принятые схемами V7, V8 и V9.
///
/// Все три версии описывают ОДИН И ТОТ ЖЕ `Account` (V8 и V9 добавляли только новые таблицы —
/// недвижимость/вложения и аудит закрытия месяца Cashflow), поэтому у них общий замороженный набор.
///
/// Заморозка обязательна: `Account.depositMeta` — composite attribute, и добавление даже одного
/// опционального поля в `DepositMeta` (V10, тег `isTaxable`) МЕНЯЕТ checksum сущности `Account`
/// задним числом. Замерено на реальном сторе: хеш `Account` уезжал с
/// `BDWJy0HN268pIbYHiNuawlUTybynWnG7Qmu7wnySOss=` — то есть уже существующий стор пользователя
/// перестал бы соответствовать какой-либо версии из плана и падал бы с NSCocoaErrorDomain 134504
/// «Cannot use staged migration with an unknown model version». Проверяется тестом
/// `AppSchemaFrozenGraphTests`.
///
/// НЕ ссылаться отсюда на продакшн-типы `Account`/`DepositMeta` — только на замороженные копии.
/// Модели без связи с `Account` (`HistoricalAssetPrice`, `HistoricalPortfolioValuation`,
/// `RealEstateProfile`, `AccountAttachment`, `CashflowMonthClosureEvent`) остаются общими:
/// их форма V10 не трогает, а дублирование ради дублирования только размножит расхождения.
extension AppSchemaV7 {

    /// Капитализация в том виде, в каком она лежит в сторах V7–V9: обычный String-enum.
    /// Продакшн-тип с V10 умеет ещё `daily`/`custom_<N>`, но на форму хранения это не влияет —
    /// в обоих случаях это одна строковая ячейка (замерено пробой checksum).
    enum FrozenDepositCapitalization: String, Codable, Hashable {
        case none
        case monthly
        case quarterly
    }

    /// `DepositMeta` без тега `isTaxable` — ровно та форма, что записана в сторах V4–V9.
    /// Переиспользуется графами V5/V6 (`AppSchemaV5`/`AppSchemaV6`): вклад ни разу не менял форму
    /// от V4 до V9, поэтому замороженная копия одна на все исторические версии.
    struct FrozenDepositMeta: Codable, Equatable {
        var rate: Decimal
        var capitalization: FrozenDepositCapitalization
        var termEnd: Date?
        var payoutDay: Int?
        var allowsTopUp: Bool
        var allowsEarlyClose: Bool
        var earlyClosePenalty: Decimal?
        var remindEnd: Bool
        var autoRollover: Bool
    }

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

        var valuationMembershipRevision: Int64?
        var valuationFinancialRevision: Int64?
        var valuationEventRevision: Int64?

        var cardMeta: CardMeta?
        var depositMeta: FrozenDepositMeta?
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
