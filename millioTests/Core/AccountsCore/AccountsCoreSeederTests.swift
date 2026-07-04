import Foundation
import SwiftData
import Testing
@testable import millio

/// Тесты сид-полигона (план, риск П4): 10 счетов владельца, идемпотентность, ненулевой тотал.
@Suite("AccountsCoreSeeder")
struct AccountsCoreSeederTests {

    private func makeContainer() throws -> ModelContainer {
        try AppMigrationPlan.makeInMemoryContainer()
    }

    @Test @MainActor
    func seedCreatesTenRealAccounts() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let didSeed = try AccountsCoreSeeder.seedDemoPortfolio(context: ctx)
        #expect(didSeed == true)

        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.name != "__accounts_core_seed_v1__" }
        )
        let accounts = try ctx.fetch(descriptor)
        #expect(accounts.count == 10)
    }

    @Test @MainActor
    func seedIsIdempotent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let firstRun = try AccountsCoreSeeder.seedDemoPortfolio(context: ctx)
        let secondRun = try AccountsCoreSeeder.seedDemoPortfolio(context: ctx)
        #expect(firstRun == true)
        #expect(secondRun == false)

        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.name != "__accounts_core_seed_v1__" }
        )
        let accounts = try ctx.fetch(descriptor)
        #expect(accounts.count == 10) // повторный вызов не задублировал
    }

    @Test @MainActor
    func seedProducesNonZeroTotalToday() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = try AccountsCoreSeeder.seedDemoPortfolio(context: ctx)

        let rebuilder = AccountSnapshotRebuilder(modelContainer: container)
        let totals = AccountsTotalsService(modelContext: ctx, rebuilder: rebuilder, rateService: StubRateService())

        let total = await totals.totalAt(Date(), in: "RUB")
        #expect(total != 0)
    }
}

/// Курс 1:1 для всех валют — не тестируем конвертацию, только ненулевой тотал.
@MainActor
private final class StubRateService: CurrencyRateServiceProtocol {
    func getRate(from: String, to: String) async -> Double? { 1 }
    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? { 1 }
    func convert(amount: Double, from: String, to: String) async -> Double? { amount }
    func forceRefreshRates() async {}
}
