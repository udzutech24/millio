import Foundation
import SwiftData
import Testing
@testable import millio

/// Схема V4: Account/AccountEvent/AccountGroup/AccountDailySnapshot открываются, вставляются,
/// фетчатся; каскад удаления события/снапшота вместе со счётом; nullify группы при удалении.
@Suite("AccountSchema")
struct AccountSchemaTests {

    @Test @MainActor
    func insertsAndFetchesAllFourTypes() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext

        let group = AccountGroup(name: "Наличные и карты")
        let account = Account(name: "Тинькофф Дебетовая", kind: .debitCard)
        account.group = group
        let event = AccountEvent(account: account, date: Date(), type: .openingBalance, amount: 1000)
        let snapshot = AccountDailySnapshot(account: account, dayKey: "2026-07-04", balance: 1000)

        ctx.insert(group)
        ctx.insert(account)
        ctx.insert(event)
        ctx.insert(snapshot)
        try ctx.save()

        let groups = try ctx.fetch(FetchDescriptor<AccountGroup>())
        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        let events = try ctx.fetch(FetchDescriptor<AccountEvent>())
        let snapshots = try ctx.fetch(FetchDescriptor<AccountDailySnapshot>())

        #expect(groups.count == 1)
        #expect(accounts.count == 1)
        #expect(events.count == 1)
        #expect(snapshots.count == 1)
        #expect(accounts.first?.group?.name == "Наличные и карты")
    }

    /// Удаление счёта каскадно удаляет его события и снапшоты (deleteRule: .cascade).
    @Test @MainActor
    func deletingAccountCascadesEventsAndSnapshots() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext

        let account = Account(name: "Долг соседу", kind: .debt)
        let event = AccountEvent(account: account, date: Date(), type: .openingBalance, amount: -5000)
        let snapshot = AccountDailySnapshot(account: account, dayKey: "2026-07-04", balance: -5000)
        ctx.insert(account)
        ctx.insert(event)
        ctx.insert(snapshot)
        try ctx.save()

        ctx.delete(account)
        try ctx.save()

        let events = try ctx.fetch(FetchDescriptor<AccountEvent>())
        let snapshots = try ctx.fetch(FetchDescriptor<AccountDailySnapshot>())
        #expect(events.isEmpty)
        #expect(snapshots.isEmpty)
    }

    /// Удаление группы не удаляет счета — только обнуляет их group (deleteRule: .nullify).
    @Test @MainActor
    func deletingGroupNullifiesAccountGroupButKeepsAccount() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext

        let group = AccountGroup(name: "Основные")
        let account = Account(name: "Наличные", kind: .cash)
        account.group = group
        ctx.insert(group)
        ctx.insert(account)
        try ctx.save()

        ctx.delete(group)
        try ctx.save()

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        #expect(accounts.count == 1)
        #expect(accounts.first?.group == nil)
    }
}
