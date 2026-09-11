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

    /// Ф2 плана `2026-08-26__deposit-confirmed-balance-unification.md`: у вклада свой контракт
    /// корректировки (`DepositOperationCoordinator`), генерик-путь обязан отказать явно, а не
    /// молча посчитать дельту от сырого баланса с прогнозными начислениями.
    @Test
    func adjustBalanceRejectsDeposit() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let deposit = try service.createAccount(name: "Вклад", kind: .deposit, currency: "RUB", openingBalance: 1000)

        var thrown: Error?
        do {
            _ = try service.adjustBalance(account: deposit, to: 2000)
        } catch {
            thrown = error
        }

        // Типизированная ошибка, а не любая: молчаливый провал здесь исказил бы баланс вклада.
        if case .unsupportedOperationForDeposit = try #require(thrown as? AccountsCoreServiceError) {} else {
            Issue.record("Ожидали unsupportedOperationForDeposit, получили \(String(describing: thrown))")
        }
        #expect((deposit.events ?? []).allSatisfy { $0.type != .adjustment })
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
    func sellRejectsQuantityExceedingHoldingWithoutPersistingEvent() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let account = try service.createAccount(
            name: "AAPL", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "AAPL", assetClass: .stock)
        )
        try service.buy(account: account, quantity: 5, unitPrice: 100)
        #expect(throws: StockLotEngineError.oversell(requested: 8, available: 5)) {
            try service.sell(account: account, quantity: 8, unitPrice: 120)
        }

        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .marketInvestment, on: Date(), marketMeta: account.marketMeta)
        #expect(balance == 500)
        #expect((account.events ?? []).filter { $0.type == .sell }.isEmpty)
    }

    @Test
    func stockCorrectionAtomicallyUpdatesMetadataAndAbsolutePosition() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(
            name: "QQQ", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "QQQ", assetClass: .stock)
        )
        try service.buy(account: account, quantity: 10, unitPrice: 100)

        try service.correctStockPosition(
            account: account,
            name: "NASDAQ 100",
            group: nil,
            note: "Broker correction",
            includeInTotal: false,
            targetQuantity: 7.5,
            targetAverageCost: 123.4567
        )

        let snapshot = try StockLotEngine.replay(events: account.events ?? [])
        #expect(account.name == "NASDAQ 100")
        #expect(account.includeInTotal == false)
        #expect(snapshot.quantity == 7.5)
        #expect(snapshot.averageUnitCost == 123.4567)
        #expect((account.events ?? []).filter { $0.type == .adjustment && $0.quantity != nil }.count == 1)
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

    // MARK: - БАГ 6: архивный/удалённый счёт read-only на уровне сервиса, не только UI

    /// До фикса `recordEvent` молча писал `.income`/`.expense`/`.adjustment` на архивный счёт —
    /// UI прятал панель действий, но toolbar-фолбэк («···») её всё равно открывал.
    @Test
    func recordEventRejectsArchivedAccount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 1000)
        try service.archiveAccount(account)

        var thrown: Error?
        do {
            _ = try service.recordEvent(account: account, type: .income, amount: 500)
        } catch {
            thrown = error
        }

        if case .accountNotWritable = try #require(thrown as? AccountsCoreServiceError) {} else {
            Issue.record("Ожидали accountNotWritable, получили \(String(describing: thrown))")
        }
        #expect((account.events ?? []).allSatisfy { $0.type != .income })
    }

    /// Мягко удалённый (`deletedAt`) счёт — та же дыра, что и архивный: экран «Архив» открывает
    /// его карточку, и без этой проверки правки проходили бы на счёте, которого уже нет в списках.
    @Test
    func recordEventRejectsDeletedAccount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 1000)
        try service.softDelete(account)

        var thrown: Error?
        do {
            _ = try service.recordEvent(account: account, type: .expense, amount: 200)
        } catch {
            thrown = error
        }

        if case .accountNotWritable = try #require(thrown as? AccountsCoreServiceError) {} else {
            Issue.record("Ожидали accountNotWritable, получили \(String(describing: thrown))")
        }
    }

    /// «Изменить баланс» в «···» — до фикса создавал adjustment-событие на закрытом счёте.
    @Test
    func adjustBalanceRejectsArchivedAccount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Карта", kind: .debitCard, currency: "RUB", openingBalance: 1000)
        try service.archiveAccount(account)

        var thrown: Error?
        do {
            _ = try service.adjustBalance(account: account, to: 2000)
        } catch {
            thrown = error
        }

        if case .accountNotWritable = try #require(thrown as? AccountsCoreServiceError) {} else {
            Issue.record("Ожидали accountNotWritable, получили \(String(describing: thrown))")
        }
        #expect((account.events ?? []).allSatisfy { $0.type != .adjustment })
    }

    /// «Редактировать» в «···» — до фикса переименовывал/менял группу закрытого счёта.
    @Test
    func updateAccountRejectsArchivedAccount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Карта", kind: .debitCard, currency: "RUB", openingBalance: 1000)
        try service.archiveAccount(account)

        var thrown: Error?
        do {
            _ = try service.updateAccount(account, name: "Переименована после архивации", group: nil)
        } catch {
            thrown = error
        }

        if case .accountNotWritable = try #require(thrown as? AccountsCoreServiceError) {} else {
            Issue.record("Ожидали accountNotWritable, получили \(String(describing: thrown))")
        }
        #expect(account.name == "Карта") // правка не применилась
    }

    /// Перевод и НА, и С архивного счёта запрещён — обе ноги одного вызова, каждая сторона своя проверка.
    @Test
    func transferRejectsArchivedSourceAndDestination() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let archivedSource = try service.createAccount(name: "Архивная карта", kind: .debitCard, currency: "RUB", openingBalance: 1000)
        let activeDestination = try service.createAccount(name: "Активная карта", kind: .debitCard, currency: "RUB", openingBalance: 0)
        try service.archiveAccount(archivedSource)

        var thrownFromArchivedSource: Error?
        do {
            _ = try service.transfer(from: archivedSource, to: activeDestination, amountInSourceCurrency: 100)
        } catch {
            thrownFromArchivedSource = error
        }
        if case .accountNotWritable = try #require(thrownFromArchivedSource as? AccountsCoreServiceError) {} else {
            Issue.record("Ожидали accountNotWritable для source, получили \(String(describing: thrownFromArchivedSource))")
        }

        let activeSource = try service.createAccount(name: "Активная карта 2", kind: .debitCard, currency: "RUB", openingBalance: 1000)
        var thrownFromArchivedDestination: Error?
        do {
            _ = try service.transfer(from: activeSource, to: archivedSource, amountInSourceCurrency: 100)
        } catch {
            thrownFromArchivedDestination = error
        }
        if case .accountNotWritable = try #require(thrownFromArchivedDestination as? AccountsCoreServiceError) {} else {
            Issue.record("Ожидали accountNotWritable для destination, получили \(String(describing: thrownFromArchivedDestination))")
        }

        // Ни одна нога не создалась ни на одном из счетов.
        #expect((archivedSource.events ?? []).allSatisfy { $0.type != .transferOut && $0.type != .transferIn })
        #expect((activeDestination.events ?? []).allSatisfy { $0.type != .transferIn })
    }

    /// Мост Cashflow (`AccountsCoreCashflowBridge.upsertEvent`) — та же дыра, что у `recordEvent`,
    /// но незаметнее: сам мост ничем не фильтрует archivedAt/deletedAt перед вызовом (греп по
    /// вызывающему коду это подтверждает), значит правка транзакции задним числом молча писала бы
    /// на закрытый счёт в обход экрана «Счёт», где панель действий уже была бы скрыта.
    @Test
    func upsertEventRejectsArchivedAccount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 1000)
        try service.archiveAccount(account)

        var thrown: Error?
        do {
            _ = try service.upsertEvent(
                sourceTransactionID: "cashflow-tx-1",
                account: account,
                type: .expense,
                amount: 300,
                date: Date()
            )
        } catch {
            thrown = error
        }

        if case .accountNotWritable = try #require(thrown as? AccountsCoreServiceError) {} else {
            Issue.record("Ожидали accountNotWritable, получили \(String(describing: thrown))")
        }
        #expect((account.events ?? []).allSatisfy { $0.sourceTransactionID != "cashflow-tx-1" })
    }

    // MARK: - Ревью round 1: isWritable + LocalizedError

    /// `isWritable` — read-only обёртка для check-before-mutate у вызывающих (мост Cashflow,
    /// A1): должна отражать ровно то же условие, что и `requireWritable`, без побочных эффектов.
    @Test
    func isWritableReflectsArchivedAndDeletedState() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let live = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0)
        let archived = try service.createAccount(name: "Архив", kind: .cash, currency: "RUB", openingBalance: 0)
        try service.archiveAccount(archived)

        #expect(service.isWritable(live))
        #expect(service.isWritable(archived) == false)
    }

    /// A3/A4: замена `error.localizedDescription` на человекочитаемый текст не должна тихо родить
    /// case без текста — иначе UI откатится к тому же системному «Операция не может быть завершена».
    @Test
    func everyErrorCaseHasNonEmptyLocalizedDescription() {
        let cases: [AccountsCoreServiceError] = [
            .dirtyContext,
            .unsupportedEventType(.income),
            .sameAccountTransfer,
            .missingFxRate,
            .eventWithoutAccount,
            .missingProductIdentity,
            .unknownLegacySemanticMutation,
            .eventNotAllowed(.cash, .income),
            .capabilityNotAllowed(.cash, .transfers),
            .invalidCreditCardAmount,
            .archivedCreditCard,
            .unsupportedOperationForDeposit,
            .accountNotWritable,
        ]
        for error in cases {
            let description = error.errorDescription
            #expect(description != nil, "\(error) должен иметь errorDescription")
            #expect(description?.isEmpty == false, "\(error) не должен иметь пустой errorDescription")
        }
    }

    // MARK: - Ревью round 2: deleteEvent/upsertEvent check-before-mutate, stageArchiveAccount идемпотентен

    /// A1 (остаточная дыра, ревью round 2): guard в `AccountsCoreCashflowBridge.syncTransfer`
    /// проверяет только НОВЫЕ source/destination правки — старые ноги существующего перевода не
    /// проверялись вовсе. `deleteEvents(bySourceTransactionID:)` (вызывается и мостом при пересборке
    /// перевода, и удалением строки ленты) до фикса удаляла обе ноги БЕЗ проверки писуемости счетов,
    /// которых касается. Тест — на уровне сервиса, без моста: прямой вызов `deleteEvents` после
    /// архивации ОДНОЙ стороны уже созданного перевода.
    @Test
    func deleteEventsBlocksTransferLegDeletionWhenOneLegAccountArchived() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let source = try service.createAccount(name: "Карта X", kind: .cash, currency: "RUB", openingBalance: 1000)
        let destination = try service.createAccount(name: "Карта L", kind: .cash, currency: "RUB", openingBalance: 0)

        let legs = try service.transfer(
            from: source, to: destination, amountInSourceCurrency: 300, sourceTransactionID: "cashflow-transfer-1"
        )
        try service.archiveAccount(source)

        var thrown: Error?
        do {
            try service.deleteEvents(bySourceTransactionID: "cashflow-transfer-1")
        } catch {
            thrown = error
        }
        if case .accountNotWritable = try #require(thrown as? AccountsCoreServiceError) {} else {
            Issue.record("Ожидали accountNotWritable, получили \(String(describing: thrown))")
        }

        // ГЛАВНАЯ ПРОВЕРКА: обе ноги остались — deleteEvent проверяет ВСЕ затронутые счета ДО
        // первого delete, не только новые концы правки.
        let transferLegs = try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.transferID == legs.out.transferID }
        ))
        #expect(transferLegs.count == 2, "Обе ноги перевода должны остаться нетронутыми при отказе")
    }

    /// Ревью round 2 («Проверка писуемости смотрит только на новые концы операции»): `upsertEvent`
    /// проверял только НОВЫЙ `account`, а `existing.account = account` переносил событие с архивного
    /// счёта молча — правка суммы блокировалась, а смена счёта (перенос транзакции с архивного X на
    /// живой Y) проходила. Единая политика «блокировать» требует проверки СТАРОГО счёта тоже.
    @Test
    func upsertEventBlocksReassignmentAwayFromArchivedAccount() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let source = try service.createAccount(name: "Кошелёк", kind: .cash, currency: "RUB", openingBalance: 0)
        let destination = try service.createAccount(name: "Другой кошелёк", kind: .cash, currency: "RUB", openingBalance: 0)

        _ = try service.upsertEvent(
            sourceTransactionID: "cashflow-tx-move", account: source, type: .expense, amount: 200, date: Date()
        )
        try service.archiveAccount(source)

        var thrown: Error?
        do {
            _ = try service.upsertEvent(
                sourceTransactionID: "cashflow-tx-move", account: destination, type: .expense, amount: 200, date: Date()
            )
        } catch {
            thrown = error
        }
        if case .accountNotWritable = try #require(thrown as? AccountsCoreServiceError) {} else {
            Issue.record("Ожидали accountNotWritable при переносе события с архивного счёта, получили \(String(describing: thrown))")
        }

        // Главная проверка: событие осталось на архивном source, а не переехало на destination молча.
        let events = try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == "cashflow-tx-move" }
        ))
        #expect(events.count == 1)
        #expect(events.first?.account?.id == source.id, "Событие не должно молча переехать на живой destination-счёт с архивного source")
    }

    /// Ревью round 2 (БАГ «Удалить» архивного кредита): «Удалить» на уже архивном кредите вело в
    /// `archiveAccount()` → `stageArchiveAccount`, которая БЕЗ проверки «уже в архиве» сдвигала
    /// `archivedAt` на сегодня — `Account.participates(on:)` времязависим, долг задним числом
    /// возвращался бы в историю net worth за весь промежуток [старый archivedAt, новый].
    @Test
    func archiveAccountDoesNotMoveArchivedAtForwardWhenAlreadyArchived() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Автокредит", kind: .loan, currency: "RUB", openingBalance: 100_000)
        let originalArchiveDate = try #require(Calendar.current.date(byAdding: .day, value: -30, to: Date()))
        try service.archiveAccount(account, on: originalArchiveDate)
        #expect(account.archivedAt == originalArchiveDate)

        // Повторная архивация (напр. повторный «Удалить» на уже архивном счёте) не должна сдвигать
        // archivedAt вперёд.
        try service.archiveAccount(account)
        #expect(account.archivedAt == originalArchiveDate, "Повторная архивация не должна сдвигать archivedAt вперёд")
    }
}
