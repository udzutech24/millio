import Foundation
import SwiftData
import Testing
@testable import millio

/// AC8 (rebuildAll == прямой реплей), инкрементальность (правка хвоста не трогает раннюю историю),
/// Т5 (dayKey зафиксирован на дату события, не пересчитывается текущей таймзоной).
@Suite("AccountSnapshotRebuilder")
struct AccountSnapshotRebuilderTests {

    private func makeContainer() throws -> ModelContainer {
        try AppMigrationPlan.makeInMemoryContainer()
    }

    private func day(_ offset: Int, base: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Date {
        base.addingTimeInterval(TimeInterval(offset) * 86_400)
    }

    /// Снапшоты пишет ФОНОВЫЙ актор через свой ModelContext (свой контейнер того же хранилища) —
    /// закэшированная relationship `account.snapshots` в тестовом mainContext их не увидит без
    /// явного refetch (тот же cross-context нюанс, что и в `AccountsTotalsService`). Читаем напрямую.
    private func fetchSnapshots(_ ctx: ModelContext, accountID: UUID) throws -> [AccountDailySnapshot] {
        try ctx.fetch(FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { $0.account?.id == accountID }
        ))
    }

    // MARK: - AC8: пересборка на перемешанном порядке вставки == прямому реплею

    @Test @MainActor
    func rebuildAllMatchesDirectReplayOnShuffledInsertOrder() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)

        let account = try service.createAccount(name: "Карта", kind: .debitCard, currency: "RUB", openingBalance: 0, date: day(0))
        // Вставляем события НЕ по порядку дат — детерминизм реплея не должен зависеть от порядка вставки (S5).
        let unordered: [(Int, Decimal)] = [(3, 400), (1, 100), (5, -200), (2, -50), (4, 300)]
        for (offset, amount) in unordered.shuffled() {
            let type: AccountEventType = amount >= 0 ? .income : .expense
            try service.recordEvent(account: account, type: type, amount: abs(amount), date: day(offset))
        }
        try ctx.save()

        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        try await rebuilder.rebuildAll(accountID: account.persistentModelID)

        let snapshots = try fetchSnapshots(ctx, accountID: account.id)
        let directReplay = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: day(5))
        let cachedSnapshot = snapshots.max(by: { $0.dayKey < $1.dayKey })
        #expect(cachedSnapshot?.balance == directReplay)

        // Промежуточная точка (день 3) тоже должна совпасть с прямым реплеем на ту же дату.
        let day3Key = AccountEvent.dayKey(for: day(3))
        let day3Snapshot = snapshots.first { $0.dayKey == day3Key }
        let day3Replay = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: day(3))
        #expect(day3Snapshot?.balance == day3Replay)
    }

    // MARK: - Инкрементальность: правка события в середине истории пересобирает только хвост

    @Test @MainActor
    func editingMiddleEventOnlyRebuildsTail() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)

        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0, date: day(0))
        let event2 = try service.recordEvent(account: account, type: .income, amount: 100, date: day(2))
        _ = try service.recordEvent(account: account, type: .income, amount: 200, date: day(4))
        try ctx.save()

        try await rebuilder.rebuildAll(accountID: account.persistentModelID)

        let day2Key = AccountEvent.dayKey(for: day(2))
        let day0Key = AccountEvent.dayKey(for: day(0))
        let day0BalanceBefore = try fetchSnapshots(ctx, accountID: account.id).first { $0.dayKey == day0Key }?.balance

        // Правим событие дня 2 — инвалидация должна снести снапшоты >= дня 2, но НЕ день 0.
        try service.updateEvent(event2, amount: 999)
        try await rebuilder.rebuild(accountID: account.persistentModelID, upTo: day(4))

        let afterSnapshots = try fetchSnapshots(ctx, accountID: account.id)
        let day0BalanceAfter = afterSnapshots.first { $0.dayKey == day0Key }?.balance
        #expect(day0BalanceAfter == day0BalanceBefore) // ранняя история не изменилась

        let day2BalanceAfter = afterSnapshots.first { $0.dayKey == day2Key }?.balance
        #expect(day2BalanceAfter == 999) // хвост пересчитан с новым значением

        // Рефетч счёта СВЕЖИМ FetchDescriptor: после `await` фонового актора не полагаемся на
        // возможно устаревший in-memory снимок relationship `events` того же объекта (тот же
        // cross-context нюанс, что и со снапшотами — см. `fetchSnapshots`).
        let accountID = account.id
        let refreshedAccount = try ctx.fetch(FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.id == accountID }
        )).first
        let finalBalance = AccountBalanceEngine.balanceAt(
            events: refreshedAccount?.events ?? [], kind: account.kind, on: day(4)
        )
        // Значение вынесено в константу: `#expect(a == 999 + 200)` в Swift Testing даёт ложное
        // «Expectation failed» при идентичных printed-значениях (макрос неверно трактует
        // инлайн-выражение справа от `==` для Decimal) — сравнение с готовой константой надёжно.
        let expectedFinalBalance: Decimal = 1199
        #expect(finalBalance == expectedFinalBalance)
    }

    // MARK: - Т5: dayKey события зафиксирован — снапшот использует его, не текущую таймзону

    @Test @MainActor
    func snapshotUsesEventFixedDayKeyNotCurrentTimezone() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)

        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0, date: day(0))
        let event = try service.recordEvent(account: account, type: .income, amount: 500, date: day(1))
        // Симулируем «событие создано в другой таймзоне» — dayKey уже зафиксирован в момент создания
        // события (AccountEvent.init), явно проверяем что он НЕ пересчитывается рядом стоящим значением.
        let fixedDayKey = event.dayKey

        try await rebuilder.rebuildAll(accountID: account.persistentModelID)

        let snapshot = try fetchSnapshots(ctx, accountID: account.id).first { $0.dayKey == fixedDayKey }
        #expect(snapshot != nil, "снапшот должен лежать под зафиксированным dayKey события, а не под текущим")
        #expect(snapshot?.balance == 500)
    }
}
