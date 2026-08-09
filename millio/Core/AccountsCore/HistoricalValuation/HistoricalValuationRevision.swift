import Foundation

enum HistoricalValuationRevisionDimension: String, CaseIterable, Hashable, Sendable {
    case accountSet
    case financial
    case events
    case evidence
}

enum HistoricalScopeOperation: String, CaseIterable, Hashable, Sendable {
    case restore
    case reconciliation
    case backfill
    case revisionMigration
}

enum HistoricalValuationWriterKind: String, Hashable, Sendable {
    case source
    case evidence
    case derivedCache
    case lifecycle
}

struct HistoricalValuationWriterInventoryEntry: Hashable, Sendable {
    let id: String
    let sourcePath: String
    let entryPoint: String
    let kind: HistoricalValuationWriterKind
    let revisionImpacts: Set<HistoricalValuationRevisionDimension>
    let readinessImpacts: Set<HistoricalScopeOperation>
}

enum HistoricalValuationRevisionTracker {
    static func bump(
        _ dimensions: Set<HistoricalValuationRevisionDimension>,
        on account: Account
    ) {
        if dimensions.contains(.accountSet) {
            account.valuationMembershipRevision = next(account.valuationMembershipRevision)
        }
        if dimensions.contains(.financial) {
            account.valuationFinancialRevision = next(account.valuationFinancialRevision)
        }
        if dimensions.contains(.events) {
            account.valuationEventRevision = next(account.valuationEventRevision)
        }
    }

    private static func next(_ current: Int64?) -> Int64 {
        guard let current else { return 1 }
        return current == .max ? .max : current + 1
    }
}

/// Auditable inventory used by V6 to wire persisted bumps. Phase 1V deliberately records impact
/// without adding columns early; cache rebuilds never masquerade as source-data revisions.
enum HistoricalValuationWriterInventory {
    static let entries: [HistoricalValuationWriterInventoryEntry] = [
        entry("core-create", "millio/Core/AccountsCore/AccountsCoreService.swift", "createAccount", [.accountSet, .financial, .events]),
        entry("core-events", "millio/Core/AccountsCore/AccountsCoreService.swift", "recordEvent/adjustBalance/buy/sell/revalue/upsertEvent/upsertInterestEvent/transfer/deleteEvent/updateEvent", [.events]),
        entry("core-lifecycle", "millio/Core/AccountsCore/AccountsCoreService.swift", "archiveAccount/restoreAccount/softDelete/physicallyDelete", [.accountSet, .events]),
        entry("core-meta", "millio/Core/AccountsCore/AccountsCoreService.swift", "updateAccount", [.financial]),
        entry("deposit-generated-events", "millio/Core/AccountsCore/DepositInterestScheduler.swift", "generate/deleteGeneratedInterestEvents", [.events]),
        entry("core-seed", "millio/Core/AccountsCore/AccountsCoreSeeder.swift", "seedIfNeeded", [.accountSet, .financial, .events]),
        entry("backup-account-import", "millio/Core/AccountsCore/AccountsCoreFeatureRegistration.swift", "AccountImporter.import", [.accountSet, .financial, .events], readiness: [.restore]),
        entry("scope-core-copy", "millio/Core/Reconciliation/ScopeMergeDedup.swift", "copyNewCore", [.accountSet, .financial, .events], readiness: [.reconciliation]),
        entry("legacy-core-conversion", "millio/Core/AccountsCore/LegacyAccountConverter.swift", "convert/unconvert", [.accountSet, .financial, .events]),
        entry("legacy-card", "millio/UI/Services/CardIndex/CardViewModel.swift", "create/update/delete", [.accountSet, .financial, .events]),
        entry("legacy-credit", "millio/UI/Services/Credits/CreditViewModel.swift", "create/update/delete", [.accountSet, .financial, .events]),
        entry("legacy-investment", "millio/UI/Services/Investments/InvestmentViewModel.swift", "create/update/delete", [.accountSet, .financial, .events]),
        entry("legacy-finance-lifecycle", "millio/UI/Services/Finances/FinanceAccountService.swift", "archive/restore/delete", [.accountSet, .financial]),
        entry("market-price-write", "millio/Core/AccountsCore/AccountMarketPriceService.swift", "refreshTodayPrices/upsertTodayPrice", [.evidence], kind: .evidence),
        entry("market-price-import", "millio/Core/AccountsCore/AccountsCoreFeatureRegistration.swift", "HistoricalAssetPriceImporter.import", [.evidence], kind: .evidence, readiness: [.restore, .reconciliation]),
        entry("fx-rate-write", "millio/Core/Currency/HistoricalRateStore.swift", "getRate/prefetchExactRates/upsertRate", [.evidence], kind: .evidence),
        entry("fx-rate-import", "millio/Core/Currency/CurrencyFeatureRegistration.swift", "HistoricalRateImporter.import", [.evidence], kind: .evidence, readiness: [.restore, .reconciliation]),
        entry("snapshot-rebuild", "millio/Core/AccountsCore/AccountSnapshotRebuilder.swift", "rebuild/rebuildAll", [], kind: .derivedCache),
        entry("snapshot-import", "millio/Core/AccountsCore/AccountsCoreFeatureRegistration.swift", "AccountDailySnapshotImporter.import", [], kind: .derivedCache, readiness: [.restore]),
        entry("restore-gate", "millio/Core/Backup/BackupManager.swift", "restoreLatest/restoreVersion", [], kind: .lifecycle, readiness: [.restore]),
        entry("reconciliation-gate", "millio/Core/Reconciliation/ScopeReconciliationService.swift", "reconcile", [], kind: .lifecycle, readiness: [.reconciliation]),
        entry("snapshot-backfill-gate", "millio/Core/AccountsCore/AccountSnapshotBackfillCoordinator.swift", "backfillIfNeeded", [], kind: .lifecycle, readiness: [.backfill]),
        entry("revision-migration-gate", "millio/UI/Services/Finances/LegacyAccountsMigrator.swift", "migrateIfNeeded", [], kind: .lifecycle, readiness: [.revisionMigration])
    ]

