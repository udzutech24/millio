import Foundation
import SwiftData
import Testing
@testable import millio

/// AC1 (adjustBalance-дельта), AC12 (двуногий перевод + отмена только целиком),
/// AC9 (отрицательный баланс не обрезается) — единая точка записи `AccountsCoreService`.
@Suite("AccountsCoreService")
@MainActor
struct AccountsCoreServiceTests {

    /// ВАЖНО: возвращаем контейнер вместе с контекстом и держим его живым в вызывающем тесте —
    /// если контейнер деаллоцируется сразу после возврата функции, `mainContext` остаётся с
    /// разрушенным хранилищем и любая операция с ним крашит процесс (наблюдалось эмпирически).
    private func makeContext() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        return (container, container.mainContext)
    }

    // MARK: - AC1: adjustBalance создаёт дельту, события не теряются

    @Test
    func adjustBalanceCreatesDeltaEventAndKeepsHistory() throws {
        let (container, ctx) = try makeContext()
        _ = container // держим контейнер живым на время теста
        let service = AccountsCoreService(modelContext: ctx)

        let account = try service.createAccount(name: "Карта", kind: .debitCard, currency: "RUB", openingBalance: 1000)
        try service.recordEvent(account: account, type: .income, amount: 500)
        // текущий баланс 1500, правим на 2000 → должна появиться adjustment-дельта +500
        try service.adjustBalance(account: account, to: 2000)

        let events = account.events ?? []
        #expect(events.count == 3) // opening + income + adjustment
        let adjustmentEvent = events.first { $0.type == .adjustment }
        #expect(adjustmentEvent?.amount == 500)

        let balance = AccountBalanceEngine.balanceAt(events: events, kind: account.kind, on: Date())
        #expect(balance == 2000)
    }

    // MARK: - AC9: отрицательный баланс не обрезается max(0,...)

    @Test
    func recordEventAllowsNegativeBalance() throws {
        let (container, ctx) = try makeContext()
        _ = container // держим контейнер живым на время теста
        let service = AccountsCoreService(modelContext: ctx)

        let account = try service.createAccount(name: "Наличные", kind: .cash, currency: "RUB", openingBalance: 100)
        try service.recordEvent(account: account, type: .expense, amount: 500)

        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: Date())
        #expect(balance == -400)
    }

    // MARK: - Фаза 2: createAccount принимает loanMeta/debtMeta и создаёт корректную openingBalance

    @Test
    func createAccountWithLoanMetaStoresMetaAndNegativeOpeningBalance() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let meta = LoanMeta(principal: 100_000, rate: 9.5, monthlyPayment: 5_000, paymentDay: 5, termEnd: nil, scheduleType: .annuity, insurance: nil)
        let account = try service.createAccount(
            name: "Кредит", kind: .loan, currency: "RUB", openingBalance: 100_000, loanMeta: meta
        )

        #expect(account.loanMeta?.principal == 100_000)
        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: Date())
        #expect(balance == -100_000) // движок C сам делает знак минус из openingBalance
    }

    @Test
    func createAccountWithDebtMetaStoresDirection() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let meta = DebtMeta(direction: .owedByMe, counterparty: "Пётр", dueDate: nil, rate: nil)
        let account = try service.createAccount(
            name: "Долг", kind: .debt, currency: "RUB", openingBalance: -3000, debtMeta: meta
        )

        #expect(account.debtMeta?.direction == .owedByMe)
        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: Date())
        #expect(balance == -3000)
    }

    // MARK: - AC12: перевод — две ноги с общим transferID, Σ = 0 (в валюте источника), отмена — обеих ног

    @Test
    func transferCreatesTwoLegsSummingToZero() throws {
        let (container, ctx) = try makeContext()
        _ = container // держим контейнер живым на время теста
        let service = AccountsCoreService(modelContext: ctx)

        let source = try service.createAccount(name: "Карта RUB", kind: .debitCard, currency: "RUB", openingBalance: 10_000)
        let destination = try service.createAccount(name: "Счёт USD", kind: .bankAccount, currency: "USD", openingBalance: 0)

        // Decimal(string:), НЕ Decimal-литерал 0.011 — литерал идёт через Double (ExpressibleByFloatLiteral)
        // и даёт 10.999999999999997952 вместо точных 11 (классическая ловушка Decimal).
        let rate = Decimal(string: "0.011")! // 1 RUB = 0.011 USD
        let legs = try service.transfer(from: source, to: destination, amountInSourceCurrency: 1000, fxRate: rate)

        #expect(legs.out.transferID == legs.in.transferID)
        #expect(legs.out.amount == 1000)
        #expect(legs.in.amount == 11)

        // Приведённые к валюте источника (обратным курсом) ноги дают ровно 0 — атомарность перевода.
        let inConvertedBack = legs.in.amount! / rate
        #expect(-legs.out.amount! + inConvertedBack == 0)

        let sourceBalance = AccountBalanceEngine.balanceAt(events: source.events ?? [], kind: source.kind, on: Date())
        let destinationBalance = AccountBalanceEngine.balanceAt(events: destination.events ?? [], kind: destination.kind, on: Date())
        #expect(sourceBalance == 9000)
        #expect(destinationBalance == 11)
    }

    @Test
    func transferSameAccountThrows() throws {
        let (container, ctx) = try makeContext()
        _ = container // держим контейнер живым на время теста
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0)

        #expect(throws: AccountsCoreServiceError.self) {
            try service.transfer(from: account, to: account, amountInSourceCurrency: 100)
        }
    }

    @Test
    func transferDifferentCurrencyWithoutFxRateThrows() throws {
        let (container, ctx) = try makeContext()
        _ = container // держим контейнер живым на время теста
        let service = AccountsCoreService(modelContext: ctx)
        let source = try service.createAccount(name: "Карта RUB", kind: .cash, currency: "RUB", openingBalance: 1000)
        let destination = try service.createAccount(name: "Счёт USD", kind: .bankAccount, currency: "USD", openingBalance: 0)

        #expect(throws: AccountsCoreServiceError.self) {
            try service.transfer(from: source, to: destination, amountInSourceCurrency: 100)
        }
    }

    /// Удаление ОДНОЙ ноги перевода (через `deleteEvent`) стирает ОБЕ ноги — отменить перевод наполовину нельзя.
    @Test
    func deletingOneTransferLegDeletesBoth() throws {
        let (container, ctx) = try makeContext()
        _ = container // держим контейнер живым на время теста
        let service = AccountsCoreService(modelContext: ctx)

        let source = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 1000)
        let destination = try service.createAccount(name: "Счёт", kind: .bankAccount, currency: "RUB", openingBalance: 0)
        let legs = try service.transfer(from: source, to: destination, amountInSourceCurrency: 300)

        try service.deleteEvent(legs.out)

        let allEvents = try ctx.fetch(FetchDescriptor<AccountEvent>())
        #expect(allEvents.contains { $0.id == legs.out.id } == false)
        #expect(allEvents.contains { $0.id == legs.in.id } == false)

        let sourceBalance = AccountBalanceEngine.balanceAt(events: source.events ?? [], kind: source.kind, on: Date())
        #expect(sourceBalance == 1000) // перевод полностью отменён
    }

    // MARK: - updateEvent: правка задним числом инвалидирует кэш от минимальной даты

    @Test
    func updateEventChangesAmountAndDate() throws {
        let (container, ctx) = try makeContext()
        _ = container // держим контейнер живым на время теста
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0)
        let event = try service.recordEvent(account: account, type: .income, amount: 100)

        try service.updateEvent(event, amount: 250)

        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: Date())
        #expect(balance == 250)
    }

    // MARK: - archive/restore не меняют историю ДО archivedAt (AC6/AC7)

    @Test
    func archiveDoesNotAffectPastParticipation() throws {
        let (container, ctx) = try makeContext()
        _ = container // держим контейнер живым на время теста
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 100)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        #expect(account.participates(on: yesterday))

        try service.archiveAccount(account)

        #expect(account.participates(on: yesterday)) // прошлое не тронуто
        #expect(account.participates(on: Date()) == false) // сегодня — уже нет

        try service.restoreAccount(account)
        #expect(account.participates(on: Date()))
    }
}
