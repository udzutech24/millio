import Foundation
import SwiftData

@MainActor
enum DataIntegrityCleaner {
    static func runIfNeeded(modelContext: ModelContext) throws {
        let key = "data_integrity_cleanup_v1"
        if UserDefaults.standard.bool(forKey: key) {
            return
        }
        try dedupeAll(modelContext: modelContext)
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Откат плохой миграции: разархивирует вклады и депозиты, которые были
    /// ошибочно заархивированы в archiveZeroQuantityInvestmentsIfNeeded из-за
    /// отсутствия проверки isMarketPriced. Сбрасывает флаг исходной миграции,
    /// чтобы она перезапустилась с исправленным условием.
    ///
    /// - Parameter scopeIdentifier: имя store (например "millio_guest" или "millio_user_<hash>").
    ///   Включается в ключ UserDefaults, чтобы миграция выполнялась независимо
    ///   для guest-store и каждого user-store.
    static func revertBadArchiveMigrationIfNeeded(modelContext: ModelContext, scopeIdentifier: String) throws {
        let revertKey = "migration.revertBadArchive.v1.\(scopeIdentifier)"
        guard !UserDefaults.standard.bool(forKey: revertKey) else { return }

        // Находим все записи, которые были заархивированы, но не являются
        // рыночными активами (stocks/crypto). isMarketPriced — computed property,
        // поэтому фильтруем в памяти после fetch.
        var descriptor = FetchDescriptor<Investment>()
        descriptor.predicate = #Predicate { $0.archivedAt != nil }
        let archived = try modelContext.fetch(descriptor)

        let now = Date()
        var reverted = 0
        for investment in archived where !investment.isMarketPriced {
            investment.archivedAt = nil
            reverted += 1
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }

        // Сбрасываем флаг исходной миграции для этого scope: она должна перезапуститься
        // уже с исправленным условием (только isMarketPriced == true).
        UserDefaults.standard.set(false, forKey: "migration.archiveZeroQuantityInvestments.v1.\(scopeIdentifier)")
        UserDefaults.standard.set(true, forKey: revertKey)

        AppLogger.log(.info, category: "Integrity", "revertBadArchiveMigration [\(scopeIdentifier)]: восстановлено \(reverted) вкладов/депозитов (ts=\(now))")
    }

    /// Однократный патч: архивирует инвестиционные позиции с нулевым количеством,
    /// которые были проданы до добавления авто-архивации в executeInvestmentOrder.
    /// Затрагивает только рыночные активы (stocks/crypto), вклады и депозиты пропускаются.
    ///
    /// - Parameter scopeIdentifier: имя store (например "millio_guest" или "millio_user_<hash>").
    ///   Включается в ключ UserDefaults, чтобы миграция выполнялась независимо
    ///   для guest-store и каждого user-store.
    static func archiveZeroQuantityInvestmentsIfNeeded(modelContext: ModelContext, scopeIdentifier: String) throws {
        let key = "migration.archiveZeroQuantityInvestments.v1.\(scopeIdentifier)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        var descriptor = FetchDescriptor<Investment>()
        descriptor.predicate = #Predicate { $0.archivedAt == nil }
        let candidates = try modelContext.fetch(descriptor)

        // Повторяем логику executeInvestmentOrder: позиция полностью продана
        // если marketQuantity == nil || == 0. Добавлена проверка isMarketPriced —
        // вклады/депозиты имеют marketQuantity == nil, но архивировать их нельзя.
        let now = Date()
        var patched = 0
        for investment in candidates where investment.isMarketPriced && (investment.marketQuantity ?? 0) == 0 {
            investment.archivedAt = now
            patched += 1
        }

        if modelContext.hasChanges {
            try modelContext.save()
        }
        UserDefaults.standard.set(true, forKey: key)

        if patched > 0 {
            AppLogger.log(.info, category: "Integrity", "archiveZeroQuantityInvestments [\(scopeIdentifier)]: архивировано \(patched) позиций")
        }
    }
    
    static func dedupeAll(modelContext: ModelContext) throws {
        try dedupeCards(modelContext: modelContext)
        try dedupeCredits(modelContext: modelContext)
        try dedupeInvestments(modelContext: modelContext)
        try dedupeFinanceGroups(modelContext: modelContext)
        
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
    
    private static func dedupeCards(modelContext: ModelContext) throws {
        let cards = try modelContext.fetch(FetchDescriptor<Card>())
        var byID: [String: Card] = [:]
        
        for card in cards {
            let id = card.cardUniqueID
            guard !id.isEmpty else { continue }
            
            if let existing = byID[id] {
                let keep: Card
                let remove: Card
                if card.updatedAt >= existing.updatedAt {
                    keep = card
                    remove = existing
                } else {
                    keep = existing
                    remove = card
                }
                byID[id] = keep
                modelContext.delete(remove)
            } else {
                byID[id] = card
            }
        }
    }
    
    private static func dedupeCredits(modelContext: ModelContext) throws {
        let credits = try modelContext.fetch(FetchDescriptor<Credit>())
        var byID: [String: Credit] = [:]
        
        for credit in credits {
            let id = credit.creditUniqueID
            guard !id.isEmpty else { continue }
            
            if let existing = byID[id] {
                let keep: Credit
                let remove: Credit
                if credit.updatedAt >= existing.updatedAt {
                    keep = credit
                    remove = existing
                } else {
                    keep = existing
                    remove = credit
                }
                byID[id] = keep
                modelContext.delete(remove)
            } else {
                byID[id] = credit
            }
        }
    }
    
    private static func dedupeInvestments(modelContext: ModelContext) throws {
        let investments = try modelContext.fetch(FetchDescriptor<Investment>())
        var byID: [String: Investment] = [:]
        
        for investment in investments {
            let id = investment.investmentUniqueID
            guard !id.isEmpty else { continue }
            
            if let existing = byID[id] {
                let keep: Investment
                let remove: Investment
                if investment.updatedAt >= existing.updatedAt {
                    keep = investment
                    remove = existing
                } else {
                    keep = existing
                    remove = investment
                }
                byID[id] = keep
                modelContext.delete(remove)
            } else {
                byID[id] = investment
            }
        }
    }
    
    private static func dedupeFinanceGroups(modelContext: ModelContext) throws {
        let groups = try modelContext.fetch(FetchDescriptor<FinanceGroup>())
        let accounts = try modelContext.fetch(FetchDescriptor<FinanceAccount>())
        var byID: [String: FinanceGroup] = [:]
        
        for group in groups {
            let id = group.groupUniqueID
            guard !id.isEmpty else { continue }
            
            if let existing = byID[id] {
                let keep: FinanceGroup
                let remove: FinanceGroup
                if group.updatedAt >= existing.updatedAt {
                    keep = group
                    remove = existing
                } else {
                    keep = existing
                    remove = group
                }
                
                for account in accounts where account.group?.persistentModelID == remove.persistentModelID {
                    account.group = keep
                }
                
                byID[id] = keep
                modelContext.delete(remove)
            } else {
                byID[id] = group
            }
        }
    }
}
