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
    
    /// Однократный патч: устраняет дубли `CashflowCustomCategory` с одинаковым `categoryID`.
    /// `categoryID` генерируется как `UUID().uuidString` без `@Attribute(.unique)` — SwiftData/
    /// CloudKit не гарантирует уникальность при merge, из-за чего в сторе оказываются два разных
    /// объекта с одним `categoryID`. Это ломает `ForEach`/`LazyVGrid` по `[CashflowCategoryOption]`
    /// (`id == rawValue == "custom:<categoryID>"`) с `Fatal error: Duplicate values for key`.
    ///
    /// Намеренно НЕ добавляем `@Attribute(.unique)` в этом же релизе: пока в сторах пользователей
    /// есть дубли, лайтвейт-миграция с unique-constraint не сможет открыть контейнер вообще —
    /// краш на КАЖДОМ запуске вместо краша в конкретном экране (см. известный SwiftData-баг:
    /// добавление .unique при существующих дублях ломает автоматическую миграцию). Эта версия
    /// сначала лечит данные, unique-constraint — отдельный релиз позже, когда патч гарантированно
    /// прогонится на подавляющем большинстве установленных копий.
    ///
    /// Отдельная (не через `dedupeAll`/`runIfNeeded`) точка входа нужна, потому что
    /// `runIfNeeded` уже отработал и выставил свой флаг для существующих установок —
    /// без собственного флага это исправление никогда бы не выполнилось для них повторно.
    static func dedupeCashflowCustomCategoriesIfNeeded(modelContext: ModelContext) throws {
        let key = "migration.dedupeCashflowCustomCategories.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        try dedupeCashflowCustomCategories(modelContext: modelContext)
        if modelContext.hasChanges {
            try modelContext.save()
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    static func dedupeAll(modelContext: ModelContext) throws {
        try dedupeCards(modelContext: modelContext)
        try dedupeCredits(modelContext: modelContext)
        try dedupeInvestments(modelContext: modelContext)
        try dedupeFinanceGroups(modelContext: modelContext)
        try dedupeCashflowCustomCategories(modelContext: modelContext)

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

    // Транзакции хранят категорию как строку `"custom:<categoryID>"` (см.
    // CashflowCategoryService.customRawValue), а не как SwiftData-связь на объект
    // CashflowCustomCategory. Поэтому в отличие от dedupeFinanceGroups здесь НЕ нужно
    // перелинковывать транзакции на выжившую категорию — оба дубля имеют одинаковый
    // categoryID, значит их rawValue идентичен и остаётся валидным после удаления любого из них.
    private static func dedupeCashflowCustomCategories(modelContext: ModelContext) throws {
        let categories = try modelContext.fetch(FetchDescriptor<CashflowCustomCategory>())
        var byID: [String: CashflowCustomCategory] = [:]

        for category in categories {
            let id = category.categoryID
            guard !id.isEmpty else { continue }

            if let existing = byID[id] {
                let keep: CashflowCustomCategory
                let remove: CashflowCustomCategory
                if category.updatedAt >= existing.updatedAt {
                    keep = category
                    remove = existing
                } else {
                    keep = existing
                    remove = category
                }
                byID[id] = keep
                modelContext.delete(remove)
                AppLogger.log(.warning, category: "Integrity", "Дубликат CashflowCustomCategory categoryID=\(id) удалён (оставлен updatedAt=\(keep.updatedAt))")
            } else {
                byID[id] = category
            }
        }
    }
}
