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
                
                if let accounts = remove.accounts {
                    for account in accounts {
                        account.group = keep
                    }
                }
                
                byID[id] = keep
                modelContext.delete(remove)
            } else {
                byID[id] = group
            }
        }
    }
}

