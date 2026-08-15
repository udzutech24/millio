import Foundation
import SwiftData
import Testing
@testable import millio

/// [Ф5c.7 contract, владелец 2026-07-12] Инвертировано относительно исходного (было: удаление
/// легаси-`FinanceGroup` чистит мирронную `AccountGroup`). Теперь `FinanceGroupService.deleteGroup` —
/// core-primary: АРХИВИРУЕТ счета группы (`AccountsCoreService.archiveAccount` — возврат легаси-
/// поведения, отмена случайного регресса контрактного флипа) и переводит их в Ungrouped
/// (`group = nil`, канон), + best-effort чистит ПУСТУЮ мирронную легаси-`FinanceGroup` того же имени
/// (`syncLegacyGroupDeletion`) — та же защита от «осиротевшей» ссылки, что была раньше, в обратном
/// направлении.
@MainActor
struct FinanceGroupServiceAccountsCoreTests {

    private func makeContext() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        return (container, container.mainContext)
    }

    private func makeService(modelContext: ModelContext, groups: [AccountGroup]) -> FinanceGroupService {
        FinanceGroupService(
            modelContext: modelContext,
            groupsProvider: { groups },
            onLoadGroups: {},
            onLoadAccounts: {},
            onCalculateTotal: {},
            onScheduleGroupTotalRefresh: { _, _ in },
            onDismissGroupEditor: {}
        )
    }

    private func sourceFile(_ relativePath: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            directory.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    @Test("Удаление core-группы удаляет ПУСТУЮ мирронную легаси-FinanceGroup, счета уходят в Ungrouped (group=nil)")
    func deletingAccountGroupRemovesEmptyMirroredFinanceGroupAndNullifiesAccounts() throws {
        let (container, ctx) = try makeContext()
        _ = container

        // Мирронная легаси-группа — ТО ЖЕ имя, ПУСТАЯ (нет FinanceAccount-junction внутри).
        let financeGroup = FinanceGroup(name: "Инвестиции", colorHex: "#FF0000")
        ctx.insert(financeGroup)

        let coreGroup = AccountGroup(name: "Инвестиции", colorHex: "#FF0000")
        ctx.insert(coreGroup)

        let accountsService = AccountsCoreService(modelContext: ctx)
        let coreAccount = try accountsService.createAccount(name: "Брокерский счёт", kind: .marketInvestment, currency: "USD", openingBalance: 0)
        coreAccount.group = coreGroup
        try ctx.save()

        #expect(coreAccount.group?.name == "Инвестиции")

        let service = makeService(modelContext: ctx, groups: [coreGroup])
        service.deleteGroup(coreGroup)

        // Мирронная легаси-группа была пуста → физически удалена, не осталась «осиротевшей» ссылкой.
        let remainingLegacyGroups = try ctx.fetch(FetchDescriptor<FinanceGroup>(
            predicate: #Predicate<FinanceGroup> { $0.name == "Инвестиции" }
        ))
        #expect(remainingLegacyGroups.isEmpty)

        // Счёт нового ядра АРХИВИРОВАН (возврат легаси-поведения, владелец 2026-07-12) и переведён
        // в Ungrouped (group == nil) — не остался привязан к удалённой группе.
        let accountID = coreAccount.id
        let refreshedAccount = try ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.id == accountID }
        )).first
        #expect(refreshedAccount != nil)
        #expect(refreshedAccount?.group == nil)
        #expect(refreshedAccount?.archivedAt != nil)
    }

    @Test("Удаление НЕ-пустой мирронной легаси-FinanceGroup — легаси-группа сохраняется (invariant 5 fallback)")
    func deletingAccountGroupWithNonEmptyMirroredFinanceGroupKeepsLegacyGroup() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let financeGroup = FinanceGroup(name: "Микс", colorHex: "#00FF00")
        ctx.insert(financeGroup)
        let card = Card(name: "Легаси-карта", cardNumber: "1234", bank: .other, cardType: .debit, currency: "RUB", balance: 100)
        ctx.insert(card)
        let junction = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        junction.group = financeGroup
        ctx.insert(junction)

        let coreGroup = AccountGroup(name: "Микс")
        ctx.insert(coreGroup)
        try ctx.save()

        let service = makeService(modelContext: ctx, groups: [coreGroup])
        service.deleteGroup(coreGroup) // не должно кидать/падать; легаси-хвост остаётся жив (invariant 5)

        let remainingLegacyGroups = try ctx.fetch(FetchDescriptor<FinanceGroup>(
            predicate: #Predicate<FinanceGroup> { $0.name == "Микс" }
        ))
        #expect(remainingLegacyGroups.count == 1)
    }

    @Test("Удаление core-группы без соответствующей легаси-FinanceGroup — no-op, не падает")
    func deletingAccountGroupWithoutMirroredFinanceGroupIsNoop() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let coreGroup = AccountGroup(name: "Только новый мир")
        ctx.insert(coreGroup)
        try ctx.save()

        let service = makeService(modelContext: ctx, groups: [coreGroup])
        service.deleteGroup(coreGroup) // не должно кидать/падать

        let remaining = try ctx.fetch(FetchDescriptor<AccountGroup>())
        #expect(remaining.isEmpty)
    }

    @Test("Group deletion contains no ignored per-account mutation")
    func groupDeletionDoesNotIgnoreArchiveFailure() throws {
        let source = try sourceFile("millio/UI/Services/Finances/FinanceGroupService.swift")
        let start = try #require(source.range(of: "func deleteGroup(_ group: AccountGroup)"))
        let tail = source[start.lowerBound...]
        let end = try #require(tail.range(of: "func updateGroup("))
        let deleteGroupBody = String(tail[..<end.lowerBound])

        #expect(!deleteGroupBody.contains("try? accountsService.archiveAccount"))
        #expect(deleteGroupBody.contains("modelContext.rollback()"))
    }

    @Test("Failed group delete rolls back archive, links and deletion before unrelated save")
    func failedDeleteIsAllOrNothing() throws {
        struct SaveFailure: Error {}
        let (_, context) = try makeContext()
        let group = AccountGroup(name: "Atomic")
        context.insert(group)
        let account = Account(name: "Cash", kind: .cash, productType: .cash)
        account.group = group
        context.insert(account)
        context.insert(AccountEvent(account: account, date: Date(), type: .openingBalance, amount: 10))
        try context.save()

        let service = FinanceGroupService(
            modelContext: context,
            saveChanges: { _ in throw SaveFailure() },
            groupsProvider: { [group] },
            onLoadGroups: {},
            onLoadAccounts: {},
            onCalculateTotal: {},
            onScheduleGroupTotalRefresh: { _, _ in },
            onDismissGroupEditor: {}
        )
        service.deleteGroup(group)

        let restoredAccount = try #require(context.fetch(FetchDescriptor<Account>()).first)
        #expect(restoredAccount.archivedAt == nil)
        #expect(restoredAccount.group?.id == group.id)
        #expect(try context.fetchCount(FetchDescriptor<AccountGroup>()) == 1)
        #expect(!context.hasChanges)

        context.insert(AccountGroup(name: "Unrelated"))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<AccountGroup>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 1)
    }
}
