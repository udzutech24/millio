import Foundation
import SwiftData

/// Чтение стора в Sendable-снимки (Track B, B2b). Nonisolated-статики — вызываются на
/// executor'е @ModelActor'а (guest reader / user worker), поэтому корректно работают с его context.
enum ScopeMergeReader {

    // Имена моделей — ключи для сопряжения guest/user сигналов в детекторе.
    enum Model {
        static let card = "Card"
        static let credit = "Credit"
        static let investment = "Investment"
        static let financeGroup = "FinanceGroup"
        static let financeAccount = "FinanceAccount"
        static let transaction = "CashflowTransaction"
        static let cashback = "Cashback"
        static let cashbackCustomCategory = "CashbackCustomCategory"
        static let userSubscription = "UserSubscription"
        static let budgetPlan = "BudgetPlan"
        static let budgetCategoryLimit = "BudgetCategoryLimit"
        static let cashflowCustomCategory = "CashflowCustomCategory"
        static let cashflowSystemCategoryOverride = "CashflowSystemCategoryOverride"
        static let account = "Account"
        static let accountEvent = "AccountEvent"
        static let accountGroup = "AccountGroup"
    }

    // MARK: - Снимок стороны (counts / watermarks / lineage / tx-fingerprints)

    static func snapshot(context: ModelContext) throws -> ScopeSideSnapshot {
        var counts: [String: Int] = [:]
        var watermarks: [String: Date] = [:]
        var identity: Set<ScopeFingerprint> = []
        var txByFP: [ScopeFingerprint: Int] = [:]

        let cards = try context.fetch(FetchDescriptor<Card>())
        counts[Model.card] = cards.count
        watermarks[Model.card] = cards.map(\.updatedAt).max()
        identity.formUnion(cards.map(\.cardUniqueID).filter { !$0.isEmpty })

        let credits = try context.fetch(FetchDescriptor<Credit>())
        counts[Model.credit] = credits.count
        watermarks[Model.credit] = credits.map(\.updatedAt).max()
        identity.formUnion(credits.map(\.creditUniqueID).filter { !$0.isEmpty })

        let investments = try context.fetch(FetchDescriptor<Investment>())
        counts[Model.investment] = investments.count
        watermarks[Model.investment] = investments.map(\.updatedAt).max()
        identity.formUnion(investments.map(\.investmentUniqueID).filter { !$0.isEmpty })

        let groups = try context.fetch(FetchDescriptor<FinanceGroup>())
        counts[Model.financeGroup] = groups.count
        watermarks[Model.financeGroup] = groups.map(\.updatedAt).max()
        identity.formUnion(groups.map(\.groupUniqueID).filter { !$0.isEmpty })

        let accounts = try context.fetch(FetchDescriptor<FinanceAccount>())
        counts[Model.financeAccount] = accounts.count
        watermarks[Model.financeAccount] = accounts.map(\.updatedAt).max()
        identity.formUnion(accounts.map(\.accountUniqueID).filter { !$0.isEmpty })

        let transactions = try context.fetch(FetchDescriptor<CashflowTransaction>())
        counts[Model.transaction] = transactions.count
        watermarks[Model.transaction] = transactions.map(\.updatedAt).max()
        for tx in transactions {
            let fp = tx.transactionUniqueID
            identity.insert(fp)
            txByFP[fp, default: 0] += 1
        }

        // Keyless-модели: только count + watermark (для детектора). В lineage не участвуют.
        try countKeyless(context, &counts, &watermarks)

        // New-core: count + watermark (updatedAt нет — берём createdAt как водяной знак присутствия).
        let coreAccounts = try context.fetch(FetchDescriptor<Account>())
        counts[Model.account] = coreAccounts.count
        watermarks[Model.account] = coreAccounts.map(\.createdAt).max()
        let coreEvents = try context.fetch(FetchDescriptor<AccountEvent>())
        counts[Model.accountEvent] = coreEvents.count
        watermarks[Model.accountEvent] = coreEvents.map(\.createdAt).max()
        let coreGroups = try context.fetch(FetchDescriptor<AccountGroup>())
        counts[Model.accountGroup] = coreGroups.count

        let total = counts.values.reduce(0, +)
        return ScopeSideSnapshot(
            modelCounts: counts,
            modelWatermarks: watermarks,
            totalEntities: total,
            identityFingerprints: identity,
            transactionCountsByFingerprint: txByFP
        )
    }

