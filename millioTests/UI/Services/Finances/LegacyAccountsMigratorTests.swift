import Foundation
import SwiftData
import Testing
@testable import millio

/// Оркестратор одноразовой миграции легаси-счетов в ядро (Фаза 1 плана 6b «Путь B»).
/// Инвариант тотала: core-двойник вносит ровно то, что вносил легаси, скрытая легаси = 0.
@Suite("LegacyAccountsMigrator (6b Фаза 1)")
@MainActor
struct LegacyAccountsMigratorTests {

    private struct Stack {
        let ctx: ModelContext
        let totals: AccountsTotalsService
        let registry: LegacyConversionRegistry
        let converter: LegacyAccountConverter
        let migrator: LegacyAccountsMigrator
        let flagDefaults: UserDefaults
    }

    private func makeStack() throws -> Stack {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let totals = AccountsTotalsService(
            modelContext: ctx,
            rebuilder: AccountSnapshotRebuilder(modelContainer: container),
            rateService: FixedRateService()
        )
        let registry = LegacyConversionRegistry(defaults: UserDefaults(suiteName: "mig-reg-\(UUID().uuidString)")!)
        let flagDefaults = UserDefaults(suiteName: "mig-flag-\(UUID().uuidString)")!
        let converter = LegacyAccountConverter(modelContext: ctx, registry: registry)
        let migrator = LegacyAccountsMigrator(
            modelContext: ctx,
            registry: registry,
            defaults: flagDefaults
        )
        return Stack(ctx: ctx, totals: totals, registry: registry, converter: converter, migrator: migrator, flagDefaults: flagDefaults)
    }

    @discardableResult
    private func seedCard(_ ctx: ModelContext, name: String = "ОГ", balance: Double = 150_000) -> Card {
        let card = Card(name: name, cardNumber: "1234", cardType: .debit, balance: balance)
        ctx.insert(card)
        return card
    }

    @discardableResult
    private func seedCredit(_ ctx: ModelContext, name: String = "Ипотека", amount: Double = 500_000) -> Credit {
        let credit = Credit(name: name, amount: amount, interestRate: 9.5, monthlyPayment: 5_000,
                            startDate: Date(), termMonths: 12, currency: "RUB")
        ctx.insert(credit)
        return credit
    }

    @discardableResult
    private func seedInvestment(_ ctx: ModelContext, name: String = "Квартира", amount: Double = 20_000_000) -> Investment {
        let inv = Investment(name: name, investmentType: .positive, category: .house, amount: amount)
        ctx.insert(inv)
        return inv
    }

    // MARK: - AC1 + AC2: миграция всех активных счетов, тотал неизменен

    @Test
    func migratesAllActiveLegacy_totalMatchesLegacyContribution() throws {
        let s = try makeStack()
        let card = seedCard(s.ctx)          // +150 000
        let credit = seedCredit(s.ctx)      // −500 000
        let inv = seedInvestment(s.ctx)     // +20 000 000
        try s.ctx.save()

        let summary = s.migrator.migrateAll()

        #expect(summary.migrated == 3)
        #expect(summary.skippedAlreadyConverted == 0)
        #expect(summary.failures == 0)

        // AC1: каждый легаси-счёт имеет core-двойника.
        #expect(s.registry.isConverted(legacyUniqueID: card.cardUniqueID))
        #expect(s.registry.isConverted(legacyUniqueID: credit.creditUniqueID))
        #expect(s.registry.isConverted(legacyUniqueID: inv.investmentUniqueID))

        // Легаси скрыто (archivedAt) → в тотале вносит 0; инвариант держится этим.
        #expect(card.archivedAt != nil)
        #expect(credit.archivedAt != nil)
        #expect(inv.archivedAt != nil)

        // Ровно три двойника.
        #expect(try s.ctx.fetchCount(FetchDescriptor<Account>()) == 3)
    }

    @Test
    func migratedCoreTotalEqualsSignedSum() async throws {
        let s = try makeStack()
        seedCard(s.ctx)          // +150 000
        seedCredit(s.ctx)        // −500 000
        seedInvestment(s.ctx)    // +20 000 000
        try s.ctx.save()

        s.migrator.migrateAll()

        // Ядро вносит ровно сумму знаковых вкладов легаси. До миграции легаси давали ту же сумму,
        // теперь дают 0 (archived) → двоемирный тотал неизменен (AC2).
        let total = await s.totals.totalAt(Date(), in: "RUB")
        #expect(total == Decimal(150_000 - 500_000 + 20_000_000))
    }

    // MARK: - AC3: идемпотентность (повторный прогон — no-op)

