//
//  FinanceAccountService.swift
//  millio
//
//  Создан в рамках Phase 8 декомпозиции FinanceViewModel.
//  Отвечает за загрузку, нормализацию, CRUD и кэш счетов (Card/Credit/Investment).
//

import Foundation
import SwiftData

// MARK: - AccountsLoadedPayload / CachesRebuiltPayload

struct AccountsLoadedPayload {
    let availableCards: [Card]
    let archivedCards: [Card]
    let availableCredits: [Credit]
    let archivedCredits: [Credit]
    let availableInvestments: [Investment]
    let archivedInvestments: [Investment]
}

struct CachesRebuiltPayload {
    let cardByID: [String: Card]
    let creditByID: [String: Credit]
    let investmentByID: [String: Investment]
}

// MARK: - UnderlyingAccountKind

enum UnderlyingAccountKind {
    case card
    case credit
    case investment
    case none
}

// MARK: - FinanceAccountService

@MainActor
final class FinanceAccountService {

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let ungroupedGroupName: String

    /// Провайдер текущих групп (для поиска группы счёта)
    private let groupsProvider: () -> [FinanceGroup]
    /// Провайдер следующего порядкового номера счёта в группе
    private let nextOrderProvider: (FinanceGroup) -> Int

    // MARK: - Callbacks

    /// Вернуть загруженные данные счетов в VM state
    private let onAccountsLoaded: (AccountsLoadedPayload) -> Void

    /// Вернуть перестроенные кэши доступных счетов в VM
    private let onCachesRebuilt: (CachesRebuiltPayload) -> Void

    private let onLoadAccounts: () -> Void
    private let onLoadGroups: () -> Void
    private let onUpdateUnattachedItems: () -> Void
    private let onCalculateTotal: () -> Void
    private let onScheduleGroupTotalRefresh: (String) -> Void
    private let onDismissAddAccountSheet: () -> Void

    // MARK: - Caches (all accounts, including archived)

    private(set) var allCardByID: [String: Card] = [:]
    private(set) var allCreditByID: [String: Credit] = [:]
    private(set) var allInvestmentByID: [String: Investment] = [:]

    // MARK: - Init

    init(
        modelContext: ModelContext,
        ungroupedGroupName: String,
        groupsProvider: @escaping () -> [FinanceGroup],
        nextOrderProvider: @escaping (FinanceGroup) -> Int,
        onAccountsLoaded: @escaping (AccountsLoadedPayload) -> Void,
        onCachesRebuilt: @escaping (CachesRebuiltPayload) -> Void,
        onLoadAccounts: @escaping () -> Void,
        onLoadGroups: @escaping () -> Void,
        onUpdateUnattachedItems: @escaping () -> Void,
        onCalculateTotal: @escaping () -> Void,
        onScheduleGroupTotalRefresh: @escaping (String) -> Void,
        onDismissAddAccountSheet: @escaping () -> Void
    ) {
        self.modelContext = modelContext
        self.ungroupedGroupName = ungroupedGroupName
        self.groupsProvider = groupsProvider
        self.nextOrderProvider = nextOrderProvider
        self.onAccountsLoaded = onAccountsLoaded
        self.onCachesRebuilt = onCachesRebuilt
        self.onLoadAccounts = onLoadAccounts
        self.onLoadGroups = onLoadGroups
        self.onUpdateUnattachedItems = onUpdateUnattachedItems
        self.onCalculateTotal = onCalculateTotal
        self.onScheduleGroupTotalRefresh = onScheduleGroupTotalRefresh
        self.onDismissAddAccountSheet = onDismissAddAccountSheet
    }

    // MARK: - Load

