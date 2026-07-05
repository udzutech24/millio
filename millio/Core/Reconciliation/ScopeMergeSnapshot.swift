import Foundation
import SwiftData

/// Sendable-снимки данных для reconciliation (Track B, B2b).
/// Guest читается в плоские значения ДО передачи в worker, чтобы merge шёл off-main
/// (митигация B1b №7) и не таскал managed-объекты через границу актора.

// MARK: - New-core DTO
//
// New-core В ModelTypeRegistry (AccountsCoreFeatureRegistration) — но ТОЛЬКО ради полного CloudKit
// backup/restore. Для reconciliation эти типы исключены из `legacyData`
// (см. `ScopeMergeReader.newCoreTypeNames`) — здесь копируем напрямую по id, единственный merge-путь
// (спека §0.4). Не регистрировать другой путь мержа для Account/AccountEvent/AccountGroup —
// задвоит импорт (см. докстринг `AccountsCoreFeatureRegistration`).

struct AccountGroupDTO: Sendable {
    let id: UUID
    let name: String
    let colorHex: String?
    let displayCurrency: String?
    let order: Int
}

struct AccountDTO: Sendable {
    let id: UUID
    let name: String
    let kindRaw: String
    let currency: String
    let createdAt: Date
    let archivedAt: Date?
    let includeInTotal: Bool
    let note: String?
    let order: Int
    let groupID: UUID?
    // Мета — Codable value-структуры (AccountMeta.swift), копируются целиком.
    let cardMeta: CardMeta?
    let depositMeta: DepositMeta?
    let loanMeta: LoanMeta?
    let debtMeta: DebtMeta?
    let marketMeta: MarketMeta?
    let manualAssetMeta: ManualAssetMeta?
}

struct AccountEventDTO: Sendable {
    let id: UUID
    let accountID: UUID?
    let date: Date
    let createdAt: Date
    let dayKey: String
    let typeRaw: String
    let amount: Decimal?
    let quantity: Decimal?
    let unitPrice: Decimal?
    let fxRateToBase: Decimal?
    let fxProvisional: Bool
    let categoryID: String?
    let note: String?
    let transferID: UUID?
    let sourceTransactionID: String?
    let originalAmount: Decimal?
    let originalCurrency: String?
    let redenomRate: Decimal?
    let redenomFromCurrency: String?
}

struct NewCoreSnapshot: Sendable {
    let groups: [AccountGroupDTO]
    let accounts: [AccountDTO]
    let events: [AccountEventDTO]

    static let empty = NewCoreSnapshot(groups: [], accounts: [], events: [])
}

// MARK: - Снимок одной стороны (guest или user) для детектора и lineage

struct ScopeSideSnapshot: Sendable {
    let modelCounts: [String: Int]
    let modelWatermarks: [String: Date]
    let totalEntities: Int
    /// Стабильные identity-ключи (карты/кредиты/инвестиции/группы/счета/транзакции) — для lineage-check.
    let identityFingerprints: Set<ScopeFingerprint>
    /// Число транзакций по `transactionUniqueID` — для multiset-таргетов.
    let transactionCountsByFingerprint: [ScopeFingerprint: Int]

    var isEmpty: Bool { totalEntities == 0 }
}

/// Полный вход merge, собранный из guest off-main.
struct GuestMergeInput: Sendable {
    let legacyData: Data
    let newCore: NewCoreSnapshot
    let snapshot: ScopeSideSnapshot
}

/// Результат применения merge worker'ом.
struct ScopeMergeWorkerResult: Sendable {
    let accountsAdded: Int
    let transactionsAdded: Int
}

enum ScopeMergeError: Error, Sendable {
    /// merged > guest+user по модели — невозможно при корректном merge, значит логика поехала.
    /// Контекст не сохраняется, на диск ничего не попадает (митигация B1b №7 sanity-abort).
    case sanityViolation(model: String, merged: Int, bound: Int)
}

// MARK: - Fingerprint для keyless-моделей

enum ScopeFingerprintBuilder {
    /// Волатильные поля, исключаемые из отпечатка (меняются, но не задают идентичность).
    private static let volatileKeys: Set<String> = ["updatedAt"]

    /// Отпечаток keyless-модели = канонический (sorted-keys) снимок `export()` без волатильных полей.
    /// Guest и user сериализуют одну логическую сущность одинаково → отпечатки совпадают.
    static func fingerprint(of model: any Exportable) -> ScopeFingerprint? {
        guard
            let data = try? model.export(),
            var dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        for key in volatileKeys { dict.removeValue(forKey: key) }
        guard
            let canonical = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
            let string = String(data: canonical, encoding: .utf8)
        else { return nil }
        return string
    }
}