    @Test
    func secondRunIsNoOp() async throws {
        let s = try makeStack()
        seedCard(s.ctx)
        seedCredit(s.ctx)
        try s.ctx.save()

        let first = s.migrator.migrateAll()
        #expect(first.migrated == 2)

        let totalAfterFirst = await s.totals.totalAt(Date(), in: "RUB")

        // После первого прогона легаси скрыта (archivedAt) → во второй скан не попадает вовсе.
        // Именно archivedAt (а не реестр) — гарант идемпотентности, restore-safe.
        let second = s.migrator.migrateAll()
        #expect(second.migrated == 0)
        #expect(second.skippedAlreadyConverted == 0)
        #expect(second.failures == 0)

        // Ни новых двойников, ни сдвига тотала.
        #expect(try s.ctx.fetchCount(FetchDescriptor<Account>()) == 2)
        #expect(await s.totals.totalAt(Date(), in: "RUB") == totalAfterFirst)
    }

    @Test
    func migrateIfNeeded_flagShortCircuitsSecondRun() throws {
        let s = try makeStack()
        seedCard(s.ctx)
        try s.ctx.save()

        let first = s.migrator.migrateIfNeeded(scopeIdentifier: "scope-A")
        #expect(first.migrated == 1)

        // Второй прогон: флаг выставлен → полное короткое замыкание (даже без скана).
        let second = s.migrator.migrateIfNeeded(scopeIdentifier: "scope-A")
        #expect(second == LegacyAccountsMigrator.Summary())
        #expect(try s.ctx.fetchCount(FetchDescriptor<Account>()) == 1)
    }

    // MARK: - AC4: обратимость (unconvert восстанавливает легаси)

    @Test
    func unconvertRestoresLegacy() async throws {
        let s = try makeStack()
        let card = seedCard(s.ctx)
        try s.ctx.save()

        s.migrator.migrateAll()
        #expect(card.archivedAt != nil)
        #expect(try s.ctx.fetchCount(FetchDescriptor<Account>()) == 1)

        try s.converter.unconvert(legacyUniqueID: card.cardUniqueID) {
            card.archivedAt = nil
        }

        // Легаси активна снова, двойник удалён, реестр чист, ядро снова 0.
        #expect(card.archivedAt == nil)
        #expect(!s.registry.isConverted(legacyUniqueID: card.cardUniqueID))
        #expect(try s.ctx.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(await s.totals.totalAt(Date(), in: "RUB") == 0)
    }

    // MARK: - Пустой стор / стор без легаси — no-op без побочек

    @Test
    func emptyStore_isNoOp() throws {
        let s = try makeStack()
        let summary = s.migrator.migrateAll()
        #expect(summary == LegacyAccountsMigrator.Summary())
        #expect(try s.ctx.fetchCount(FetchDescriptor<Account>()) == 0)
    }

    // MARK: - Уже скрытая легаси (restore-safety) — не мигрируется повторно

    @Test
    func alreadyArchivedLegacy_notMigrated() throws {
        let s = try makeStack()
        let card = seedCard(s.ctx)
        card.archivedAt = Date() // как после restore: archivedAt перенёсся, реестр (UserDefaults) — нет
        try s.ctx.save()

        let summary = s.migrator.migrateAll()

        // Скрытая легаси в скан не попадает → двойник не создаётся (иначе был бы double-count).
        #expect(summary.migrated == 0)
        #expect(try s.ctx.fetchCount(FetchDescriptor<Account>()) == 0)
    }

    // MARK: - Группа переносится из junction FinanceAccount

    @Test
    func groupPreservedFromJunction() throws {
        let s = try makeStack()
        let card = seedCard(s.ctx)
        let group = FinanceGroup(name: "Инвесткошелёк")
        s.ctx.insert(group)
        let link = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        link.group = group
        s.ctx.insert(link)
        try s.ctx.save()

        s.migrator.migrateAll()

        let twins = try s.ctx.fetch(FetchDescriptor<Account>())
        #expect(twins.count == 1)
        #expect(twins.first?.group?.name == "Инвесткошелёк")
    }

    @Test
    func ungroupedJunction_mapsToNilGroup() throws {
        let s = try makeStack()
        let card = seedCard(s.ctx)
        let ungrouped = FinanceGroup(name: FinanceSystemGroups.ungroupedName)
        s.ctx.insert(ungrouped)
        let link = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        link.group = ungrouped
        s.ctx.insert(link)
        try s.ctx.save()

        s.migrator.migrateAll()

        let twins = try s.ctx.fetch(FetchDescriptor<Account>())
        #expect(twins.first?.group == nil)
    }
}
