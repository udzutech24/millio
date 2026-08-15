import Foundation

/// Persisted financial-product identity. Unlike `AccountKind`, this preserves user intent when
/// several products share one replay engine (for example real estate and business).
enum AccountProductType: String, Codable, CaseIterable, Hashable {
    case cash
    case debitCard
    case creditCard
    case bankAccount
    case deposit
    case loan
    case receivable
    case payable
    case marketStock
    case marketCrypto
    case marketBond
    case marketMetal
    case genericMarketInvestment
    case realEstate
    case business
    case vehicle
    case otherManualAsset
    case unknownLegacy
}

/// Stable diagnostic persisted alongside `unknownLegacy`. Raw values are backup-compatible and
/// intentionally not localized.
enum ProductMigrationReason: String, Codable, CaseIterable, Hashable {
    case invalidKindRaw
    case multipleMetaObjects
    case kindMetaContradiction
    case ambiguousCashKind
    case nonPositiveCreditLimit
    case invalidDepositMeta
    case invalidLoanMeta
    case invalidDebtMeta
    case invalidMarketMeta
    case ambiguousManualAsset
    case invalidPersistedProductType
    case persistedProductContradiction
    case unverifiedLegacyMapping
}