    func loadAccounts() {
        let allCards = CardCatalog.fetchAll(in: modelContext)
        let availableCards = allCards.filter { $0.archivedAt == nil }
        let archivedCards = allCards.filter { $0.archivedAt != nil }

        let creditDescriptor = FetchDescriptor<Credit>()
        let allCredits = (try? modelContext.fetch(creditDescriptor)) ?? []
        let availableCredits = allCredits.filter { $0.archivedAt == nil }
        let archivedCredits = allCredits.filter { $0.archivedAt != nil }
        normalizeCreditsIncludeInTotal(availableCredits + archivedCredits)

        let investmentDescriptor = FetchDescriptor<Investment>()
        let allInvestments = (try? modelContext.fetch(investmentDescriptor)) ?? []
        normalizeMarketAssetIdentities(allInvestments)
        normalizeMarketQuoteLookupKeys(allInvestments)
        let availableInvestments = allInvestments.filter { $0.archivedAt == nil }
        let archivedInvestments = allInvestments.filter { $0.archivedAt != nil }

        rebuildAllAccountCaches(cards: allCards, credits: allCredits, investments: allInvestments)

        let cardByIDAvail = Dictionary(uniqueKeysWithValues: availableCards.map { ($0.cardUniqueID, $0) })
        let creditByIDAvail = Dictionary(uniqueKeysWithValues: availableCredits.map { ($0.creditUniqueID, $0) })
        let investByIDAvail = Dictionary(uniqueKeysWithValues: availableInvestments.map { ($0.investmentUniqueID, $0) })

        onAccountsLoaded(AccountsLoadedPayload(
            availableCards: availableCards,
            archivedCards: archivedCards,
            availableCredits: availableCredits,
            archivedCredits: archivedCredits,
            availableInvestments: availableInvestments,
            archivedInvestments: archivedInvestments
        ))
        onCachesRebuilt(CachesRebuiltPayload(
            cardByID: cardByIDAvail,
            creditByID: creditByIDAvail,
            investmentByID: investByIDAvail
        ))

        cleanupInvalidFinanceAccounts()

        CardManager.shared.setup(modelContext: modelContext)
        CreditManager.shared.setup(modelContext: modelContext)
        InvestmentManager.shared.setup(modelContext: modelContext)

        onUpdateUnattachedItems()
    }

    // MARK: - Normalize

    private func normalizeCreditsIncludeInTotal(_ credits: [Credit]) {
        var requiresSave = false
        for credit in credits where !credit.includeInTotal {
            credit.includeInTotal = true
            credit.updatedAt = Date()
            requiresSave = true
        }
        if requiresSave {
            do {
                try modelContext.save()
            } catch {
                AppLogger.log(.error, category: "Finance", "Failed to normalize credits includeInTotal: \(error.localizedDescription)")
            }
        }
    }

    private func normalizeMarketAssetIdentities(_ investments: [Investment]) {
        var requiresSave = false
        let assetCatalogStore = AssetCatalogStore(modelContext: modelContext)
        for investment in investments where investment.isMarketPriced {
            requiresSave = assetCatalogStore.migrateInvestmentIfNeeded(investment) || requiresSave
        }
        guard requiresSave else { return }
        do {
            try modelContext.save()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to normalize market asset identities: \(error.localizedDescription)")
        }
    }

    private func normalizeMarketQuoteLookupKeys(_ investments: [Investment]) {
        var requiresSave = false
        for investment in investments where investment.isMarketPriced {
            let existingLookupKey = investment.marketQuoteLookupKey?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            if !existingLookupKey.isEmpty { continue }

            let rawSymbol = investment.marketSymbol?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            guard !rawSymbol.isEmpty else { continue }
            if investment.marketExchange?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false &&
                rawSymbol.hasSuffix(".US") {
                continue
            }

            let normalizedKey = MarketInstrumentIdentity.canonicalQuoteLookupKey(
                symbol: rawSymbol,
                exchange: investment.marketExchange
            )
            if !normalizedKey.isEmpty, investment.marketQuoteLookupKey != normalizedKey {
                investment.marketQuoteLookupKey = normalizedKey
                requiresSave = true
            }
        }
        guard requiresSave else { return }
        do {
            try modelContext.save()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to normalize market quote lookup keys: \(error.localizedDescription)")
        }
    }

    // MARK: - Caches

