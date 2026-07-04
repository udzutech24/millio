import Foundation
import SwiftData

/// Дедуп слитого набора и копия new-core (Track B, B2b). Nonisolated — вызывается на
/// executor'е worker-актора синхронно, оперирует его context'ом.
///
/// Отдельно от `DataIntegrityCleaner` (тот @MainActor и сохраняет контекст сам) —
/// merge идёт off-main с ЕДИНСТВЕННЫМ save в конце (митигация B1b №5), плюс здесь multiset
/// для транзакций (митигация B1b №3), которого в restore-дедупе быть не должно.
enum ScopeMergeDedup {

    /// - transactionTargets: целевое число транзакций на `transactionUniqueID` = max(guest, user).
    static func dedupe(context: ModelContext, transactionTargets: [ScopeFingerprint: Int]) throws {
        // Identity-keyed (single-collapse LWW по updatedAt) — паттерн DataIntegrityCleaner.
        try collapse(context, Card.self, fingerprint: { $0.cardUniqueID }, updatedAt: { $0.updatedAt })
        try collapse(context, Credit.self, fingerprint: { $0.creditUniqueID }, updatedAt: { $0.updatedAt })
        try collapse(context, Investment.self, fingerprint: { $0.investmentUniqueID }, updatedAt: { $0.updatedAt })
        try collapseGroups(context) // с ре-парентингом счетов (митигация B1b №4)
        try collapse(context, FinanceAccount.self, fingerprint: { $0.accountUniqueID }, updatedAt: { $0.updatedAt })

        // Keyless (single-collapse LWW по export-fingerprint). Импортёры этих моделей — blind INSERT,
        // поэтому без дедупа общая first-login база задвоилась бы.
        try collapse(context, Cashback.self, fingerprint: exportFP, updatedAt: { $0.updatedAt })
        try collapse(context, CashbackCustomCategory.self, fingerprint: exportFP, updatedAt: { $0.updatedAt })
        try collapse(context, UserSubscription.self, fingerprint: exportFP, updatedAt: { $0.updatedAt })
        try collapse(context, BudgetPlan.self, fingerprint: exportFP, updatedAt: { $0.updatedAt })
        try collapse(context, BudgetCategoryLimit.self, fingerprint: exportFP, updatedAt: { $0.updatedAt })
        try collapse(context, CashflowCustomCategory.self, fingerprint: exportFP, updatedAt: { $0.updatedAt })
        try collapse(context, CashflowSystemCategoryOverride.self, fingerprint: exportFP, updatedAt: { $0.updatedAt })

        // Транзакции — MULTISET: не схлопываем легитимные bulk-дубли (митигация B1b №3).
        try multisetTransactions(context, targets: transactionTargets)
    }

    private static func exportFP<T: PersistentModel & Exportable>(_ model: T) -> ScopeFingerprint? {
        ScopeFingerprintBuilder.fingerprint(of: model)
    }

    private static func collapse<T: PersistentModel>(
        _ context: ModelContext,
        _ type: T.Type,
        fingerprint: (T) -> ScopeFingerprint?,
        updatedAt: (T) -> Date
    ) throws {
        let items = try context.fetch(FetchDescriptor<T>())
        var byFP: [ScopeFingerprint: T] = [:]
        for item in items {
            guard let fp = fingerprint(item), !fp.isEmpty else { continue }
            if let existing = byFP[fp] {
                if updatedAt(item) >= updatedAt(existing) {
                    context.delete(existing)
                    byFP[fp] = item
                } else {
                    context.delete(item)
                }
            } else {
                byFP[fp] = item
            }
        }
    }

    /// Схлопывание дублей групп с перецепкой счетов на выживший экземпляр (митигация B1b №4).
    private static func collapseGroups(_ context: ModelContext) throws {
        let groups = try context.fetch(FetchDescriptor<FinanceGroup>())
        let accounts = try context.fetch(FetchDescriptor<FinanceAccount>())
        var byFP: [ScopeFingerprint: FinanceGroup] = [:]
        for group in groups {
            let fp = group.groupUniqueID
            guard !fp.isEmpty else { continue }
            if let existing = byFP[fp] {
                let keep: FinanceGroup
                let remove: FinanceGroup
                if group.updatedAt >= existing.updatedAt { keep = group; remove = existing }
                else { keep = existing; remove = group }
                for account in accounts where account.group?.persistentModelID == remove.persistentModelID {
                    account.group = keep
                }
                byFP[fp] = keep
                context.delete(remove)
            } else {
                byFP[fp] = group
            }
        }
    }

