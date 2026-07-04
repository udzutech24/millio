import Foundation
import SwiftData
import Testing
@testable import millio

/// Задача 7 брифинга Фазы 5: `deleteGroup` (старый мир) должен убирать и МИРРОРНУЮ `AccountGroup`
/// нового ядра (мэппинг по имени, см. `AccountsCoreAdditionBridge.resolveAccountGroup`) — иначе
/// счета нового ядра остаются «привязанными» к группе, которой больше нет в UI, и не попадают ни
/// в старый мир, ни в Ungrouped (регрессия, найденная при аудите Фазы 5).
@MainActor
struct FinanceGroupServiceAccountsCoreTests {

    private func makeContext() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        return (container, container.mainContext)
    }

    private func makeService(modelContext: ModelContext, groups: [FinanceGroup]) -> FinanceGroupService {
        FinanceGroupService(
            modelContext: modelContext,
            ungroupedGroupName: FinanceSystemGroups.ungroupedName,
            groupsProvider: { groups },
            accountInfoResolver: { _ in true },
            onLoadGroups: {},
            onLoadAccounts: {},
            onCalculateTotal: {},
            onScheduleGroupTotalRefresh: { _, _ in },
            onDismissGroupEditor: {},
            onArchiveUnderlying: { _, _ in }
        )
    }

    @Test("Удаление старой группы удаляет мирронную AccountGroup нового ядра, счета уходят в Ungrouped (group=nil)")
    func deletingFinanceGroupRemovesMirroredAccountGroupAndNullifiesAccounts() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let financeGroup = FinanceGroup(name: "Инвестиции", colorHex: "#FF0000")
        ctx.insert(financeGroup)

        // Мирронная AccountGroup нового ядра — ТО ЖЕ имя, как создаёт `AccountsCoreAdditionBridge`.
        let coreGroup = AccountGroup(name: "Инвестиции", colorHex: "#FF0000")
        ctx.insert(coreGroup)

        let accountsService = AccountsCoreService(modelContext: ctx)
        let coreAccount = try accountsService.createAccount(name: "Брокерский счёт", kind: .marketInvestment, currency: "USD", openingBalance: 0)
        coreAccount.group = coreGroup
        try ctx.save()

        #expect(coreAccount.group?.name == "Инвестиции")

        let service = makeService(modelContext: ctx, groups: [financeGroup])
        service.deleteGroup(financeGroup)

        // Мирронная группа физически удалена — не осталась «осиротевшей» ссылкой.
        let remainingCoreGroups = try ctx.fetch(FetchDescriptor<AccountGroup>(
            predicate: #Predicate<AccountGroup> { $0.name == "Инвестиции" }
        ))
        #expect(remainingCoreGroups.isEmpty)

        // Счёт нового ядра ЖИВ (AC7: удаление группы — не архивация и не удаление счёта),
        // но group == nil — нашёл дорогу в Ungrouped, а не остался привязан к удалённой группе.
        let accountID = coreAccount.id
        let refreshedAccount = try ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.id == accountID }
        )).first
        #expect(refreshedAccount != nil)
        #expect(refreshedAccount?.group == nil)
        #expect(refreshedAccount?.archivedAt == nil) // не архивация, счёт остаётся активным
    }

    @Test("Удаление группы без соответствующей AccountGroup нового ядра — no-op, не падает")
    func deletingFinanceGroupWithoutMirroredAccountGroupIsNoop() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let financeGroup = FinanceGroup(name: "Только старый мир", colorHex: "#00FF00")
        ctx.insert(financeGroup)
        try ctx.save()

        let service = makeService(modelContext: ctx, groups: [financeGroup])
        service.deleteGroup(financeGroup) // не должно кидать/падать

        let remaining = try ctx.fetch(FetchDescriptor<AccountGroup>())
        #expect(remaining.isEmpty)
    }
}
