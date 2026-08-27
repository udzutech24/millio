import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф1 плана `2026-08-26__deposit-confirmed-balance-unification.md`: единый подтверждённый баланс
/// вклада во всех потребителях. До фикса строка списка/тоталы/снапшоты показывали 13 141 138,
/// а деталка того же вклада — 13 000 000.
@Suite("Deposit confirmed balance resolver", .serialized)
@MainActor
struct DepositConfirmedBalanceResolverTests {

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let accountID: UUID
        let opening: Date
        let calendar: Calendar
    }

    /// Вклад 100 000 ₽ под 12% с ежемесячной капитализацией, открыт 01.01.2025 на 3 месяца.
    /// Прогнозные начисления: 01.02 (1 000), 01.03 (1 010), 01.04 (1 020.10).
    private func fixture() throws -> Fixture {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let maturity = calendar.date(byAdding: .month, value: 3, to: opening)!
        let accountID = try AccountProductFactory(modelContext: context).create(CreateProductCommand(
            productType: .deposit, name: "Deposit", currency: "RUB", openingBalance: 100_000,
            metadata: .init(deposit: DepositMeta(
                rate: 12, capitalization: .monthly, termEnd: maturity, payoutDay: nil,
                allowsTopUp: true, allowsEarlyClose: true, earlyClosePenalty: nil,
                remindEnd: false, autoRollover: false
            )),
            date: opening, calendar: calendar
        ))
        try context.save()
        return Fixture(
            container: container, context: context, accountID: accountID,
            opening: opening, calendar: calendar
        )
    }

    private func deposit(_ fixture: Fixture) throws -> Account {
        try #require(fixture.context.fetch(FetchDescriptor<Account>()).first { $0.id == fixture.accountID })
    }

    private func contractBalance(_ fixture: Fixture, asOf: Date) throws -> Decimal {
        let account = try deposit(fixture)
        let snapshot = DepositFinancialContract.snapshot(
            accountID: account.id,
            currency: account.currency,
            openingDate: account.createdAt,
            meta: account.depositMeta,
            events: account.events ?? [],
            asOf: asOf,
            calendarPolicy: DepositCalendarPolicy(timeZone: TimeZone(identifier: "UTC")!)
        )
        return try #require(snapshot.currentBalance.value)
    }

    /// Инвариант 1 плана: строка списка «Счета» == «Текущий баланс» деталки.
    @Test("Строка списка совпадает с текущим балансом деталки после наступления прогноза")
    func listRowMatchesContractCurrentBalance() throws {
        let fixture = try fixture()
        // 15.02: прогноз от 01.02 уже «в прошлом» — ровно та точка, где раньше цифры расходились.
        let asOf = fixture.calendar.date(from: DateComponents(year: 2025, month: 2, day: 15))!
        let account = try deposit(fixture)

        let viewModel = FinanceViewModel(
            modelContext: fixture.context,
            currencyService: MockCurrencyRateService(),
            now: { asOf },
            skipInitialLoad: true
        )
        let listValue = viewModel.newCoreBalanceToday(account)

        #expect(listValue == 100_000)
        #expect(try contractBalance(fixture, asOf: asOf) == listValue)
        // Регресс: сырой реплей той же ленты даёт старую, завышенную цифру.
        #expect(AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .deposit, on: asOf) == 101_000)
    }

    /// Инвариант 2 плана: тотал использует тот же confirmed-баланс, что и контракт.
    @Test("totalAt использует тот же подтверждённый баланс, что и контракт")
    func totalAtMatchesContractCurrentBalance() async throws {
        let fixture = try fixture()
        let asOf = fixture.calendar.date(from: DateComponents(year: 2025, month: 2, day: 15))!
        let totals = AccountsTotalsService(
            modelContext: fixture.context,
            rebuilder: AccountSnapshotRebuilder(modelContainer: fixture.container),
            rateService: DateAwareMockRateService()
        )

        let total = await totals.totalAt(asOf, in: "RUB")

        #expect(total == 100_000)
        #expect(try contractBalance(fixture, asOf: asOf) == total)
    }

    /// Acceptance criterion 2: фильтр работает относительно ЗАДАННОЙ даты, а не только «сегодня».
    @Test("Исторический баланс не включает прогноз, сгенерированный после этой даты")
    func historicalBalanceExcludesLaterForecast() throws {
        let fixture = try fixture()
        let account = try deposit(fixture)
        let midMarch = fixture.calendar.date(from: DateComponents(year: 2025, month: 3, day: 15))!
        let midJanuary = fixture.calendar.date(from: DateComponents(year: 2025, month: 1, day: 15))!

        #expect(DepositConfirmedBalanceResolver.balanceAt(
            events: account.events ?? [], accountID: account.id, on: midMarch
        ) == 100_000)
        #expect(DepositConfirmedBalanceResolver.balanceAt(
            events: account.events ?? [], accountID: account.id, on: midJanuary
        ) == 100_000)
    }

    /// Граница «в прошлом» — по ВРЕМЕНИ, а не по dayKey (кейс ежедневной капитализации «Фридом»).
    @Test("Подтверждённое начисление входит в баланс ровно с момента своей даты")
    func confirmedInterestEntersBalanceByInstantNotDayKey() throws {
        let fixture = try fixture()
        let payout = fixture.calendar.date(from: DateComponents(year: 2025, month: 2, day: 1))!
        DepositInterestConfirmationSweep.run(context: fixture.context, asOf: payout)
        let account = try deposit(fixture)

        let justBefore = fixture.calendar.date(byAdding: .second, value: -1, to: payout)!
        #expect(DepositConfirmedBalanceResolver.balanceAt(
            events: account.events ?? [], accountID: account.id, on: justBefore
        ) == 100_000)
        #expect(DepositConfirmedBalanceResolver.balanceAt(
            events: account.events ?? [], accountID: account.id, on: payout
        ) == 101_000)
    }

    /// Интеграционный тест ПУТИ СОЗДАНИЯ (урок Ф7b-2, `millio-integration-test-creation-path`):
    /// проверяется не трансформация, а реальный `AccountProductFactory` + чтение потребителями.
    @Test("Путь создания вклада: список и тотал сразу показывают только внесённую сумму")
    func creationPathShowsOnlyPrincipal() async throws {
        let fixture = try fixture()
        let account = try deposit(fixture)
        let atOpening = fixture.calendar.date(byAdding: .hour, value: 1, to: fixture.opening)!

        // Фабрика сразу кладёт всё расписание в ленту — весь смысл инварианта в том, чтобы
        // ни одна из этих трёх точек чтения не приняла расписание за деньги на счёте.
        #expect((account.events ?? []).filter { $0.type == .interest }.count == 3)

        let viewModel = FinanceViewModel(
            modelContext: fixture.context,
            currencyService: MockCurrencyRateService(),
            now: { atOpening },
            skipInitialLoad: true
        )
        let totals = AccountsTotalsService(
            modelContext: fixture.context,
            rebuilder: AccountSnapshotRebuilder(modelContainer: fixture.container),
            rateService: DateAwareMockRateService()
        )

        #expect(viewModel.newCoreBalanceToday(account) == 100_000)
        #expect(try contractBalance(fixture, asOf: atOpening) == 100_000)
        #expect(await totals.totalAt(atOpening, in: "RUB") == 100_000)
    }

    /// Регресс из раздела «Снапшоты» плана: пересобранный кэш обязан хранить confirmed-значения,
    /// иначе завышенные балансы переживут бэкап/restore (`AccountDailySnapshotImporter`).
    @Test("Пересобранные снапшоты содержат подтверждённые значения")
    func rebuiltSnapshotsAreConfirmed() async throws {
        let fixture = try fixture()
        let account = try deposit(fixture)
        let rebuilder = AccountSnapshotRebuilder(modelContainer: fixture.container)

        try await rebuilder.rebuildAll(accountID: account.persistentModelID)

        let snapshots = try fixture.context.fetch(FetchDescriptor<AccountDailySnapshot>())
            .filter { $0.account?.id == account.id }
        #expect(!snapshots.isEmpty)
        #expect(snapshots.allSatisfy { $0.balance == 100_000 })
        // Дни, где событием был только прогноз, checkpoint-а не получают.
        #expect(snapshots.count == 1)
    }
}