    private static func multisetTransactions(_ context: ModelContext, targets: [ScopeFingerprint: Int]) throws {
        let txs = try context.fetch(FetchDescriptor<CashflowTransaction>())
        let instances = txs.map { (fingerprint: $0.transactionUniqueID, updatedAt: $0.updatedAt, ref: $0) }
        for tx in MultisetReconciler.instancesToDelete(instances, targets: targets) {
            context.delete(tx)
        }
    }

    // MARK: - Копия new-core по id (спека §2 «New-core merge»)

    /// Вставляет отсутствующие в user группы/счета/события new-core по `id` (идемпотентно).
    /// Снапшоты (`AccountDailySnapshot`) НЕ копируются — пересобираются после merge (спека §2).
    static func copyNewCore(
        _ snapshot: NewCoreSnapshot,
        into context: ModelContext
    ) throws -> (accountsAdded: Int, eventsAdded: Int) {
        var groupByID = try indexByID(context.fetch(FetchDescriptor<AccountGroup>()), id: \.id)
        for dto in snapshot.groups where groupByID[dto.id] == nil {
            let group = AccountGroup(id: dto.id, name: dto.name, colorHex: dto.colorHex,
                                     displayCurrency: dto.displayCurrency, order: dto.order)
            context.insert(group)
            groupByID[dto.id] = group
        }

        var accountByID = try indexByID(context.fetch(FetchDescriptor<Account>()), id: \.id)
        var accountsAdded = 0
        for dto in snapshot.accounts where accountByID[dto.id] == nil {
            let account = Account(id: dto.id, name: dto.name,
                                  kind: AccountKind(rawValue: dto.kindRaw) ?? .cash,
                                  currency: dto.currency, createdAt: dto.createdAt,
                                  includeInTotal: dto.includeInTotal, order: dto.order)
            account.archivedAt = dto.archivedAt
            account.note = dto.note
            account.cardMeta = dto.cardMeta
            account.depositMeta = dto.depositMeta
            account.loanMeta = dto.loanMeta
            account.debtMeta = dto.debtMeta
            account.marketMeta = dto.marketMeta
            account.manualAssetMeta = dto.manualAssetMeta
            if let groupID = dto.groupID { account.group = groupByID[groupID] }
            context.insert(account)
            accountByID[dto.id] = account
            accountsAdded += 1
        }

        var eventIDs = Set(try context.fetch(FetchDescriptor<AccountEvent>()).map(\.id))
        var eventsAdded = 0
        for dto in snapshot.events where !eventIDs.contains(dto.id) {
            let event = AccountEvent(
                id: dto.id, account: dto.accountID.flatMap { accountByID[$0] },
                date: dto.date, createdAt: dto.createdAt,
                type: AccountEventType(rawValue: dto.typeRaw) ?? .adjustment,
                amount: dto.amount, quantity: dto.quantity, unitPrice: dto.unitPrice,
                fxRateToBase: dto.fxRateToBase, fxProvisional: dto.fxProvisional,
                categoryID: dto.categoryID, note: dto.note, transferID: dto.transferID,
                sourceTransactionID: dto.sourceTransactionID, originalAmount: dto.originalAmount,
                originalCurrency: dto.originalCurrency, redenomRate: dto.redenomRate,
                redenomFromCurrency: dto.redenomFromCurrency
            )
            // AccountEvent.init пересчитывает dayKey из date по ТЕКУЩЕЙ таймзоне — восстанавливаем
            // сохранённый на guest ключ, иначе смена TZ задним числом переносит операцию в другой день (Т5).
            event.dayKey = dto.dayKey
            context.insert(event)
            eventIDs.insert(dto.id)
            eventsAdded += 1
        }
        return (accountsAdded, eventsAdded)
    }

    /// Индекс по id, устойчивый к возможным дублям (last-wins), без краха uniqueKeysWithValues.
    private static func indexByID<T>(_ items: [T], id: (T) -> UUID) -> [UUID: T] {
        var result: [UUID: T] = [:]
        for item in items { result[id(item)] = item }
        return result
    }
}
