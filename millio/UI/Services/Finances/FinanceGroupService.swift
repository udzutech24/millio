//
//  FinanceGroupService.swift
//  millio
//
//  Создан в рамках Phase 5 декомпозиции FinanceViewModel.
//  Отвечает за CRUD групп счетов: создание, переименование, удаление, порядок.
//

import Foundation
import SwiftData

// MARK: - FinanceGroupService

@MainActor
final class FinanceGroupService {

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let ungroupedGroupName: String

    /// Провайдер текущих групп из FinanceState
    private let groupsProvider: () -> [FinanceGroup]

    /// Резолвер информации о счёте: используется для фильтрации видимых счетов
    private let accountInfoResolver: (FinanceAccount) -> Bool

    /// Кол-во счетов нового ядра в группе (Фаза 1.5) — чтобы группа/Ungrouped из одних core-счетов
    /// не пряталась как «пустая» (баг §1.3a: legacy-junction пуст, а счета есть в AccountGroup).
    private let coreAccountsCount: (FinanceGroup) -> Int

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
    /// Callback: архивировать underlying-счёт при удалении группы
    private let onArchiveUnderlying: (FinanceAccount, Date) -> Void

    // MARK: - Init

    init(
        modelContext: ModelContext,
        ungroupedGroupName: String,
        groupsProvider: @escaping () -> [FinanceGroup],
        accountInfoResolver: @escaping (FinanceAccount) -> Bool,
        coreAccountsCount: @escaping (FinanceGroup) -> Int = { _ in 0 },
        onLoadGroups: @escaping () -> Void,
        onLoadAccounts: @escaping () -> Void,
        onCalculateTotal: @escaping () -> Void,
        onScheduleGroupTotalRefresh: @escaping (String, String?) -> Void,
        onDismissGroupEditor: @escaping () -> Void,
        onArchiveUnderlying: @escaping (FinanceAccount, Date) -> Void
    ) {
        self.modelContext = modelContext
        self.ungroupedGroupName = ungroupedGroupName
        self.groupsProvider = groupsProvider
        self.accountInfoResolver = accountInfoResolver
        self.coreAccountsCount = coreAccountsCount
        self.onLoadGroups = onLoadGroups
        self.onLoadAccounts = onLoadAccounts
        self.onCalculateTotal = onCalculateTotal
        self.onScheduleGroupTotalRefresh = onScheduleGroupTotalRefresh
        self.onDismissGroupEditor = onDismissGroupEditor
        self.onArchiveUnderlying = onArchiveUnderlying
    }

    // MARK: - Visibility

    func visibleGroupsForList() -> [FinanceGroup] {
        groupsProvider().filter { !shouldHideGroupInList($0) }
    }

    private func shouldHideGroupInList(_ group: FinanceGroup) -> Bool {
        guard group.name == ungroupedGroupName else { return false }
        return visibleAccountsForGroup(group).isEmpty && coreAccountsCount(group) == 0
    }

    private func visibleAccountsForGroup(_ group: FinanceGroup) -> [FinanceAccount] {
        orderedAccounts(for: group).filter { accountInfoResolver($0) }
    }

