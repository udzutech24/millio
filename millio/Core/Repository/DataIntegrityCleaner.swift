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
    /// Намеренно БЕЗ одноразового флага (в отличие от `runIfNeeded`/`archiveZeroQuantity...`):
    /// холодный старт всегда создаёт первый `DIContainer` на guest-сторе (`initialScope = .guest`
    /// в `millioApp`, ДО `restoreSession`/`synchronizeDataScope`), и только потом — второй
    /// `DIContainer` на реальном user-сторе через `rebindDataScope`. Общий на весь app флаг сгорал
    /// бы на почти пустом guest-сторе и реальный user-стор никогда бы не дочищался. Фетч + группировка
    /// по `categoryID` дешёвы при отсутствии дублей, поэтому безопаснее и проще (KISS) гонять патч
    /// на КАЖДОМ `DIContainer.create()` для любого стора, чем плюмбить per-scope идентификатор через
    /// весь путь создания контейнера.
    static func dedupeCashflowCustomCategoriesOnLaunch(modelContext: ModelContext) throws {
        try dedupeCashflowCustomCategories(modelContext: modelContext)
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    /// Однократный патч (архитектурно — на каждый запуск, без флага): устраняет дубли
    /// `CashbackCustomCategory` с одинаковым `categoryID`. Идентичная уязвимость
    /// `CashflowCustomCategory` (см. `dedupeCashflowCustomCategoriesOnLaunch` выше) —
    /// `categoryID` генерируется как `UUID().uuidString` без `@Attribute(.unique)`,
    /// SwiftData/CloudKit не гарантирует уникальность при merge/restore. Ломает
    /// `ForEach`/`LazyVGrid` по `[CashbackCategoryOption]` (`id == rawValue ==
    /// "custom:<categoryID>"`) тем же `Fatal error: Duplicate values for key`.
    ///
    /// Намеренно БЕЗ одноразового флага — по той же причине, что и у Cashflow-версии:
    /// холодный старт создаёт первый `DIContainer` на guest-сторе ДО restoreSession,
    /// общий флаг сгорел бы там и реальный user-стор никогда бы не дочищался.
    static func dedupeCashbackCustomCategoriesOnLaunch(modelContext: ModelContext) throws {
        try dedupeCashbackCustomCategories(modelContext: modelContext)
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    /// Однократный патч (архитектурно — на каждый запуск, без флага): устраняет дубли
    /// `BudgetCategoryLimit` с одинаковым ключом `(budgetID, categoryRawValue)`. `BudgetPlan.budgetID`
    /// генерируется как `UUID().uuidString` без `@Attribute(.unique)`, а сам `BudgetCategoryLimit`
    /// не имеет уникального ограничения вовсе — CloudKit-merge/восстановление бэкапа может создать
    /// два лимита на одну и ту же категорию внутри одного бюджетного плана. Такие дубли роняют
    /// `Dictionary(uniqueKeysWithValues:)` в `CashflowViewModel+History.swift`
    /// (`monthlyBudgetSummary`, `previousMonthlyBudgetSuggestion`, `saveBudgetConfiguration`) с тем же
    /// `Fatal error: Duplicate values for key`, что уже чинили для custom-категорий.
    ///
    /// Ключ уникальности — `(budgetID, categoryRawValue)`, а не просто `categoryRawValue`: один и тот
    /// же raw value категории существует независимо в разных бюджетных планах (разные месяцы/периоды
    /// и expense/income — у каждого своя запись `BudgetPlan` со своим `budgetID`), это не дубли.
    /// `categoryKindRaw` в ключ не добавляем — он не самостоятельная сущность, а атрибут самого
    /// `BudgetPlan` (`fetchBudgetCategoryLimits(for:)` уже отбирает лимиты одного `budgetID`, значит
    /// внутри группы kind у всех дублей совпадает по построению).
    ///
    /// Намеренно БЕЗ одноразового флага — по той же причине, что и у Cashflow/Cashback-версий:
    /// холодный старт создаёт первый `DIContainer` на guest-сторе ДО restoreSession, общий флаг
    /// сгорел бы там и реальный user-стор никогда бы не дочищался.
    static func dedupeBudgetCategoryLimitsOnLaunch(modelContext: ModelContext) throws {
        try dedupeBudgetCategoryLimits(modelContext: modelContext)
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }

    static func dedupeAll(modelContext: ModelContext) throws {
        try dedupeCards(modelContext: modelContext)
        try dedupeCredits(modelContext: modelContext)
        try dedupeInvestments(modelContext: modelContext)
        try dedupeFinanceGroups(modelContext: modelContext)
        try dedupeCashflowCustomCategories(modelContext: modelContext)
        try dedupeCashbackCustomCategories(modelContext: modelContext)
        try dedupeBudgetCategoryLimits(modelContext: modelContext)

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

    // Транзакции хранят категорию как строку `"custom:<categoryID>"` (см.
    // CashbackViewModel.customRawValue), а не как SwiftData-связь на объект
    // CashbackCustomCategory. Релинковка не нужна по той же причине, что и у
    // dedupeCashflowCustomCategories — оба дубля имеют одинаковый categoryID.
    private static func dedupeCashbackCustomCategories(modelContext: ModelContext) throws {
        let categories = try modelContext.fetch(FetchDescriptor<CashbackCustomCategory>())
        var byID: [String: CashbackCustomCategory] = [:]

        for category in categories {
            let id = category.categoryID
            guard !id.isEmpty else { continue }

            if let existing = byID[id] {
                let keep: CashbackCustomCategory
                let remove: CashbackCustomCategory
                if category.updatedAt >= existing.updatedAt {
                    keep = category
                    remove = existing
                } else {
                    keep = existing
                    remove = category
                }
                byID[id] = keep
                modelContext.delete(remove)
                AppLogger.log(.warning, category: "Integrity", "Дубликат CashbackCustomCategory categoryID=\(id) удалён (оставлен updatedAt=\(keep.updatedAt))")
            } else {
                byID[id] = category
            }
        }
    }

    // Ключ (budgetID, categoryRawValue) — см. комментарий на dedupeBudgetCategoryLimitsOnLaunch.
    // Релинковка не нужна: транзакции ссылаются на категорию по её собственному rawValue
    // (CashflowCategoryService/CashbackViewModel customRawValue), а не через связь на BudgetCategoryLimit.
    private static func dedupeBudgetCategoryLimits(modelContext: ModelContext) throws {
        let limits = try modelContext.fetch(FetchDescriptor<BudgetCategoryLimit>())
        var byKey: [String: BudgetCategoryLimit] = [:]

        for limit in limits {
            guard !limit.budgetID.isEmpty, !limit.categoryRawValue.isEmpty else { continue }
            let key = "\(limit.budgetID)|\(limit.categoryRawValue)"

            if let existing = byKey[key] {
                let keep: BudgetCategoryLimit
                let remove: BudgetCategoryLimit
                if limit.updatedAt >= existing.updatedAt {
                    keep = limit
                    remove = existing
                } else {
                    keep = existing
                    remove = limit
                }
                byKey[key] = keep
                modelContext.delete(remove)
                AppLogger.log(.warning, category: "Integrity", "Дубликат BudgetCategoryLimit budgetID=\(limit.budgetID) categoryRawValue=\(limit.categoryRawValue) удалён (оставлен updatedAt=\(keep.updatedAt))")
            } else {
                byKey[key] = limit
            }
        }
    }
}