    private static func entry(
        _ id: String,
        _ sourcePath: String,
        _ entryPoint: String,
        _ revisions: Set<HistoricalValuationRevisionDimension>,
        kind: HistoricalValuationWriterKind = .source,
        readiness: Set<HistoricalScopeOperation> = []
    ) -> HistoricalValuationWriterInventoryEntry {
        .init(
            id: id,
            sourcePath: sourcePath,
            entryPoint: entryPoint,
            kind: kind,
            revisionImpacts: revisions,
            readinessImpacts: readiness
        )
    }
}

@MainActor
enum HistoricalValuationRevisionBuilder {
    static func build(
        accounts: [Account],
        eventsByAccountID: [UUID: [AccountEvent]],
        evidenceRevision: UInt64 = 0
    ) -> HistoricalValuationInputRevision {
        var accountSet = StableRevisionDigest()
        var financial = StableRevisionDigest()
        var events = StableRevisionDigest()

        for account in accounts.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            accountSet.combine(account.id.uuidString)
            accountSet.combine(account.createdAt)
            accountSet.combine(account.archivedAt)
            accountSet.combine(account.deletedAt)
            accountSet.combine(account.includeInTotal)
            accountSet.combine(account.valuationMembershipRevision)

            financial.combine(account.id.uuidString)
            financial.combine(account.kindRaw)
            financial.combine(account.productTypeRaw)
            financial.combine(account.productMigrationReason)
            financial.combine(account.currency.uppercased())
            financial.combine(account.cardMeta?.creditLimit)
            financial.combine(account.depositMeta?.rate)
            financial.combine(account.depositMeta?.capitalization.rawValue)
            financial.combine(account.depositMeta?.termEnd)
            financial.combine(account.depositMeta?.earlyClosePenalty)
            financial.combine(account.loanMeta?.principal)
            financial.combine(account.loanMeta?.rate)
            financial.combine(account.debtMeta?.direction.rawValue)
            financial.combine(account.marketMeta?.symbol.uppercased())
            financial.combine(account.marketMeta?.assetClass.rawValue)
            financial.combine(account.manualAssetMeta?.depreciationRatePerYear)
            financial.combine(account.valuationFinancialRevision)

            events.combine(account.valuationEventRevision)

            for event in (eventsByAccountID[account.id] ?? []).sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                events.combine(account.id.uuidString)
                events.combine(event.id.uuidString)
                events.combine(event.date)
                events.combine(event.createdAt)
                events.combine(event.dayKey)
                events.combine(event.typeRaw)
                events.combine(event.amount)
                events.combine(event.quantity)
                events.combine(event.unitPrice)
                events.combine(event.fxRateToBase)
                events.combine(event.fxProvisional)
                events.combine(event.transferID?.uuidString)
                events.combine(event.redenomRate)
                events.combine(event.redenomFromCurrency)
            }
        }

        return .init(
            accountSet: accountSet.value,
            financial: financial.value,
            events: events.value,
            evidence: evidenceRevision
        )
    }
}

private struct StableRevisionDigest {
    private(set) var value: UInt64 = 14_695_981_039_346_656_037

    mutating func combine<T>(_ value: T?) {
        let string = value.map(String.init(describing:)) ?? "<nil>"
        for byte in string.utf8 {
            self.value ^= UInt64(byte)
            self.value &*= 1_099_511_628_211
        }
        self.value ^= 0xFF
        self.value &*= 1_099_511_628_211
    }
}
