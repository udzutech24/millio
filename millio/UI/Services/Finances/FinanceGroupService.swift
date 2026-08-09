//
//  FinanceGroupService.swift
//  millio
//
//  Создан в рамках Phase 5 декомпозиции FinanceViewModel.
//  [Ф5c.7 contract] Флип на core-типы: CRUD групп теперь на `AccountGroup`/`Account`.
//  Легаси-`FinanceGroup` синхронизируется ПО ИМЕНИ как fallback-хвост (не первичный источник) —
//  см. `syncLegacyGroup`, инвариант 9 §2.1 плана 5c.7.
//

import Foundation
import SwiftData

// MARK: - FinanceGroupService

@MainActor
final class FinanceGroupService {

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let saveChanges: (ModelContext) throws -> Void

    /// Провайдер текущих core-групп из FinanceState
    private let groupsProvider: () -> [AccountGroup]

    /// Callback: загрузить группы в VM
    private let onLoadGroups: () -> Void
    /// Callback: загрузить счета в VM
    private let onLoadAccounts: () -> Void
    /// Callback: пересчитать суммарный итог
    private let onCalculateTotal: () -> Void
    /// Callback: запланировать обновление итога группы
    private let onScheduleGroupTotalRefresh: (String, String?) -> Void
    /// Callback: закрыть редактор группы в state
    private let onDismissGroupEditor: () -> Void

    // MARK: - Init

    init(
        modelContext: ModelContext,
        saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() },
        groupsProvider: @escaping () -> [AccountGroup],
        onLoadGroups: @escaping () -> Void,
        onLoadAccounts: @escaping () -> Void,
        onCalculateTotal: @escaping () -> Void,
        onScheduleGroupTotalRefresh: @escaping (String, String?) -> Void,
        onDismissGroupEditor: @escaping () -> Void
    ) {
        self.modelContext = modelContext
        self.saveChanges = saveChanges
        self.groupsProvider = groupsProvider
        self.onLoadGroups = onLoadGroups
        self.onLoadAccounts = onLoadAccounts
        self.onCalculateTotal = onCalculateTotal
        self.onScheduleGroupTotalRefresh = onScheduleGroupTotalRefresh
        self.onDismissGroupEditor = onDismissGroupEditor
    }

    // MARK: - CRUD

    /// Удалить группу — счета АРХИВИРУЮТСЯ (core-путь `AccountsCoreService.archiveAccount`) и
    /// переводятся в Ungrouped (`account.group = nil`, канон). [Ф5c.7 contract, владелец 2026-07-12]
    /// Возврат легаси-поведения (было отменено при контрактном флипе как "излишняя мутация" —
    /// пересмотрено: это отмена случайного регресса, а не новая фича — удаление группы в старом мире
    /// ВСЕГДА архивировало её счета, тот же контракт сохраняется для core).
    func deleteGroup(_ group: AccountGroup) {
        let groupID = group.id
        let transactionContext = ModelContext(modelContext.container)
        transactionContext.autosaveEnabled = false
        do {
            let groupDescriptor = FetchDescriptor<AccountGroup>(
                predicate: #Predicate<AccountGroup> { $0.id == groupID }
            )
            guard let transactionGroup = try transactionContext.fetch(groupDescriptor).first else { return }
            let accountsService = AccountsCoreService(modelContext: transactionContext)
            let now = Date()
            let accounts = try transactionContext.fetch(FetchDescriptor<Account>()).filter { $0.group?.id == groupID }
            for account in accounts {
                accountsService.stageArchiveAccount(account, on: now)
                account.group = nil
            }
            transactionContext.delete(transactionGroup)
            try syncLegacyGroupDeletion(named: transactionGroup.name, in: transactionContext)
            try saveChanges(transactionContext)
            onLoadGroups()
            onLoadAccounts()
            onCalculateTotal()
        } catch {
            transactionContext.rollback()
            AppLogger.log(.error, category: "Finance", "Failed to delete group: \(error.localizedDescription)")
        }
    }

    func updateGroup(
        name: String,
        colorHex: String,
        displayCurrency: String?,
        customIconName: String?,
        editingGroup: AccountGroup?,
        displayCurrencyFallback: String
    ) {
        let groupToUpdate: AccountGroup
        if let existing = editingGroup {
            // Синхронизируем одноимённую легаси-`FinanceGroup` (fallback-хвост, invariant 9) ДО
            // переименования — ищем по СТАРОМУ имени, иначе связь по имени порвётся.
            syncLegacyGroup(oldName: existing.name, newName: name, colorHex: colorHex, displayCurrency: displayCurrency)
            existing.name = name
            existing.colorHex = colorHex
            existing.displayCurrency = displayCurrency
            existing.customIconName = customIconName
            groupToUpdate = existing
        } else {
            let maxOrder = groupsProvider().map { $0.order }.max() ?? -1
            let newGroup = AccountGroup(name: name, colorHex: colorHex, displayCurrency: displayCurrency, order: maxOrder + 1)
            newGroup.customIconName = customIconName
            modelContext.insert(newGroup)
            groupToUpdate = newGroup
        }

        do {
            try modelContext.save()
            onLoadGroups()
            onDismissGroupEditor()
            onScheduleGroupTotalRefresh(
                groupToUpdate.groupUniqueID,
                displayCurrency ?? displayCurrencyFallback
            )
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to save group: \(error.localizedDescription)")
        }
    }

    func moveGroup(sourceGroupID: String, destinationIndex: Int) {
        var groups = groupsProvider()
        guard let sourceIndex = groups.firstIndex(where: { $0.groupUniqueID == sourceGroupID }) else {
            return
        }

        let movedGroup = groups.remove(at: sourceIndex)
        let boundedDestination = min(max(destinationIndex, 0), groups.count)
        groups.insert(movedGroup, at: boundedDestination)

        for (index, group) in groups.enumerated() {
            group.order = index
        }

        do {
            try modelContext.save()
            onLoadGroups()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to reorder groups: \(error.localizedDescription)")
        }
    }

    // MARK: - Синхронизация с легаси-`FinanceGroup` (invariant 9 §2.1 — fallback-хвост по имени)

    /// Переносит правки редактора группы (сore, primary) на одноимённую легаси-`FinanceGroup`, если
    /// она ещё существует (непроконвертированный хвост). Инверсия направления sync относительно
    /// expand-фазы (была core←legacy, теперь legacy←core, т.к. core стал primary).
    private func syncLegacyGroup(oldName: String, newName: String, colorHex: String, displayCurrency: String?) {
        guard !oldName.isEmpty else { return }
        let descriptor = FetchDescriptor<FinanceGroup>(predicate: #Predicate<FinanceGroup> { $0.name == oldName })
        guard let legacyGroup = try? modelContext.fetch(descriptor).first else { return }
        legacyGroup.name = newName
        legacyGroup.colorHex = colorHex
        legacyGroup.displayCurrency = displayCurrency
        legacyGroup.updatedAt = Date()
    }

    /// Удаление core-группы: если одноимённая легаси-`FinanceGroup` существует И пуста (нет
    /// непроконвертированного хвоста), удаляем и её — иначе оставляем (легаси archive/restore
    /// продолжает работать для её содержимого, invariant 5).
    private func syncLegacyGroupDeletion(named name: String, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<FinanceGroup>(predicate: #Predicate<FinanceGroup> { $0.name == name })
        guard let legacyGroup = try context.fetch(descriptor).first else { return }
        if legacyGroup.accounts?.isEmpty ?? true {
            context.delete(legacyGroup)
        }
    }
}
