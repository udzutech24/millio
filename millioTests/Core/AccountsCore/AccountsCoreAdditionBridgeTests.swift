import Foundation
import SwiftData
import Testing
@testable import millio

/// Тесты моста «старый флоу добавления счёта → новое ядро» (Фаза 1a-ui).
@Suite("AccountsCoreAdditionBridge")
struct AccountsCoreAdditionBridgeTests {

    private func makeContainer() throws -> ModelContainer {
        try AppMigrationPlan.makeInMemoryContainer()
    }

    // MARK: - cardKind

    @Test
    func cardKindOtherBankIsCash() {
        #expect(AccountsCoreAdditionBridge.cardKind(bank: .other) == .cash)
    }

    @Test
    func cardKindRealBankIsDebitCard() {
        #expect(AccountsCoreAdditionBridge.cardKind(bank: .sberbank) == .debitCard)
        #expect(AccountsCoreAdditionBridge.cardKind(bank: .tinkoff) == .debitCard)
    }

    // MARK: - resolveAccountGroup

    @Test @MainActor
    func resolveAccountGroupReturnsNilForNilFinanceGroup() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        #expect(AccountsCoreAdditionBridge.resolveAccountGroup(matching: nil, in: ctx) == nil)
    }

    @Test @MainActor
    func resolveAccountGroupCreatesNewGroupByName() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let financeGroup = FinanceGroup(name: "Мои карты", colorHex: "#123456")
        ctx.insert(financeGroup)

        let resolved = AccountsCoreAdditionBridge.resolveAccountGroup(matching: financeGroup, in: ctx)
        #expect(resolved?.name == "Мои карты")

        let descriptor = FetchDescriptor<AccountGroup>()
        let allGroups = try ctx.fetch(descriptor)
        #expect(allGroups.count == 1)
    }

    @Test @MainActor
    func resolveAccountGroupReusesExistingGroupWithSameName() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let existing = AccountGroup(name: "Вклады")
        ctx.insert(existing)
        try ctx.save()

        let financeGroup = FinanceGroup(name: "Вклады")
        ctx.insert(financeGroup)

        let resolved = AccountsCoreAdditionBridge.resolveAccountGroup(matching: financeGroup, in: ctx)
        #expect(resolved?.id == existing.id)

        let descriptor = FetchDescriptor<AccountGroup>()
        let allGroups = try ctx.fetch(descriptor)
        #expect(allGroups.count == 1) // не задублировали
    }
}
