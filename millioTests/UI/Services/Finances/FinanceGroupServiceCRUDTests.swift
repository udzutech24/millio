import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5c.7.1: фиксируем CRUD-поведение `FinanceGroupService` (create/rename/move) и мост правки
/// легаси-группы на одноимённую core-`AccountGroup` (`syncCoreGroup`). Эти инварианты должны
/// пережить перетипизацию VM/View на core в 5c.7.3–5c.7.5 — тест ловит регресс порядка/имени/моста.
/// Delete + удаление мирронной `AccountGroup` покрыты `FinanceGroupServiceAccountsCoreTests`.
@MainActor
struct FinanceGroupServiceCRUDTests {

    private func makeContext() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        return (container, container.mainContext)
    }

    /// Провайдер групп читает из стора динамически — так же, как VM после `onLoadGroups`.
    private func makeService(_ ctx: ModelContext) -> FinanceGroupService {
        FinanceGroupService(
            modelContext: ctx,
            ungroupedGroupName: FinanceSystemGroups.ungroupedName,
            groupsProvider: {
                (try? ctx.fetch(FetchDescriptor<FinanceGroup>(sortBy: [SortDescriptor(\.order)]))) ?? []
            },
            accountInfoResolver: { _ in true },
            onLoadGroups: {},
            onLoadAccounts: {},
            onCalculateTotal: {},
            onScheduleGroupTotalRefresh: { _, _ in },
            onDismissGroupEditor: {},
            onArchiveUnderlying: { _, _ in }
        )
    }

    @Test("Создание группы (editingGroup=nil) вставляет FinanceGroup со следующим порядком")
    func createGroupInsertsWithNextOrder() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let existing = FinanceGroup(name: "Карты", colorHex: "#111111", order: 0)
        ctx.insert(existing)
        try ctx.save()

        let service = makeService(ctx)
        service.updateGroup(
            name: "Вклады",
            colorHex: "#222222",
            displayCurrency: nil,
            editingGroup: nil,
            displayCurrencyFallback: "RUB"
        )

        let created = try ctx.fetch(FetchDescriptor<FinanceGroup>(
            predicate: #Predicate<FinanceGroup> { $0.name == "Вклады" }
        ))
        #expect(created.count == 1)
        #expect(created.first?.order == 1) // max(existing.order)=0 → +1
    }

    @Test("Переименование группы переносит имя/цвет/валюту на одноимённую core-AccountGroup (syncCoreGroup)")
    func renameGroupSyncsMirroredAccountGroup() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let financeGroup = FinanceGroup(name: "Инвестиции", colorHex: "#FF0000")
        ctx.insert(financeGroup)
        // Мирронная core-группа с ТЕМ ЖЕ именем (как создаёт `resolveAccountGroup`).
        let coreGroup = AccountGroup(name: "Инвестиции", colorHex: "#FF0000")
        ctx.insert(coreGroup)
        try ctx.save()

        let service = makeService(ctx)
        service.updateGroup(
            name: "Брокеры",
            colorHex: "#00AAFF",
            displayCurrency: "USD",
            editingGroup: financeGroup,
            displayCurrencyFallback: "RUB"
        )

        // Легаси-группа переименована.
        #expect(financeGroup.name == "Брокеры")
        #expect(financeGroup.colorHex == "#00AAFF")

        // Core-двойник синхронизирован по СТАРОМУ имени — иначе связь по имени порвалась бы.
        let refreshedCore = try ctx.fetch(FetchDescriptor<AccountGroup>()).first
        #expect(refreshedCore?.name == "Брокеры")
        #expect(refreshedCore?.colorHex == "#00AAFF")
        #expect(refreshedCore?.displayCurrency == "USD")
        // Старого имени в core-сторе не осталось.
        let staleByOldName = try ctx.fetch(FetchDescriptor<AccountGroup>(
            predicate: #Predicate<AccountGroup> { $0.name == "Инвестиции" }
        ))
        #expect(staleByOldName.isEmpty)
    }

    @Test("Перемещение группы вверх пересчитывает order у затронутых групп")
    func moveGroupReordersOrder() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let groupA = FinanceGroup(name: "A", colorHex: "#111111", order: 0)
        let groupB = FinanceGroup(name: "B", colorHex: "#222222", order: 1)
        ctx.insert(groupA)
        ctx.insert(groupB)
        try ctx.save()

        let service = makeService(ctx)
        // Двигаем B на позицию 0 → B должна стать первой.
        service.moveGroup(sourceGroupID: groupB.groupUniqueID, destinationIndex: 0)

        #expect(groupB.order == 0)
        #expect(groupA.order == 1)
    }
}
