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
        return visibleAccountsForGroup(group).isEmpty
    }

    private func visibleAccountsForGroup(_ group: FinanceGroup) -> [FinanceAccount] {
        orderedAccounts(for: group).filter { accountInfoResolver($0) }
    }

    func orderedAccounts(for group: FinanceGroup, amountResolver: ((FinanceAccount) -> Double)? = nil) -> [FinanceAccount] {
        let accounts = (group.accounts ?? []).filter { accountInfoResolver($0) }
        if group.usesManualAccountOrdering {
            return accounts.sorted { lhs, rhs in
                if lhs.order != rhs.order {
                    return lhs.order < rhs.order
                }
                return lhs.createdAt < rhs.createdAt
            }
        }

        return accounts.sorted { lhs, rhs in
            let lhsAmount = amountResolver?(lhs) ?? 0
            let rhsAmount = amountResolver?(rhs) ?? 0
            if lhsAmount != rhsAmount {
                return lhsAmount > rhsAmount
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    // MARK: - CRUD

    func deleteGroup(_ group: FinanceGroup) {
        let now = Date()
        var didAffectCards = false
        var didAffectCredits = false

        if let accounts = group.accounts {
            for account in accounts {
                onArchiveUnderlying(account, now)
                switch account.accountType {
                case .card:
                    didAffectCards = true
                case .credit:
                    didAffectCredits = true
                case .investment:
                    break
                }
                modelContext.delete(account)
            }
        }

        modelContext.delete(group)

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

}
