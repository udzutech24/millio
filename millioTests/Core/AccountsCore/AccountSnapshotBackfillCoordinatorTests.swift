import Foundation
import SwiftData
import Testing
@testable import millio

/// Бэкфилл `AccountDailySnapshot` от первого события каждого счёта до сегодня (блокер Ф1
/// `plans/2026-07-05__account-detail-per-type.md`, Open Question №6 спеки). Проверяем: полное
/// покрытие истории, идемпотентность/one-shot флага, edge cases (без событий, архив, redenomination).
@Suite("AccountSnapshotBackfillCoordinator")
struct AccountSnapshotBackfillCoordinatorTests {

    private func makeContainer() throws -> ModelContainer {
        try AppMigrationPlan.makeInMemoryContainer()
    }

    private func day(_ offset: Int, base: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Date {
        base.addingTimeInterval(TimeInterval(offset) * 86_400)
    }

    private func fetchSnapshots(_ ctx: ModelContext, accountID: UUID) throws -> [AccountDailySnapshot] {
        try ctx.fetch(FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { $0.account?.id == accountID }
        ))
    }

    private func isolatedDefaults(_ testName: String) -> UserDefaults {
        let suiteName = "AccountSnapshotBackfillCoordinatorTests.\(testName).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Полное покрытие: от первого события до "сегодня"

    @Test @MainActor
    func backfillBuildsSnapshotsFromFirstEventToNow() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let defaults = isolatedDefaults(#function)

        let account = try service.createAccount(name: "Карта", kind: .debitCard, currency: "RUB", openingBalance: 100, date: day(0))
        try service.recordEvent(account: account, type: .income, amount: 50, date: day(10))
        try service.recordEvent(account: account, type: .expense, amount: 20, date: day(20))
        try ctx.save()

        let now = day(20)
        let coordinator = AccountSnapshotBackfillCoordinator(modelContainer: container, defaults: defaults, nowProvider: { now })
        let processed = await coordinator.backfillIfNeeded(scopeIdentifier: "test_user")
        #expect(processed == 1)

        let snapshots = try fetchSnapshots(ctx, accountID: account.id)
        // Checkpoint-ы кладутся только на дни событий (разреженный кэш) — day0, day10, day20.
        #expect(snapshots.count == 3)
        let latest = snapshots.max(by: { $0.dayKey < $1.dayKey })
        #expect(latest?.balance == 130) // 100 + 50 - 20
    }

    // MARK: - One-shot: флаг per-scope блокирует повторный забег, даже если появились новые события

    @Test @MainActor
    func secondCallIsNoOpOnceFlagIsSet() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let defaults = isolatedDefaults(#function)

        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0, date: day(0))
        try ctx.save()

        let coordinator = AccountSnapshotBackfillCoordinator(modelContainer: container, defaults: defaults, nowProvider: { self.day(5) })
        let firstRun = await coordinator.backfillIfNeeded(scopeIdentifier: "test_user")
        #expect(firstRun == 1)

        // Новое событие ПОСЛЕ первого забега — координатор больше не отвечает за него
        // (это зона существующего инкрементального пути AccountsTotalsService).
        try service.recordEvent(account: account, type: .income, amount: 500, date: day(6))
        try ctx.save()

        let secondRun = await coordinator.backfillIfNeeded(scopeIdentifier: "test_user")
        #expect(secondRun == 0) // флаг уже стоит — no-op

        let day6Key = AccountEvent.dayKey(for: day(6))
        let snapshots = try fetchSnapshots(ctx, accountID: account.id)
        #expect(!snapshots.contains { $0.dayKey == day6Key }) // подтверждает, что второй забег реально не выполнялся
    }

    @Test @MainActor
    func concurrentCallsShareOneBackfill() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let defaults = isolatedDefaults(#function)
        let account = try service.createAccount(
            name: "Карта",
            kind: .cash,
            currency: "RUB",
            openingBalance: 100,
            date: day(0)
        )
        try service.recordEvent(account: account, type: .income, amount: 50, date: day(1))
        try ctx.save()

        let coordinator = AccountSnapshotBackfillCoordinator(
            modelContainer: container,
            defaults: defaults,
            nowProvider: { self.day(1) }
        )
        async let first = coordinator.backfillIfNeeded(scopeIdentifier: "single-flight")
        async let second = coordinator.backfillIfNeeded(scopeIdentifier: "single-flight")
        let results = await [first, second]

        #expect(results == [1, 1])
        #expect(try fetchSnapshots(ctx, accountID: account.id).count == 2)
    }

    // MARK: - Разные scope НЕ делят один флаг

    @Test @MainActor
    func differentScopeIdentifiersRunIndependently() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let defaults = isolatedDefaults(#function)

        _ = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0, date: day(0))
        try ctx.save()

        let coordinator = AccountSnapshotBackfillCoordinator(modelContainer: container, defaults: defaults, nowProvider: { self.day(1) })
        let guestRun = await coordinator.backfillIfNeeded(scopeIdentifier: "millio_guest")
        let userRun = await coordinator.backfillIfNeeded(scopeIdentifier: "millio_user_abc")

