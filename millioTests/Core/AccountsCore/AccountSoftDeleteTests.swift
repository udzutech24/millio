import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5/Q1: удаление счёта — мягкое (tombstone `deletedAt`), история графика НЕИЗМЕННА.
/// Доказываем три инварианта: (а) точки серии ДО даты удаления не меняются; (б) вклад ПОСЛЕ
/// удаления = 0 (не «последний баланс»); (в) счёт исчезает из тотала «сегодня» и из списка архива.
@Suite("AccountSoftDelete")
struct AccountSoftDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        try AppMigrationPlan.makeInMemoryContainer()
    }

    private func day(_ offset: Int, base: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Date {
        base.addingTimeInterval(TimeInterval(offset) * 86_400)
    }

    // MARK: - participates(on:) — deletedAt как жёсткая отсечка

    @Test
    func participatesRespectsDeletedAtCutoff() {
        let acc = Account(name: "X", kind: .cash, currency: "RUB")
        acc.deletedAt = day(5)
        #expect(acc.participates(on: day(3)) == true)   // до удаления — участвует
        #expect(acc.participates(on: day(5)) == false)  // ровно в дату — уже нет
        #expect(acc.participates(on: day(6)) == false)  // после — нет
    }

    @Test
    func participatesUsesEarliestOfArchivedAndDeleted() {
        let acc = Account(name: "X", kind: .cash, currency: "RUB")
        acc.archivedAt = day(2)
        acc.deletedAt = day(5)
        // Берём самую раннюю отсечку — архивация раньше удаления.
        #expect(acc.participates(on: day(3)) == false)
        #expect(acc.participates(on: day(1)) == true)
    }

    // MARK: - Тоталы: прошлое неизменно, будущее = 0

    @Test @MainActor
    func softDeleteKeepsPastTotalAndZeroesFutureContribution() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()

        _ = try service.createAccount(name: "Выживший", kind: .cash, currency: "RUB", openingBalance: 1000, date: day(0))
        let victim = try service.createAccount(name: "Удаляемый", kind: .cash, currency: "RUB", openingBalance: 500, date: day(0))

        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)

        // Базовая точка ДО удаления — оба счёта в сумме.
        let pastBefore = await totals.totalAt(day(3), in: "RUB")
        #expect(pastBefore == 1500)

        try service.softDelete(victim, on: day(5))

        // (а) точка ДО даты удаления не изменилась.
        let pastAfter = await totals.totalAt(day(3), in: "RUB")
        #expect(pastAfter == 1500)

        // (б) вклад ПОСЛЕ удаления = 0 (не 500 «последним балансом»), остаётся только выживший.
        let future = await totals.totalAt(day(6), in: "RUB")
        #expect(future == 1000)

        // (в-часть) в тотале «сегодня» удалённого нет.
        let today = await totals.totalAt(Date(), in: "RUB")
        #expect(today == 1000)
    }

    @Test @MainActor
    func softDeleteDoesNotShiftSurvivorSeriesPoints() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let rateService = DateAwareMockRateService()

        _ = try service.createAccount(name: "Выживший", kind: .cash, currency: "RUB", openingBalance: 1000, date: day(0))
        let victim = try service.createAccount(name: "Удаляемый", kind: .cash, currency: "RUB", openingBalance: 500, date: day(0))

        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: rateService)
        let baseline = await totals.seriesBetween(start: day(0), end: day(4), currency: "RUB")

        try service.softDelete(victim, on: day(10)) // удаление ПОЗЖЕ окна серии

        let afterDelete = await totals.seriesBetween(start: day(0), end: day(4), currency: "RUB")
        #expect(afterDelete.map(\.1) == baseline.map(\.1)) // все точки прошлого идентичны
        #expect(afterDelete.allSatisfy { $0.1 == 1500 })
    }

    // MARK: - (в) счёт исчезает из списка архива

    @Test @MainActor
    func softDeletedAccountLeavesArchiveList() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)

        let acc = try service.createAccount(name: "Архивный", kind: .cash, currency: "RUB", openingBalance: 100)
        try service.archiveAccount(acc)

        // До удаления — в списке архива (тот же предикат, что ArchivedAccountsView / hasArchivedNewCoreAccounts).
        let archivedPredicate = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.archivedAt != nil && $0.deletedAt == nil }
        )
        #expect(((try? ctx.fetchCount(archivedPredicate)) ?? -1) == 1)

        try service.softDelete(acc)

        // После — исчез из списка архива.
        #expect(((try? ctx.fetchCount(archivedPredicate)) ?? -1) == 0)
        // Но сам счёт (и его история) в БД сохранён — не каскадный снос.
        #expect(((try? ctx.fetchCount(FetchDescriptor<Account>())) ?? 0) == 1)
    }

    // MARK: - Backup round-trip deletedAt

    @Test @MainActor
    func deletedAtSurvivesBackupExportImport() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let service = AccountsCoreService(modelContext: ctx)

        let acc = try service.createAccount(name: "Удалённый", kind: .cash, currency: "RUB", openingBalance: 0)
        try service.softDelete(acc, on: day(5))

        let data = try acc.export()
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("export не дал словарь"); return
        }
        #expect(dict["deletedAt"] != nil)

        // Импорт в чистый контекст — deletedAt должен восстановиться.
        let fresh = try makeContainer()
        try AccountImporter.import(from: dict, context: fresh.mainContext)
        let imported = try fresh.mainContext.fetch(FetchDescriptor<Account>())
        #expect(imported.count == 1)
        #expect(imported.first?.deletedAt != nil)
    }
}
