import Foundation
import SwiftData
import Testing
@testable import millio

/// Слияние моделей групп `FinanceGroup` → канон `AccountGroup` (Фаза 1.5 плана 6b «Путь B»).
/// Перенос полей + идемпотентность + корректная per-group сумма по обоим мирам.
@Suite("GroupsMigrator (6b Фаза 1.5)")
@MainActor
struct GroupsMigratorTests {

    private struct Stack {
        let ctx: ModelContext
        let migrator: GroupsMigrator
        let flagDefaults: UserDefaults
    }

    private func makeStack() throws -> Stack {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let flagDefaults = UserDefaults(suiteName: "grp-mig-\(UUID().uuidString)")!
        let migrator = GroupsMigrator(modelContext: ctx, defaults: flagDefaults)
        return Stack(ctx: ctx, migrator: migrator, flagDefaults: flagDefaults)
    }

    @discardableResult
    private func seedFinanceGroup(
        _ ctx: ModelContext,
        name: String,
        colorHex: String = "#123456",
        order: Int = 0,
        isFavorite: Bool = false,
        usesManual: Bool = false,
        priority: GroupPriority = .normal,
        displayCurrency: String? = nil
    ) -> FinanceGroup {
        let g = FinanceGroup(name: name, colorHex: colorHex, order: order, isFavorite: isFavorite, priority: priority)
        g.usesManualAccountOrdering = usesManual
        g.displayCurrency = displayCurrency
        ctx.insert(g)
        return g
    }

    private func accountGroup(_ ctx: ModelContext, name: String) -> AccountGroup? {
        let d = FetchDescriptor<AccountGroup>(predicate: #Predicate<AccountGroup> { $0.name == name })
        return try? ctx.fetch(d).first
    }

    // MARK: - AC3: поля переносятся без потери

    @Test
    func migratesAllFieldsToCoreGroup() throws {
        let s = try makeStack()
        seedFinanceGroup(s.ctx, name: "Инвестиции", colorHex: "#FF8800", order: 3,
                         isFavorite: true, usesManual: true, priority: .high, displayCurrency: "USD")
        try s.ctx.save()

        let summary = s.migrator.migrateAll()

        #expect(summary.migrated == 1)
        let core = try #require(accountGroup(s.ctx, name: "Инвестиции"))
        #expect(core.isFavorite == true)
        #expect(core.usesManualAccountOrdering == true)
        #expect(core.priorityRaw == GroupPriority.high.rawValue)
        #expect(core.colorHex == "#FF8800")
        #expect(core.displayCurrency == "USD")
        #expect(core.order == 3)
        #expect(core.legacyFieldsMigratedAt != nil)
    }

    // MARK: - AC3: переиспользует существующую AccountGroup (по имени), не плодит дубли

    @Test
    func reusesExistingCoreGroupByName() throws {
        let s = try makeStack()
        let existing = AccountGroup(name: "Карты")
        s.ctx.insert(existing)
        seedFinanceGroup(s.ctx, name: "Карты", isFavorite: true, priority: .low)
        try s.ctx.save()

        s.migrator.migrateAll()

        let all = try s.ctx.fetch(FetchDescriptor<AccountGroup>(predicate: #Predicate { $0.name == "Карты" }))
        #expect(all.count == 1)
        #expect(all.first?.isFavorite == true)
        #expect(all.first?.priorityRaw == GroupPriority.low.rawValue)
    }

    // MARK: - AC4: повторный прогон — no-op, не затирает правки пользователя

    @Test
    func secondRunIsNoOpAndPreservesUserEdits() throws {
        let s = try makeStack()
        seedFinanceGroup(s.ctx, name: "Кредиты", isFavorite: true)
        try s.ctx.save()

        let first = s.migrator.migrateAll()
        #expect(first.migrated == 1)

        // Пользователь после миграции переключил избранное на core-группе.
        let core = try #require(accountGroup(s.ctx, name: "Кредиты"))
        core.isFavorite = false
        try s.ctx.save()

        let second = s.migrator.migrateAll()
        #expect(second.migrated == 0)
        #expect(second.skippedAlreadyMigrated == 1)
        // Правка пользователя НЕ затёрта повторным прогоном (маркер legacyFieldsMigratedAt держит).
        #expect(accountGroup(s.ctx, name: "Кредиты")?.isFavorite == false)
    }

    // MARK: - AC4: флаг-гейт короткого замыкания

    @Test
    func migrateIfNeededShortCircuitsSecondCall() throws {
        let s = try makeStack()
        seedFinanceGroup(s.ctx, name: "Наличные")
        try s.ctx.save()

        let first = s.migrator.migrateIfNeeded(scopeIdentifier: "user")
        #expect(first.migrated == 1)
        let second = s.migrator.migrateIfNeeded(scopeIdentifier: "user")
        #expect(second == GroupsMigrator.Summary())
    }

    // MARK: - Ungrouped не создаёт AccountGroup

    @Test
    func ungroupedGroupIsSkipped() throws {
        let s = try makeStack()
        seedFinanceGroup(s.ctx, name: FinanceSystemGroups.ungroupedName)
        try s.ctx.save()

        let summary = s.migrator.migrateAll()

        #expect(summary.migrated == 0)
        #expect(summary.skippedUngrouped == 1)
        #expect(accountGroup(s.ctx, name: FinanceSystemGroups.ungroupedName) == nil)
    }
}

/// Per-group сумма по счетам нового ядра (Фаза 1.5) — доказывает AC1 (группа целиком из core) и
/// AC2 (смешанная: сумма по обоим мирам считается сложением независимых вкладов).
@Suite("AccountsTotalsService per-group subset (Фаза 1.5)")
struct AccountsTotalsServicePerGroupTests {

    @Test @MainActor
    func totalForSubsetSumsOnlyGivenAccountsInTargetCurrency() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()
        rateService.todayRate = 100 // 1 USD = 100 RUB

        let groupA = AccountGroup(name: "A")
        ctx.insert(groupA)
        let a1 = try service.createAccount(name: "RUB", kind: .cash, currency: "RUB", openingBalance: 5000, group: groupA)
        let a2 = try service.createAccount(name: "USD", kind: .bankAccount, currency: "USD", openingBalance: 10, group: groupA)
        // Счёт вне группы A — НЕ должен попасть в per-group сумму.
        _ = try service.createAccount(name: "Чужой", kind: .cash, currency: "RUB", openingBalance: 99_999)

        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)
        let sum = await totals.total(for: [a1, a2], on: Date(), in: "RUB")

        #expect(sum == 6000) // 5000 + 10×100, «Чужой» исключён
    }

    @Test @MainActor
    func totalForEmptySubsetIsZero() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: DateAwareMockRateService())
        let sum = await totals.total(for: [], on: Date(), in: "RUB")
        #expect(sum == 0)
    }
}
