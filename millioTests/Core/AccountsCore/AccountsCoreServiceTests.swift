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

    // MARK: - Фаза 3: earlyCloseDeposit — сторно % по penalty, перевод остатка, архивация

    @Test
    func earlyCloseDepositAppliesPenaltyTransfersRemainderAndArchives() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let deposit = try service.createAccount(name: "Вклад", kind: .deposit, currency: "RUB", openingBalance: 1_000_000)
        deposit.depositMeta = DepositMeta(
            rate: 12, capitalization: .monthly, termEnd: nil, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: true, earlyClosePenalty: 0.5, // 50% удержания
            remindEnd: false, autoRollover: false
        )
        // Начислено 10 000 ₽ процентов (руками, без генератора — сценарий уже накопленного вклада).
        ctx.insert(AccountEvent(account: deposit, date: Date(), type: .interest, amount: 10_000))
        try ctx.save()

        let destination = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0)

        let balanceBeforeClose = AccountBalanceEngine.balanceAt(events: deposit.events ?? [], kind: .deposit, on: Date())
        #expect(balanceBeforeClose == 1_010_000)

        try service.earlyCloseDeposit(deposit, transferTo: destination)

        // Сторно = 10 000 × 0.5 = 5 000 (fee), остаток переведён на destination.
        let feeEvent = (deposit.events ?? []).first { $0.type == .fee }
        #expect(feeEvent?.amount == 5_000)

        let destinationBalance = AccountBalanceEngine.balanceAt(events: destination.events ?? [], kind: .cash, on: Date())
        #expect(destinationBalance == 1_005_000) // 1 010 000 − 5 000 удержано

        #expect(deposit.archivedAt != nil) // архивация — НЕ удаление, история сохранена (AC7)
        #expect((deposit.events ?? []).count > 2) // opening + interest + fee + transferOut остались
    }

    @Test
    func earlyCloseDepositWithoutPenaltyTransfersFullBalance() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let deposit = try service.createAccount(name: "Накопительный", kind: .deposit, currency: "RUB", openingBalance: 200_000)
        deposit.depositMeta = DepositMeta(
            rate: 8, capitalization: .monthly, termEnd: nil, payoutDay: nil,
            allowsTopUp: true, allowsEarlyClose: true, earlyClosePenalty: nil, // без потери %
            remindEnd: false, autoRollover: false
        )
        let destination = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0)

        try service.earlyCloseDeposit(deposit, transferTo: destination)

        let destinationBalance = AccountBalanceEngine.balanceAt(events: destination.events ?? [], kind: .cash, on: Date())
        #expect(destinationBalance == 200_000) // без штрафа — весь остаток
        #expect((deposit.events ?? []).first { $0.type == .fee } == nil)
    }

    // MARK: - Фаза 4: buy/sell/dividend/fee/revalue

    @Test
    func buyCreatesEventAndIncreasesQuantity() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let account = try service.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "AAPL", assetClass: .stock)
        )
        try service.buy(account: account, quantity: 10, unitPrice: 150)

        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .marketInvestment, on: Date(), marketMeta: account.marketMeta)
        #expect(balance == 1500) // 10 × 150 (без provider — fallback на lastKnown buy-цену)
    }

    @Test
    func sellReducesQuantityAndAllowsExceedingCurrentHolding() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let account = try service.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "AAPL", assetClass: .stock)
        )
        try service.buy(account: account, quantity: 5, unitPrice: 100)
        // Продажа БОЛЬШЕ остатка — не жёсткий запрет (брифинг Фазы 4, задача 4): сервис не бросает ошибку.
        try service.sell(account: account, quantity: 8, unitPrice: 120)

        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .marketInvestment, on: Date(), marketMeta: account.marketMeta)
        #expect(balance == -360) // quantity = -3 × 120
    }

    @Test
    func buySellRejectedForNonMarketKind() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0)

        #expect(throws: AccountsCoreServiceError.self) {
            try service.buy(account: account, quantity: 1, unitPrice: 1)
        }
    }

    /// Task 6: dividend/fee — информационные события, НЕ меняют quantity/баланс движка E.
    @Test
    func recordMarketCashEventDoesNotAffectMarketBalance() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "AAPL", assetClass: .stock)
        )
        try service.buy(account: account, quantity: 10, unitPrice: 100)
        let balanceBefore = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .marketInvestment, on: Date(), marketMeta: account.marketMeta)

        try service.recordMarketCashEvent(account: account, type: .dividend, amount: 50)
        try service.recordMarketCashEvent(account: account, type: .fee, amount: 5)

        let balanceAfter = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .marketInvestment, on: Date(), marketMeta: account.marketMeta)
        #expect(balanceAfter == balanceBefore)
        #expect((account.events ?? []).filter { $0.type == .dividend || $0.type == .fee }.count == 2)
    }

    @Test
    func recordMarketCashEventRejectsUnsupportedType() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "AAPL", assetClass: .stock)
        )
        #expect(throws: AccountsCoreServiceError.self) {
            try service.recordMarketCashEvent(account: account, type: .income, amount: 10)
        }
    }

    @Test
    func revalueUpdatesManualAssetBalance() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Квартира", kind: .manualAsset, currency: "RUB", openingBalance: 17_000_000)

        try service.revalue(account: account, newValue: 20_000_000)

        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .manualAsset, on: Date())
        #expect(balance == 20_000_000)
    }

    /// Переоценка задним числом меняет точки от своей даты вперёд, но НЕ трогает точки ДО неё
    /// (брифинг Фазы 4, задача 6, блок F) — движок сам берёт последнюю revaluation ≤date.
    @Test
    func revalueBackdatedDoesNotChangeEarlierPoints() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        // openingBalance ДОЛЖЕН быть раньше первой переоценки — иначе balanceBeforeFirstRevaluation
        // проверяла бы точку ДО существования счёта (реальная ошибка сборки теста, не движка).
        let account = try service.createAccount(
            name: "Квартира", kind: .manualAsset, currency: "RUB", openingBalance: 17_000_000,
            date: Date().addingTimeInterval(-60 * 86_400)
        )

        let earlierDate = Date().addingTimeInterval(-30 * 86_400)
        try service.revalue(account: account, newValue: 18_000_000, date: earlierDate)
        try service.revalue(account: account, newValue: 20_000_000) // сегодня

        let balanceBeforeFirstRevaluation = AccountBalanceEngine.balanceAt(
            events: account.events ?? [], kind: .manualAsset, on: earlierDate.addingTimeInterval(-1)
        )
        let balanceToday = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .manualAsset, on: Date())

        #expect(balanceBeforeFirstRevaluation == 17_000_000) // opening — до первой переоценки
        #expect(balanceToday == 20_000_000)
    }

    @Test
    func revalueRejectedForNonManualAssetKind() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0)

        #expect(throws: AccountsCoreServiceError.self) {
            try service.revalue(account: account, newValue: 1000)
        }
    }

    // MARK: - Фаза 5, задача 3: физическое удаление и целостность переводов (S2)

    /// A→B перевод, удаляем A навсегда → у B баланс НЕ меняется, нога B стала income без transferID
    /// (иначе баланс B продолжал бы включать сумму, «прилетевшую в никуда» — S2 в плане).
    @Test
    func physicallyDeleteConvertsSurvivorTransferLegToIncomeAndPreservesBalance() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let accountA = try service.createAccount(name: "A", kind: .cash, currency: "RUB", openingBalance: 1000)
        let accountB = try service.createAccount(name: "B", kind: .cash, currency: "RUB", openingBalance: 0)
        try service.transfer(from: accountA, to: accountB, amountInSourceCurrency: 300)

        let balanceBeforeDelete = AccountBalanceEngine.balanceAt(events: accountB.events ?? [], kind: accountB.kind, on: Date())
        #expect(balanceBeforeDelete == 300)

        try service.physicallyDelete(accountA)

        let balanceAfterDelete = AccountBalanceEngine.balanceAt(events: accountB.events ?? [], kind: accountB.kind, on: Date())
        #expect(balanceAfterDelete == 300) // инвариант: баланс выжившего счёта не изменился

        let survivorEvents = accountB.events ?? []
        #expect(survivorEvents.count == 2) // opening + бывший transferIn
        let convertedLeg = survivorEvents.first { $0.type == .income }
        #expect(convertedLeg != nil)
        #expect(convertedLeg?.transferID == nil) // больше не перевод
        #expect(convertedLeg?.note?.contains("A") == true) // пометка с именем удалённого счёта
    }

    /// Симметричный случай: удаляем ПОЛУЧАТЕЛЯ (B) — нога источника (A) должна стать expense.
    @Test
    func physicallyDeleteConvertsSourceLegToExpenseWhenDestinationDeleted() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let accountA = try service.createAccount(name: "A", kind: .cash, currency: "RUB", openingBalance: 1000)
        let accountB = try service.createAccount(name: "B", kind: .cash, currency: "RUB", openingBalance: 0)
        try service.transfer(from: accountA, to: accountB, amountInSourceCurrency: 300)

        try service.physicallyDelete(accountB)

        let balanceA = AccountBalanceEngine.balanceAt(events: accountA.events ?? [], kind: accountA.kind, on: Date())
        #expect(balanceA == 700) // 1000 - 300, как и было до удаления B

        let survivorEvents = accountA.events ?? []
        let convertedLeg = survivorEvents.first { $0.type == .expense }
        #expect(convertedLeg != nil)
        #expect(convertedLeg?.transferID == nil)
    }

    /// Удаление счёта без переводов — просто каскад events+snapshots, без побочных эффектов на другие счета.
    @Test
    func physicallyDeleteWithoutTransfersJustCascades() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let account = try service.createAccount(name: "Соло", kind: .cash, currency: "RUB", openingBalance: 500)
        try service.recordEvent(account: account, type: .income, amount: 100)

        try service.physicallyDelete(account)

        let remaining = try ctx.fetch(FetchDescriptor<Account>())
        #expect(remaining.isEmpty)
        let remainingEvents = try ctx.fetch(FetchDescriptor<AccountEvent>())
        #expect(remainingEvents.isEmpty) // каскад унёс события удалённого счёта
    }
}
