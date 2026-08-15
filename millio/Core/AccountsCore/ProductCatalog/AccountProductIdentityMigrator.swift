import Foundation
import SwiftData

/// Proof that a structured legacy row still exists and the device-local registry maps that exact
/// row to this exact core UUID. Without both values, legacy category is not migration evidence.
struct VerifiedLegacyProductEvidence: Equatable {
    let legacyRowIdentifier: String
    let registryMappedCoreAccountID: UUID
    let productType: AccountProductType

    private init(
        legacyRowIdentifier: String,
        registryMappedCoreAccountID: UUID,
        productType: AccountProductType
    ) {
        self.legacyRowIdentifier = legacyRowIdentifier
        self.registryMappedCoreAccountID = registryMappedCoreAccountID
        self.productType = productType
    }

    /// Requiring a concrete generic row makes "row exists" part of the call contract; checking the
    /// real registry here makes the device-local mapping proof non-forgeable by migration callers.
    @MainActor
    static func verify<LegacyRow>(
        row: LegacyRow,
        identifier: (LegacyRow) -> String,
        productType: AccountProductType,
        coreAccount: Account,
        registry: LegacyConversionRegistry
    ) -> VerifiedLegacyProductEvidence? {
        let legacyRowIdentifier = identifier(row)
        guard !legacyRowIdentifier.isEmpty,
              registry.coreAccountID(forLegacyUniqueID: legacyRowIdentifier) == coreAccount.id else {
            return nil
        }
        return VerifiedLegacyProductEvidence(
            legacyRowIdentifier: legacyRowIdentifier,
            registryMappedCoreAccountID: coreAccount.id,
            productType: productType
        )
    }

    func applies(to account: Account) -> Bool {
        !legacyRowIdentifier.isEmpty && registryMappedCoreAccountID == account.id
    }
}

struct ProductIdentityMigrationAssignment: Equatable {
    let productType: AccountProductType
    let reason: ProductMigrationReason?
}

/// Deterministic, side-effect-limited classification of existing rows. It mutates only the two
/// additive product columns; kind, meta, events, snapshots and lifecycle stay untouched.
enum AccountProductIdentityMigrator {
    /// Cold-start/restore boundary for already-persisted rows. An isolated context prevents a
    /// classification save failure from contaminating unrelated pending UI changes.
    @MainActor
    static func migratePersistedAccounts(
        in container: ModelContainer,
        verifiedEvidenceByCoreAccountID: [UUID: VerifiedLegacyProductEvidence] = [:]
    ) throws -> Int {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        do {
            let accounts = try context.fetch(FetchDescriptor<Account>())
            let changed = migrate(
                accounts,
                verifiedEvidenceByCoreAccountID: verifiedEvidenceByCoreAccountID
            )
            if changed > 0 { try context.save() }
            return changed
        } catch {
            context.rollback()
            throw error
        }
    }

    @discardableResult
    static func migrate(
        _ accounts: [Account],
        verifiedEvidenceByCoreAccountID: [UUID: VerifiedLegacyProductEvidence] = [:]
    ) -> Int {
        accounts.reduce(into: 0) { changedCount, account in
            if migrate(account, verifiedLegacyEvidence: verifiedEvidenceByCoreAccountID[account.id]) {
                changedCount += 1
            }
        }
    }

    @discardableResult
    static func migrate(
        _ account: Account,
        verifiedLegacyEvidence: VerifiedLegacyProductEvidence? = nil
    ) -> Bool {
        let assignment = classify(account, verifiedLegacyEvidence: verifiedLegacyEvidence)
        let nextReason = assignment.reason?.rawValue
        guard account.productTypeRaw != assignment.productType.rawValue
                || account.productMigrationReason != nextReason else {
            return false
        }
        account.productTypeRaw = assignment.productType.rawValue
        account.productMigrationReason = nextReason
        HistoricalValuationRevisionTracker.bump([.financial], on: account)
        return true
    }