        #expect(guestRun == 1)
        #expect(userRun == 1) // разный scopeIdentifier — свой флаг, не блокируется первым забегом
    }

    // MARK: - Edge case: счёт без единого события (не через сервис, напрямую) не роняет бэкфилл

    @Test @MainActor
    func accountWithoutEventsIsSkippedGracefully() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let defaults = isolatedDefaults(#function)

        // Обходим AccountsCoreService намеренно — он всегда создаёт якорное openingBalance-событие,
        // а нам нужен именно счёт БЕЗ единого события (защитный edge case).
        let account = Account(name: "Пустой счёт", kind: .cash, currency: "RUB", createdAt: day(0))
        ctx.insert(account)
        try ctx.save()

        let coordinator = AccountSnapshotBackfillCoordinator(modelContainer: container, defaults: defaults, nowProvider: { self.day(5) })
        let processed = await coordinator.backfillIfNeeded(scopeIdentifier: "test_user")
        #expect(processed == 1) // счёт обработан (без ошибки), просто нечего строить

        let snapshots = try fetchSnapshots(ctx, accountID: account.id)
        #expect(snapshots.isEmpty)
    }

    // MARK: - Архивный счёт: бэкфилл не строит checkpoint-ы после archivedAt

    @Test @MainActor
    func archivedAccountBackfillStopsAtArchiveDate() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let defaults = isolatedDefaults(#function)

        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 100, date: day(0))
        try service.recordEvent(account: account, type: .income, amount: 50, date: day(5))
        try service.recordEvent(account: account, type: .income, amount: 50, date: day(15))
        account.archivedAt = day(5)
        try ctx.save()

        let coordinator = AccountSnapshotBackfillCoordinator(modelContainer: container, defaults: defaults, nowProvider: { self.day(20) })
        let processed = await coordinator.backfillIfNeeded(scopeIdentifier: "test_user")
        #expect(processed == 1)

        let snapshots = try fetchSnapshots(ctx, accountID: account.id)
        let day15Key = AccountEvent.dayKey(for: day(15))
        #expect(!snapshots.contains { $0.dayKey == day15Key }) // после архивации счёт не участвует — checkpoint не строится
        #expect(snapshots.count == 2) // day0, day5 (день закрытия — граничный, остаётся)
    }

    // MARK: - Redenomination: бэкфилл сохраняет пост-деноминационные значения (AC11/AC15)

    @Test @MainActor
    func redenominationCaseBackfillsConvertedBalance() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let defaults = isolatedDefaults(#function)

        let account = try service.createAccount(name: "Счёт", kind: .bankAccount, currency: "RUB", openingBalance: 1000, date: day(0))
        // Редоминация напрямую через AccountEvent — у AccountsCoreService нет отдельного метода записи
        // (см. AccountBalanceEngineTests.redenomination_* — та же прямая конструкция события в тестах ядра).
        let redenom = AccountEvent(account: account, date: day(2), type: .redenomination, redenomRate: Decimal(string: "0.001")!, redenomFromCurrency: "OLD")
        ctx.insert(redenom)
        try service.recordEvent(account: account, type: .income, amount: 5, date: day(3))
        try ctx.save()

        let coordinator = AccountSnapshotBackfillCoordinator(modelContainer: container, defaults: defaults, nowProvider: { self.day(3) })
        let processed = await coordinator.backfillIfNeeded(scopeIdentifier: "test_user")
        #expect(processed == 1)

        let snapshots = try fetchSnapshots(ctx, accountID: account.id)
        let latest = snapshots.max(by: { $0.dayKey < $1.dayKey })
        // 1000 * 0.001 (переоценено в новую валюту) + 5 = 6 — совпадает с прямым реплеем AccountBalanceEngine.
        let expectedBalance: Decimal = 6
        #expect(latest?.balance == expectedBalance)
    }

    // MARK: - Несколько счетов: каждый обрабатывается независимо

    @Test @MainActor
    func multipleAccountsAreAllProcessed() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let defaults = isolatedDefaults(#function)

        let accountA = try service.createAccount(name: "A", kind: .cash, currency: "RUB", openingBalance: 10, date: day(0))
        let accountB = try service.createAccount(name: "B", kind: .cash, currency: "RUB", openingBalance: 20, date: day(0))
        let accountC = try service.createAccount(name: "C", kind: .cash, currency: "RUB", openingBalance: 30, date: day(0))
        try ctx.save()

        let coordinator = AccountSnapshotBackfillCoordinator(modelContainer: container, defaults: defaults, nowProvider: { self.day(1) })
        let processed = await coordinator.backfillIfNeeded(scopeIdentifier: "test_user")
        #expect(processed == 3)

        for account in [accountA, accountB, accountC] {
            let snapshots = try fetchSnapshots(ctx, accountID: account.id)
            #expect(snapshots.count == 1)
        }
    }
}
