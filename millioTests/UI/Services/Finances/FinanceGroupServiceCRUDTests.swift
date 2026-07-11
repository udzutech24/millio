import Foundation
import SwiftData
import Testing
@testable import millio

/// [Ф5c.7 contract] Инвертировано относительно исходного (было: `FinanceGroup`-primary + `syncCoreGroup`
/// легаси→core). Теперь `FinanceGroupService` — `AccountGroup`-primary + `syncLegacyGroup` core→легаси
/// (fallback-хвост, invariant 9 §2.1). Delete покрыт `FinanceGroupServiceAccountsCoreTests`.
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
            groupsProvider: {
                (try? ctx.fetch(FetchDescriptor<AccountGroup>(sortBy: [SortDescriptor(\.order)]))) ?? []
            },
            onLoadGroups: {},
            onLoadAccounts: {},
            onCalculateTotal: {},
            onScheduleGroupTotalRefresh: { _, _ in },
            onDismissGroupEditor: {}
        )
    }

    @Test("Создание группы (editingGroup=nil) вставляет AccountGroup со следующим порядком")
    func createGroupInsertsWithNextOrder() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let existing = AccountGroup(name: "Карты", colorHex: "#111111", order: 0)
        ctx.insert(existing)
        try ctx.save()

        let service = makeService(ctx)
        service.updateGroup(
            name: "Вклады",
            colorHex: "#222222",
            displayCurrency: nil,
            customIconName: nil,
            editingGroup: nil,
            displayCurrencyFallback: "RUB"
        )

        let created = try ctx.fetch(FetchDescriptor<AccountGroup>(
            predicate: #Predicate<AccountGroup> { $0.name == "Вклады" }
        ))
        #expect(created.count == 1)
        #expect(created.first?.order == 1) // max(existing.order)=0 → +1
    }

    @Test("Переименование группы переносит имя/цвет/валюту на одноимённую легаси-FinanceGroup (syncLegacyGroup)")
    func renameGroupSyncsMirroredFinanceGroup() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let coreGroup = AccountGroup(name: "Инвестиции", colorHex: "#FF0000")
        ctx.insert(coreGroup)
        // Мирронная легаси-группа с ТЕМ ЖЕ именем (непроконвертированный хвост, invariant 9).
        let financeGroup = FinanceGroup(name: "Инвестиции", colorHex: "#FF0000")
        ctx.insert(financeGroup)
        try ctx.save()

        let service = makeService(ctx)
        service.updateGroup(
            name: "Брокеры",
            colorHex: "#00AAFF",
            displayCurrency: "USD",
            customIconName: nil,
            editingGroup: coreGroup,
            displayCurrencyFallback: "RUB"
        )

        // Core-группа переименована.
        #expect(coreGroup.name == "Брокеры")
        #expect(coreGroup.colorHex == "#00AAFF")
        #expect(coreGroup.displayCurrency == "USD")

        // Легаси-двойник синхронизирован по СТАРОМУ имени — иначе связь по имени порвалась бы.
        #expect(financeGroup.name == "Брокеры")
        #expect(financeGroup.colorHex == "#00AAFF")
        // Старого имени в легаси-сторе не осталось.
        let staleByOldName = try ctx.fetch(FetchDescriptor<FinanceGroup>(
            predicate: #Predicate<FinanceGroup> { $0.name == "Инвестиции" }
        ))
        #expect(staleByOldName.isEmpty)
    }

    @Test("Перемещение группы вверх пересчитывает order у затронутых групп")
    func moveGroupReordersOrder() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let groupA = AccountGroup(name: "A", colorHex: "#111111", order: 0)
        let groupB = AccountGroup(name: "B", colorHex: "#222222", order: 1)
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