    static func classify(
        _ account: Account,
        verifiedLegacyEvidence: VerifiedLegacyProductEvidence? = nil
    ) -> ProductIdentityMigrationAssignment {
        let metadata = AccountProductMetadata(account: account)

        if let raw = account.productTypeRaw {
            guard let existing = AccountProductType(rawValue: raw) else {
                return unknown(.invalidPersistedProductType)
            }
            do {
                try ProductDefinitionCatalog.validateStoredIdentity(
                    existing,
                    kindRaw: account.kindRaw,
                    metadata: metadata,
                    migrationReason: account.productMigrationReason
                )
                return ProductIdentityMigrationAssignment(
                    productType: existing,
                    reason: existing == .unknownLegacy
                        ? account.productMigrationReason.flatMap(ProductMigrationReason.init(rawValue:))
                            ?? .persistedProductContradiction
                        : nil
                )
            } catch {
                return unknown(.persistedProductContradiction)
            }
        }

        guard let kind = AccountKind(rawValue: account.kindRaw) else {
            return unknown(.invalidKindRaw)
        }
        guard metadata.presentKinds.count <= 1 else {
            return unknown(.multipleMetaObjects)
        }
        guard metaIsCompatibleWithKind(metadata.presentKinds.first, kind: kind) else {
            return unknown(.kindMetaContradiction)
        }

        switch kind {
        case .cash:
            if let limit = metadata.card?.creditLimit {
                return limit > 0 ? resolved(.creditCard) : unknown(.nonPositiveCreditLimit)
            }
            return classifyAmbiguous(
                account,
                metadata: metadata,
                fallback: .ambiguousCashKind,
                verifiedLegacyEvidence: verifiedLegacyEvidence
            )
        case .debitCard:
            if let limit = metadata.card?.creditLimit {
                return limit > 0 ? resolved(.creditCard) : unknown(.nonPositiveCreditLimit)
            }
            return resolved(.debitCard)
        case .bankAccount:
            return resolved(.bankAccount)
        case .deposit:
            guard let deposit = metadata.deposit,
                  deposit.rate >= 0,
                  deposit.earlyClosePenalty.map({ $0 >= 0 && $0 <= 1 }) ?? true else {
                return unknown(.invalidDepositMeta)
            }
            return resolved(.deposit)
        case .loan:
            guard let loan = metadata.loan,
                  loan.principal > 0,
                  loan.rate >= 0,
                  loan.monthlyPayment.map({ $0 > 0 }) ?? true else {
                return unknown(.invalidLoanMeta)
            }
            return resolved(.loan)
        case .debt:
            guard let direction = metadata.debt?.direction else {
                return unknown(.invalidDebtMeta)
            }
            return resolved(direction == .owedToMe ? .receivable : .payable)
        case .marketInvestment:
            guard let market = metadata.market,
                  !market.symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return unknown(.invalidMarketMeta)
            }
            switch market.assetClass {
            case .stock: return resolved(.marketStock)
            case .crypto: return resolved(.marketCrypto)
            case .bond: return resolved(.marketBond)
            case .metal: return resolved(.marketMetal)
            }
        case .manualAsset:
            return classifyAmbiguous(
                account,
                metadata: metadata,
                fallback: .ambiguousManualAsset,
                verifiedLegacyEvidence: verifiedLegacyEvidence
            )
        }
    }

    private static func classifyAmbiguous(
        _ account: Account,
        metadata: AccountProductMetadata,
        fallback: ProductMigrationReason,
        verifiedLegacyEvidence: VerifiedLegacyProductEvidence?
    ) -> ProductIdentityMigrationAssignment {
        guard let evidence = verifiedLegacyEvidence else { return unknown(fallback) }
        guard evidence.applies(to: account), evidence.productType != .unknownLegacy else {
            return unknown(.unverifiedLegacyMapping)
        }
        do {
            try ProductDefinitionCatalog.validateNewProduct(
                evidence.productType,
                kind: AccountKind(rawValue: account.kindRaw)!,
                metadata: metadata
            )
            return resolved(evidence.productType)
        } catch {
            return unknown(.unverifiedLegacyMapping)
        }
    }

    private static func metaIsCompatibleWithKind(_ meta: AccountMetaKind?, kind: AccountKind) -> Bool {
        // Missing required meta is classified by the kind-specific branch below so diagnostics
        // distinguish corruption from an incompatible *different* meta object.
        guard let meta else { return true }
        switch kind {
        case .cash, .debitCard, .bankAccount: return meta == .card
        case .deposit: return meta == .deposit
        case .loan: return meta == .loan
        case .debt: return meta == .debt
        case .marketInvestment: return meta == .market
        case .manualAsset: return meta == .manualAsset
        }
    }

    private static func resolved(_ productType: AccountProductType) -> ProductIdentityMigrationAssignment {
        ProductIdentityMigrationAssignment(productType: productType, reason: nil)
    }

    private static func unknown(_ reason: ProductMigrationReason) -> ProductIdentityMigrationAssignment {
        ProductIdentityMigrationAssignment(productType: .unknownLegacy, reason: reason)
    }
}
