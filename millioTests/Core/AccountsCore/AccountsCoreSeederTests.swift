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
        #expect(accounts.count == 11) // 10 (Фаза 0/1) + 1 .debt (Фаза 2)
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
        #expect(accounts.count == 11) // повторный вызов не задублировал
    }

    /// Регрессия Фазы 2: `expense` в сиде раньше хранил ОТРИЦАТЕЛЬНОЕ число (двойное отрицание
    /// с cashLikeSignMap(.expense) == -1) — расход молча УВЕЛИЧИВАЛ баланс карты. Фиксируем точную
    /// сумму первой карты: 150 000 + 120 000 (income) − 45 000 (expense) − 12 000 (expense) = 213 000.
    @Test @MainActor
    func seedFirstCardBalanceReflectsExpenseAsSubtraction() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = try AccountsCoreSeeder.seedDemoPortfolio(context: ctx)

        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.name == "Основная карта" })
        let card = try #require(try ctx.fetch(descriptor).first)

        let balance = AccountBalanceEngine.balanceAt(events: card.events ?? [], kind: card.kind, on: Date())
        #expect(balance == 213_000)
    }

    /// Сид Фазы 2: `.loan` (Ипотека) уже отрицательный с правильным `loanMeta`, `.debt` (Долг Игоря)
    /// — новый счёт owedToMe с положительным балансом (мне должны).
    @Test @MainActor
    func seedLoanAndDebtHaveCorrectSignAndMeta() async throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        _ = try AccountsCoreSeeder.seedDemoPortfolio(context: ctx)

        let loanDescriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.name == "Ипотека" })
        let loan = try #require(try ctx.fetch(loanDescriptor).first)
        #expect(loan.kind == .loan)
        #expect(loan.loanMeta?.principal == 12_700_000)
        let loanBalance = AccountBalanceEngine.balanceAt(events: loan.events ?? [], kind: loan.kind, on: Date())
        #expect(loanBalance == -12_700_000)

        let debtDescriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.name == "Долг Игоря" })
        let debt = try #require(try ctx.fetch(debtDescriptor).first)
        #expect(debt.kind == .debt)
        #expect(debt.debtMeta?.direction == .owedToMe)
        let debtBalance = AccountBalanceEngine.balanceAt(events: debt.events ?? [], kind: debt.kind, on: Date())
        #expect(debtBalance == 500_000)
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
