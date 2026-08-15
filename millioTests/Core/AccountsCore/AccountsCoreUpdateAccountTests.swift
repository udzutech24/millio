import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5c.7.0: `AccountsCoreService.updateAccount` — правка «карточки» счёта (имя/группа/заметка/мета)
/// прямой мутацией полей, БЕЗ смены валюты (инвариант 8) и БЕЗ создания события (имя/группа/мета не
/// участвуют в реплее `balanceAt`). Два гейта под-фазы: (1) регресс-guard на дубли по аналогии с
/// `AllPresetsOnNewCoreTests`; (2) backup roundtrip — правка переживает export→clear→import (инвариант 7).
@Suite(.serialized)
@MainActor
struct AccountsCoreUpdateAccountTests {

    /// См. комментарий в `AccountsCoreServiceTests.makeContext` — контейнер держим живым вместе с
    /// контекстом, иначе `mainContext` остаётся с разрушенным хранилищем.
    private func makeContext() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        return (container, container.mainContext)
    }

    /// Регистрация типов в `ModelTypeRegistry` для backup-roundtrip, с восстановлением состояния —
    /// один-в-один паттерн `AccountsCoreBackupTests.withRegistry`.
    private func withRegistry(_ body: () throws -> Void) throws {
        let state = ModelTypeRegistry.shared.captureState()
        FinanceFeatureRegistration.register()
        CardFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        CurrencyFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()
        do { try body() } catch { ModelTypeRegistry.shared.restoreState(state); throw error }
        ModelTypeRegistry.shared.restoreState(state)
    }

    // MARK: - Гейт 1: регресс-guard на дубли

    @Test("updateAccount(rename/группа/мета) правит на месте — не плодит Account и не пишет событие")
    func updateAccountEditsInPlaceWithoutDuplicating() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let group = AccountGroup(name: "Основные")
        ctx.insert(group)
        let account = try service.createAccount(
            name: "Карта", kind: .debitCard, currency: "RUB", openingBalance: 1_000,
            cardMeta: CardMeta(bank: Bank.sberbank.rawValue, last4: "1234")
        )
        #expect(try ctx.fetch(FetchDescriptor<Account>()).count == 1)
        let openingEventCount = try ctx.fetch(FetchDescriptor<AccountEvent>()).count

        try service.updateAccount(
            account, name: "Карта Т-Банк", group: group, note: "зп-карта",
            cardMeta: CardMeta(bank: Bank.tinkoff.rawValue, last4: "9999")
        )

        let accounts = try ctx.fetch(FetchDescriptor<Account>())
        #expect(accounts.count == 1, "updateAccount не должен плодить Account (регресс-guard дубля Ф6a)")
        let updated = try #require(accounts.first)
        #expect(updated.id == account.id)
        #expect(updated.name == "Карта Т-Банк")
        #expect(updated.group?.id == group.id)
        #expect(updated.note == "зп-карта")
        #expect(updated.cardMeta?.bank == Bank.tinkoff.rawValue)
        #expect(updated.cardMeta?.last4 == "9999")
        // Валюта не тронута — параметра валюты в API нет (инвариант 8).
        #expect(updated.currency == "RUB")
        // Правка карточки — не событие: лента не выросла (остался только якорь openingBalance).
        #expect(try ctx.fetch(FetchDescriptor<AccountEvent>()).count == openingEventCount)
        // Ни одной легаси-сущности при правке не создано.
        #expect(try ctx.fetch(FetchDescriptor<Card>()).isEmpty)
    }

    @Test("updateAccount(group: nil) убирает счёт из группы («Без группы» = account.group == nil)")
    func updateAccountCanClearGroup() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let group = AccountGroup(name: "Группа")
        ctx.insert(group)
        let account = try service.createAccount(
            name: "Счёт", kind: .bankAccount, currency: "RUB", openingBalance: 5_000, group: group
        )
        #expect(account.group?.id == group.id)

        try service.updateAccount(account, name: account.name, group: nil)

        #expect(try ctx.fetch(FetchDescriptor<Account>()).count == 1)
        #expect(account.group == nil, "group: nil = «Без группы» (канон Ungrouped ядра)")
    }

    @Test("updateAccount changes total membership and bumps account-set revision")
    func updateAccountCanChangeTotalMembership() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(
            name: "Квартира", kind: .manualAsset, currency: "RUB", openingBalance: 10_000_000
        )
        let revisionBefore = account.valuationMembershipRevision

        try service.updateAccount(
            account,
            name: account.name,
            group: nil,
            includeInTotal: false
        )

        #expect(account.includeInTotal == false)
        #expect(account.participates(on: Date()) == false)
        #expect(account.valuationMembershipRevision != revisionBefore)
        #expect(try ctx.fetch(FetchDescriptor<AccountEvent>()).count == 1)
    }

    @Test("Failed update is typed, rolled back, and cannot be resurrected by a later save")
    func updateAccountSaveFailureRollsBackCompletely() throws {
        struct SaveFailure: Error {}
        let (container, ctx) = try makeContext()
        _ = container
        let setupService = AccountsCoreService(modelContext: ctx)
        let account = try setupService.createAccount(
            name: "Original", kind: .bankAccount, currency: "RUB", openingBalance: 1_000
        )
        let financialRevisionBefore = account.valuationFinancialRevision
        let membershipRevisionBefore = account.valuationMembershipRevision
        let failingService = AccountsCoreService(modelContext: ctx) { _ in throw SaveFailure() }

        do {
            _ = try failingService.updateAccount(
                account,
                name: "Must not persist",
                group: nil,
                note: "Must not persist",
                includeInTotal: false
            )
            Issue.record("Expected a typed persistence failure")
        } catch let AccountsCorePersistenceError.saveFailed(operation, underlying) {
            #expect(operation == .updateAccount)
            #expect(underlying is SaveFailure)
        } catch {
            Issue.record("Unexpected error: \(type(of: error))")
        }

        let rolledBack = try #require(ctx.fetch(FetchDescriptor<Account>()).first)
        #expect(rolledBack.name == "Original")
        #expect(rolledBack.note == nil)
        #expect(rolledBack.includeInTotal)
        #expect(rolledBack.valuationFinancialRevision == financialRevisionBefore)
        #expect(rolledBack.valuationMembershipRevision == membershipRevisionBefore)
        #expect(!ctx.hasChanges)

        ctx.insert(AccountGroup(name: "Unrelated"))
        try ctx.save()
        let persisted = try #require(ctx.fetch(FetchDescriptor<Account>()).first)
        #expect(persisted.name == "Original")
        #expect(persisted.note == nil)
        #expect(persisted.includeInTotal)
    }

    // MARK: - Гейт 2: backup roundtrip (инвариант 7)

    @Test("Round-trip: правка через updateAccount переживает export→clear→import без потери полей")
    func updateAccountSurvivesBackupRoundTrip() throws {
        try withRegistry {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let ctx = container.mainContext
            let service = AccountsCoreService(modelContext: ctx)

            let group = AccountGroup(name: "Инвестиции", colorHex: "#00AA00", order: 2)
            ctx.insert(group)
            let account = try service.createAccount(
                name: "Старое имя", kind: .bankAccount, currency: "RUB", openingBalance: 5_000
            )
            try service.updateAccount(account, name: "Новое имя", group: group, note: "после правки")

            let backupData = try DataRepository.exportAllData(from: ctx)
            let repository = DataRepository(modelContext: ctx, modelContainer: container)
            try repository.clearAllData()
            #expect(try ctx.fetch(FetchDescriptor<Account>()).isEmpty)

            try repository.importAllData(backupData)

            let restored = try ctx.fetch(FetchDescriptor<Account>())
            #expect(restored.count == 1, "roundtrip не должен потерять или задвоить счёт")
            let acc = try #require(restored.first)
            // updateAccount не вводит новых событий/полей схемы — правит существующие name/group/note,
            // которые уже сериализуются в Account.export(); поэтому старый бэкап, снятый до появления
            // updateAccount, байт-совместим и миграции не требует (инвариант 7).
            #expect(acc.name == "Новое имя")
            #expect(acc.note == "после правки")
            #expect(acc.group?.name == "Инвестиции")
            #expect(acc.currency == "RUB")
        }
    }
}