    private static func countKeyless(
        _ context: ModelContext,
        _ counts: inout [String: Int],
        _ watermarks: inout [String: Date]
    ) throws {
        let cashbacks = try context.fetch(FetchDescriptor<Cashback>())
        counts[Model.cashback] = cashbacks.count
        watermarks[Model.cashback] = cashbacks.map(\.updatedAt).max()

        let cashbackCats = try context.fetch(FetchDescriptor<CashbackCustomCategory>())
        counts[Model.cashbackCustomCategory] = cashbackCats.count
        watermarks[Model.cashbackCustomCategory] = cashbackCats.map(\.updatedAt).max()

        let subs = try context.fetch(FetchDescriptor<UserSubscription>())
        counts[Model.userSubscription] = subs.count
        watermarks[Model.userSubscription] = subs.map(\.updatedAt).max()

        let plans = try context.fetch(FetchDescriptor<BudgetPlan>())
        counts[Model.budgetPlan] = plans.count
        watermarks[Model.budgetPlan] = plans.map(\.updatedAt).max()

        let limits = try context.fetch(FetchDescriptor<BudgetCategoryLimit>())
        counts[Model.budgetCategoryLimit] = limits.count
        watermarks[Model.budgetCategoryLimit] = limits.map(\.updatedAt).max()

        let cfCats = try context.fetch(FetchDescriptor<CashflowCustomCategory>())
        counts[Model.cashflowCustomCategory] = cfCats.count
        watermarks[Model.cashflowCustomCategory] = cfCats.map(\.updatedAt).max()

        let overrides = try context.fetch(FetchDescriptor<CashflowSystemCategoryOverride>())
        counts[Model.cashflowSystemCategoryOverride] = overrides.count
        watermarks[Model.cashflowSystemCategoryOverride] = overrides.map(\.updatedAt).max()
    }

    /// Лёгкие по-модельные счётчики (fetchCount, без материализации) — для pre/post merge и sanity.
    static func counts(context: ModelContext) throws -> [String: Int] {
        [
            Model.card: try context.fetchCount(FetchDescriptor<Card>()),
            Model.credit: try context.fetchCount(FetchDescriptor<Credit>()),
            Model.investment: try context.fetchCount(FetchDescriptor<Investment>()),
            Model.financeGroup: try context.fetchCount(FetchDescriptor<FinanceGroup>()),
            Model.financeAccount: try context.fetchCount(FetchDescriptor<FinanceAccount>()),
            Model.transaction: try context.fetchCount(FetchDescriptor<CashflowTransaction>()),
            Model.cashback: try context.fetchCount(FetchDescriptor<Cashback>()),
            Model.cashbackCustomCategory: try context.fetchCount(FetchDescriptor<CashbackCustomCategory>()),
            Model.userSubscription: try context.fetchCount(FetchDescriptor<UserSubscription>()),
            Model.budgetPlan: try context.fetchCount(FetchDescriptor<BudgetPlan>()),
            Model.budgetCategoryLimit: try context.fetchCount(FetchDescriptor<BudgetCategoryLimit>()),
            Model.cashflowCustomCategory: try context.fetchCount(FetchDescriptor<CashflowCustomCategory>()),
            Model.cashflowSystemCategoryOverride: try context.fetchCount(FetchDescriptor<CashflowSystemCategoryOverride>()),
            Model.account: try context.fetchCount(FetchDescriptor<Account>()),
            Model.accountEvent: try context.fetchCount(FetchDescriptor<AccountEvent>()),
            Model.accountGroup: try context.fetchCount(FetchDescriptor<AccountGroup>())
        ]
    }

    // MARK: - Чтение new-core в DTO

    static func readNewCore(context: ModelContext) throws -> NewCoreSnapshot {
        let groups = try context.fetch(FetchDescriptor<AccountGroup>()).map {
            AccountGroupDTO(id: $0.id, name: $0.name, colorHex: $0.colorHex,
                            displayCurrency: $0.displayCurrency, order: $0.order)
        }
        let accounts = try context.fetch(FetchDescriptor<Account>()).map { account in
            AccountDTO(
                id: account.id, name: account.name, kindRaw: account.kindRaw, currency: account.currency,
                createdAt: account.createdAt, archivedAt: account.archivedAt,
                includeInTotal: account.includeInTotal, note: account.note, order: account.order,
                groupID: account.group?.id,
                cardMeta: account.cardMeta, depositMeta: account.depositMeta, loanMeta: account.loanMeta,
                debtMeta: account.debtMeta, marketMeta: account.marketMeta, manualAssetMeta: account.manualAssetMeta
            )
        }
        let events = try context.fetch(FetchDescriptor<AccountEvent>()).map { event in
            AccountEventDTO(
                id: event.id, accountID: event.account?.id, date: event.date, createdAt: event.createdAt,
                dayKey: event.dayKey, typeRaw: event.typeRaw, amount: event.amount, quantity: event.quantity,
                unitPrice: event.unitPrice, fxRateToBase: event.fxRateToBase, fxProvisional: event.fxProvisional,
                categoryID: event.categoryID, note: event.note, transferID: event.transferID,
                sourceTransactionID: event.sourceTransactionID, originalAmount: event.originalAmount,
                originalCurrency: event.originalCurrency, redenomRate: event.redenomRate,
                redenomFromCurrency: event.redenomFromCurrency
            )
        }
        return NewCoreSnapshot(groups: groups, accounts: accounts, events: events)
    }

    static func readGuestInput(context: ModelContext) throws -> GuestMergeInput {
        let legacyData = try DataRepository.exportAllData(from: context)
        let newCore = try readNewCore(context: context)
        let snap = try snapshot(context: context)
        return GuestMergeInput(legacyData: legacyData, newCore: newCore, snapshot: snap)
    }
}