    private func rebuildAllAccountCaches(cards: [Card], credits: [Credit], investments: [Investment]) {
        allCardByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.cardUniqueID, $0) })
        allCreditByID = Dictionary(uniqueKeysWithValues: credits.map { ($0.creditUniqueID, $0) })
        allInvestmentByID = Dictionary(uniqueKeysWithValues: investments.map { ($0.investmentUniqueID, $0) })
    }

    // MARK: - Cleanup

    private func cleanupInvalidFinanceAccounts() {
        let descriptor = FetchDescriptor<FinanceAccount>()
        guard let accounts = try? modelContext.fetch(descriptor) else { return }

        var didMutate = false
        var removedCount = 0
        var dedupedCount = 0
        var reassignedToUngroupedCount = 0
        var createdMissingCardLinksCount = 0
        var createdMissingCreditLinksCount = 0
        var createdMissingInvestmentLinksCount = 0

        var ungroupedGroup: FinanceGroup?
        func resolveUngroupedGroup() -> FinanceGroup {
            if let ungroupedGroup { return ungroupedGroup }
            let group = FinanceSystemGroups.ensureUngroupedGroup(in: modelContext)
            ungroupedGroup = group
            return group
        }

        var linkedCardIDs = Set(accounts.compactMap { account in
            account.accountType == .card ? account.accountID : nil
        })
        var linkedCreditIDs = Set(accounts.compactMap { account in
            account.accountType == .credit ? account.accountID : nil
        })
        var linkedInvestmentIDs = Set(accounts.compactMap { account in
            account.accountType == .investment ? account.accountID : nil
        })

        let groupedAccounts = Dictionary(
            grouping: accounts,
            by: { "\($0.accountTypeRaw)|\($0.accountID)" }
        )

        for duplicates in groupedAccounts.values where duplicates.count > 1 {
            let survivor = duplicates.max { lhs, rhs in
                financeAccountDeduplicationRank(lhs) < financeAccountDeduplicationRank(rhs)
            }
            for duplicate in duplicates where duplicate.persistentModelID != survivor?.persistentModelID {
                modelContext.delete(duplicate)
                dedupedCount += 1
                didMutate = true
            }
        }

        for account in accounts {
            if account.modelContext == nil { continue }
            if account.group == nil {
                account.group = resolveUngroupedGroup()
                account.updatedAt = Date()
                reassignedToUngroupedCount += 1
                didMutate = true
            }
            switch account.accountType {
            case .card:
                if allCardByID[account.accountID] == nil {
                    modelContext.delete(account)
                    removedCount += 1
                    didMutate = true
                }
            case .credit:
                if allCreditByID[account.accountID] == nil {
                    modelContext.delete(account)
                    removedCount += 1
                    didMutate = true
                }
            case .investment:
                if allInvestmentByID[account.accountID] == nil {
                    modelContext.delete(account)
                    removedCount += 1
                    didMutate = true
                }
            }
        }

        for card in allCardByID.values where card.archivedAt == nil {
            guard !linkedCardIDs.contains(card.cardUniqueID) else { continue }
            let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
            account.group = resolveUngroupedGroup()
            modelContext.insert(account)
            linkedCardIDs.insert(card.cardUniqueID)
            createdMissingCardLinksCount += 1
            didMutate = true
        }

        for credit in allCreditByID.values where credit.archivedAt == nil {
            guard !linkedCreditIDs.contains(credit.creditUniqueID) else { continue }
            let account = FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID)
            account.group = resolveUngroupedGroup()
            modelContext.insert(account)
            linkedCreditIDs.insert(credit.creditUniqueID)
            createdMissingCreditLinksCount += 1
            didMutate = true
        }

        for investment in allInvestmentByID.values where investment.archivedAt == nil {
            guard !linkedInvestmentIDs.contains(investment.investmentUniqueID) else { continue }
            let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
            account.group = resolveUngroupedGroup()
            modelContext.insert(account)
            linkedInvestmentIDs.insert(investment.investmentUniqueID)
            createdMissingInvestmentLinksCount += 1
            didMutate = true
        }

        guard didMutate else { return }

        do {
            try modelContext.save()
            if dedupedCount > 0 {
                AppLogger.log(.info, category: "Finance", "Removed \(dedupedCount) duplicate finance account links")
            }
            if removedCount > 0 {
                AppLogger.log(.info, category: "Finance", "Removed \(removedCount) invalid finance account links")
            }
            if reassignedToUngroupedCount > 0 {
                AppLogger.log(.info, category: "Finance", "Reassigned \(reassignedToUngroupedCount) finance account links to ungrouped group")
            }
            if createdMissingCardLinksCount > 0 {
                AppLogger.log(.info, category: "Finance", "Created \(createdMissingCardLinksCount) missing card finance account links")
            }
            if createdMissingCreditLinksCount > 0 {
                AppLogger.log(.info, category: "Finance", "Created \(createdMissingCreditLinksCount) missing credit finance account links")
            }
            if createdMissingInvestmentLinksCount > 0 {
                AppLogger.log(.info, category: "Finance", "Created \(createdMissingInvestmentLinksCount) missing investment finance account links")
            }
            onLoadGroups()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to cleanup finance accounts: \(error.localizedDescription)")
        }
    }

    private func financeAccountDeduplicationRank(_ account: FinanceAccount) -> (Int, Int, Date, Date) {
        let isGrouped = account.group != nil ? 1 : 0
        let isNonSystemGroup: Int = {
            guard let group = account.group else { return 0 }
            return group.name == ungroupedGroupName ? 0 : 1
        }()
        return (isNonSystemGroup, isGrouped, account.updatedAt, account.createdAt)
    }

    // MARK: - CRUD

    func addAccountToGroup(accountType: FinanceAccountType, accountID: String, group: FinanceGroup?) {
        let targetGroup = group ?? FinanceSystemGroups.ensureUngroupedGroup(in: modelContext)
        let nextOrder = nextOrderProvider(targetGroup)

        let allAccountsDescriptor = FetchDescriptor<FinanceAccount>()
        if let allAccounts = try? modelContext.fetch(allAccountsDescriptor) {
            let existingAccount = allAccounts.first { account in
                account.accountType == accountType && account.accountID == accountID
            }
            if let existing = existingAccount {
                existing.group = targetGroup
                if targetGroup.usesManualAccountOrdering {
                    existing.order = nextOrder
                }
                existing.updatedAt = Date()
            } else {
                let account = FinanceAccount(accountType: accountType, accountID: accountID)
                account.group = targetGroup
                account.order = nextOrder
                modelContext.insert(account)
            }
        } else {
            let account = FinanceAccount(accountType: accountType, accountID: accountID)
            account.group = targetGroup
            account.order = nextOrder
            modelContext.insert(account)
        }

        do {
            try modelContext.save()
            onLoadAccounts()
            onLoadGroups()
            onCalculateTotal()
            onScheduleGroupTotalRefresh(targetGroup.groupUniqueID)
            onDismissAddAccountSheet()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to add account: \(error.localizedDescription)")
        }
    }

    @discardableResult
    func removeAccountFromGroup(_ account: FinanceAccount) -> UnderlyingAccountKind {
        let accountGroup = groupsProvider().first { group in
            group.accounts?.contains(where: { $0.accountUniqueID == account.accountUniqueID }) ?? false
        }

        let kind = updateUnderlyingArchiveState(for: account, archivedAt: Date())
        account.updatedAt = Date()

        do {
            try modelContext.save()
            onLoadGroups()
            onCalculateTotal()
            if let groupID = accountGroup?.groupUniqueID {
                onScheduleGroupTotalRefresh(groupID)
            }
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to remove account: \(error.localizedDescription)")
        }
        return kind
    }

    @discardableResult
    func deleteAccountPermanently(_ account: FinanceAccount) -> UnderlyingAccountKind {
        let accountGroup = groupsProvider().first { group in
            group.accounts?.contains(where: { $0.accountUniqueID == account.accountUniqueID }) ?? false
        }
        let kind = updateUnderlyingArchiveState(for: account, archivedAt: Date())

        do {
            try modelContext.save()
            onLoadGroups()
            onCalculateTotal()
            if let groupID = accountGroup?.groupUniqueID {
                onScheduleGroupTotalRefresh(groupID)
            }
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to delete account permanently: \(error.localizedDescription)")
        }
        return kind
    }

    func restoreArchivedAccountToGroup(accountType: FinanceAccountType, accountID: String, group: FinanceGroup?) {
        updateUnderlyingArchiveState(accountType: accountType, accountID: accountID, archivedAt: nil)
        addAccountToGroup(accountType: accountType, accountID: accountID, group: group)
    }

    // MARK: - Archive State

    @discardableResult
    func updateUnderlyingArchiveState(for account: FinanceAccount, archivedAt: Date?) -> UnderlyingAccountKind {
        updateUnderlyingArchiveState(accountType: account.accountType, accountID: account.accountID, archivedAt: archivedAt)
    }

    @discardableResult
    func updateUnderlyingArchiveState(accountType: FinanceAccountType, accountID: String, archivedAt: Date?) -> UnderlyingAccountKind {
        switch accountType {
        case .card:
            let card = allCardByID[accountID] ?? ((try? modelContext.fetch(FetchDescriptor<Card>())) ?? []).first { $0.cardUniqueID == accountID }
            if let card {
                card.archivedAt = archivedAt
                card.updatedAt = Date()
            }
            return .card
        case .credit:
            let credit = allCreditByID[accountID] ?? ((try? modelContext.fetch(FetchDescriptor<Credit>())) ?? []).first { $0.creditUniqueID == accountID }
            if let credit {
                credit.archivedAt = archivedAt
                credit.updatedAt = Date()
            }
            return .credit
        case .investment:
            let investment = allInvestmentByID[accountID] ?? ((try? modelContext.fetch(FetchDescriptor<Investment>())) ?? []).first { $0.investmentUniqueID == accountID }
            if let investment {
                investment.archivedAt = archivedAt
                investment.updatedAt = Date()
            }
            return .investment
        }
    }
}