    func orderedAccounts(
        for group: FinanceGroup,
        sortMode: AccountSortMode = .amountDescending,
        amountResolver: ((FinanceAccount) -> Double)? = nil,
        nameResolver: ((FinanceAccount) -> String)? = nil
    ) -> [FinanceAccount] {
        let accounts = (group.accounts ?? []).filter { accountInfoResolver($0) }
        if group.usesManualAccountOrdering {
            return accounts.sorted { lhs, rhs in
                if lhs.order != rhs.order { return lhs.order < rhs.order }
                return lhs.createdAt < rhs.createdAt
            }
        }

        return accounts.sorted { lhs, rhs in
            switch sortMode {
            case .amountDescending:
                let lhsAmt = amountResolver?(lhs) ?? 0
                let rhsAmt = amountResolver?(rhs) ?? 0
                if lhsAmt != rhsAmt { return lhsAmt > rhsAmt }
            case .amountAscending:
                let lhsAmt = amountResolver?(lhs) ?? 0
                let rhsAmt = amountResolver?(rhs) ?? 0
                if lhsAmt != rhsAmt { return lhsAmt < rhsAmt }
            case .nameAscending:
                let lhsName = nameResolver?(lhs) ?? ""
                let rhsName = nameResolver?(rhs) ?? ""
                let cmp = lhsName.localizedCompare(rhsName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
            case .nameDescending:
                let lhsName = nameResolver?(lhs) ?? ""
                let rhsName = nameResolver?(rhs) ?? ""
                let cmp = lhsName.localizedCompare(rhsName)
                if cmp != .orderedSame { return cmp == .orderedDescending }
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    // MARK: - CRUD

    func deleteGroup(_ group: FinanceGroup) {
        let now = Date()
        var didAffectCards = false
        var didAffectCredits = false
        let archiveGroup = FinanceSystemGroups.ensureUngroupedGroup(in: modelContext)
        let shouldDeleteGroup = archiveGroup.groupUniqueID != group.groupUniqueID
        var nextArchiveOrder = nextAccountOrder(in: archiveGroup)

        if let accounts = group.accounts {
            for account in accounts {
                onArchiveUnderlying(account, now)
                account.group = archiveGroup
                account.order = nextArchiveOrder
                account.updatedAt = now
                nextArchiveOrder += 1

                switch account.accountType {
                case .card:
                    didAffectCards = true
                case .credit:
                    didAffectCredits = true
                case .investment:
                    break
                }
            }
        }

        if shouldDeleteGroup {
            modelContext.delete(group)
            // Мост Cashflow→новое ядро (задача 7, Фаза 5): `AccountGroup` нового мира мэппится на
            // `FinanceGroup` ПО ИМЕНИ (см. `AccountsCoreAdditionBridge.resolveAccountGroup`). Без этой
            // строки удаление старой группы оставляло бы счета нового ядра «привязанными» к группе,
            // которой больше нет в UI старого мира — они не появлялись бы ни в старой, ни в Ungrouped.
            // Удаление АккаунтГруппы каскадом `.nullify` переводит её счета в Ungrouped (group = nil),
            // сами счета и их события НЕ трогает (AC7: это не архивация и не удаление счёта).
            let groupName = group.name
            let coreGroupDescriptor = FetchDescriptor<AccountGroup>(
                predicate: #Predicate<AccountGroup> { $0.name == groupName }
            )
            if let coreGroup = try? modelContext.fetch(coreGroupDescriptor).first {
                modelContext.delete(coreGroup)
            }
        }

        do {
            try modelContext.save()
            onLoadGroups()
            onLoadAccounts()
            onCalculateTotal()

            if didAffectCards {
                EventBus.shared.publish(FinanceEvent.cardsUpdated)
            }
            if didAffectCredits {
                EventBus.shared.publish(FinanceEvent.creditsUpdated)
            }
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to delete group: \(error.localizedDescription)")
        }
    }

    func updateGroup(
        name: String,
        colorHex: String,
        displayCurrency: String?,
        editingGroup: FinanceGroup?,
        displayCurrencyFallback: String
    ) {
        let groupToUpdate: FinanceGroup
        if let existing = editingGroup {
            // Синхронизируем одноимённую AccountGroup (канон, Фаза 1.5) ДО переименования FinanceGroup —
            // ищем по СТАРОМУ имени, иначе после смены имени связь по имени порвётся.
            syncCoreGroup(oldName: existing.name, newName: name, colorHex: colorHex, displayCurrency: displayCurrency)
            existing.name = name
            existing.colorHex = colorHex
            existing.displayCurrency = displayCurrency
            existing.updatedAt = Date()
            groupToUpdate = existing
        } else {
            let maxOrder = groupsProvider().map { $0.order }.max() ?? -1
            let newGroup = FinanceGroup(name: name, colorHex: colorHex, order: maxOrder + 1)
            newGroup.displayCurrency = displayCurrency
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
        var groups = visibleGroupsForList()
        guard let sourceIndex = groups.firstIndex(where: { $0.groupUniqueID == sourceGroupID }) else {
            return
        }

        let movedGroup = groups.remove(at: sourceIndex)
        let boundedDestination = min(max(destinationIndex, 0), groups.count)
        groups.insert(movedGroup, at: boundedDestination)

        for (index, group) in groups.enumerated() {
            group.order = index
            group.updatedAt = Date()
        }

        normalizeHiddenGroupOrders(excluding: groups.map(\.groupUniqueID))

        do {
            try modelContext.save()
            onLoadGroups()
        } catch {
            AppLogger.log(.error, category: "Finance", "Failed to reorder groups: \(error.localizedDescription)")
        }
    }

    // MARK: - Order Helpers

    func normalizeHiddenGroupOrders(excluding visibleGroupIDs: [String]) {
        let hiddenGroups = groupsProvider()
            .filter { !visibleGroupIDs.contains($0.groupUniqueID) }
            .sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.createdAt < rhs.createdAt
            }

        let startIndex = visibleGroupIDs.count
        for (offset, group) in hiddenGroups.enumerated() {
            group.order = startIndex + offset
        }
    }

    func nextAccountOrder(in group: FinanceGroup) -> Int {
        ((group.accounts ?? []).map(\.order).max() ?? -1) + 1
    }

    // MARK: - Синхронизация с AccountGroup (Фаза 1.5)

    /// Переносит правки редактора группы на одноимённую `AccountGroup` (канон нового ядра). Без этого
    /// после слияния моделей правка цвета/валюты/имени в редакторе меняла бы только легаси-`FinanceGroup`,
    /// а `AccountGroup` (по которой считаются core-счета) расходилась бы. Ищем по СТАРОМУ имени; если
    /// группы ещё нет — не создаём (создаст `GroupsMigrator`/`resolveAccountGroup` при первом core-счёте).
    private func syncCoreGroup(oldName: String, newName: String, colorHex: String, displayCurrency: String?) {
        guard oldName != ungroupedGroupName, !oldName.isEmpty else { return }
        let descriptor = FetchDescriptor<AccountGroup>(
            predicate: #Predicate<AccountGroup> { $0.name == oldName }
        )
        guard let coreGroup = try? modelContext.fetch(descriptor).first else { return }
        coreGroup.name = newName
        coreGroup.colorHex = colorHex
        coreGroup.displayCurrency = displayCurrency
    }

}
