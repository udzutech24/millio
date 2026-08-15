//
//  AccountsCoreCashflowBridgeTests.swift
//  millioTests
//
//  Тесты моста Cashflow → новое ядро счетов (Фаза 1b, план §2.5/§3, риски №1/№2/№4/№6/№7/№8).
//

import Foundation
import SwiftData
import Testing
@testable import millio

@MainActor
final class BridgeMockRateService: CurrencyRateServiceProtocol {
    var historicalRatesByPair: [String: Double] = [:]
    var currentRatesByPair: [String: Double] = [:]

    func getRate(from: String, to: String) async -> Double? {
        currentRatesByPair["\(from.uppercased())_\(to.uppercased())"]
    }

    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? {
        historicalRatesByPair["\(from.uppercased())_\(to.uppercased())"]
    }

    func convert(amount: Double, from: String, to: String) async -> Double? {
        guard let rate = await getRate(from: from, to: to) else { return nil }
        return amount * rate
    }

    func forceRefreshRates() async {}
}

@Suite("AccountsCoreCashflowBridge")
@MainActor
struct AccountsCoreCashflowBridgeTests {

    /// Держим контейнер живым вместе с контекстом — см. конвенцию AccountsCoreServiceTests.
    private func makeContext(rateService: BridgeMockRateService? = nil) throws -> (
        container: ModelContainer, context: ModelContext, accountsService: AccountsCoreService, bridge: AccountsCoreCashflowBridge
    ) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let accountsService = AccountsCoreService(modelContext: ctx)
        let rateStore = HistoricalRateStore(modelContext: ctx, currencyService: rateService ?? BridgeMockRateService())
        let bridge = AccountsCoreCashflowBridge(
            modelContext: ctx, accountsCoreService: accountsService, historicalRateStore: rateStore
        )
        return (container, ctx, accountsService, bridge)
    }

    private func makeTransaction(
        type: CashflowTransactionType,
        amount: Double,
        currency: String = "RUB",
        cardID: String? = nil,
        toCardID: String? = nil,
        date: Date = Date(),
        note: String? = nil
    ) -> CashflowTransaction {
        CashflowTransaction(
            transactionType: type, amount: amount, currency: currency, transactionDate: date,
            cardID: cardID, toCardID: toCardID, note: note
        )
    }

    // MARK: - Задача 9, пункт 1: income/expense на новый счёт создаёт событие, balanceAt меняется

    @Test
    func expenseOnNewCoreAccountCreatesEventAndChangesBalance() async throws {
        let (container, ctx, service, bridge) = try makeContext()
        _ = container
        let account = try service.createAccount(name: "Карта", kind: .debitCard, currency: "RUB", openingBalance: 1000)

        let tx = makeTransaction(type: .expense, amount: 300, cardID: account.id.uuidString)
        ctx.insert(tx)
        try ctx.save()
        let txID = tx.uniqueID

        try await bridge.sync(for: tx)

        let events = try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == txID }
        ))
        #expect(events.count == 1)
        #expect(events.first?.type == .expense)
        #expect(events.first?.amount == 300)

        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: Date())
        #expect(balance == 700)
    }

    // MARK: - Фаза 2: creditDebtAdjustment на new-core .loan → adjustment-событие (раньше был no-op)

    @Test
    func creditDebtAdjustmentOnNewCoreLoanCreatesAdjustmentEventAndReducesDebt() async throws {
        let (container, ctx, service, bridge) = try makeContext()
        _ = container
        // openingBalance для .loan — МАГНИТУДА (движок C сам вычитает через loanSignMap).
        let loan = try service.createAccount(name: "Кредит", kind: .loan, currency: "RUB", openingBalance: 100_000)

        // Положительная сумма = уменьшение долга (та же конвенция, что у quick-edit в FinanceViewModel).
        let tx = makeTransaction(type: .creditDebtAdjustment, amount: 20_000, cardID: loan.id.uuidString)
        ctx.insert(tx)
        try ctx.save()
        let txID = tx.uniqueID

        try await bridge.sync(for: tx)

        let events = try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == txID }
        ))
        #expect(events.count == 1)
        #expect(events.first?.type == .adjustment)
        #expect(events.first?.amount == 20_000)

        let balance = AccountBalanceEngine.balanceAt(events: loan.events ?? [], kind: loan.kind, on: Date())
        #expect(balance == -80_000)
    }

    // MARK: - Задача 9, пункт 2: чужая валюта фиксирует original + курс

    @Test
    func expenseInForeignCurrencyFixesOriginalAmountAndRate() async throws {
        let rateService = BridgeMockRateService()
        rateService.historicalRatesByPair["USD_RUB"] = 90
        let (container, ctx, service, bridge) = try makeContext(rateService: rateService)
        _ = container
        let account = try service.createAccount(name: "Карта", kind: .debitCard, currency: "RUB", openingBalance: 2_000)

        let tx = makeTransaction(type: .expense, amount: 10, currency: "USD", cardID: account.id.uuidString)
        ctx.insert(tx)
        try ctx.save()
        let txID = tx.uniqueID

        try await bridge.sync(for: tx)

        let event = try #require(try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == txID }
        )).first)
        #expect(event.amount == 900) // 10 USD * 90
        #expect(event.originalAmount == 10)
        #expect(event.originalCurrency == "USD")
        #expect(event.fxRateToBase == 90)
        #expect(event.fxProvisional == false)
    }

    // MARK: - Задача 9, пункт 3: удаление транзакции удаляет событие и пересчитывает кэш

    @Test
    func deletingTransactionDeletesEvent() async throws {
        let (container, ctx, service, bridge) = try makeContext()
        _ = container
        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 1000)

        let tx = makeTransaction(type: .income, amount: 500, cardID: account.id.uuidString)
        ctx.insert(tx)
        try ctx.save()
        let txID = tx.uniqueID
        try await bridge.sync(for: tx)

        var events = try ctx.fetch(FetchDescriptor<AccountEvent>())
        #expect(events.contains { $0.sourceTransactionID == txID })

        try bridge.deleteEvents(for: tx)

        events = try ctx.fetch(FetchDescriptor<AccountEvent>())
        #expect(events.contains { $0.sourceTransactionID == txID } == false)

        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: Date())
        #expect(balance == 1000) // событие удалено — доход отменён
    }

    // MARK: - Задача 9, пункт 4 (риск №2): смена цели старый↔новый — обе ветки

    @Test
    func switchingTargetFromLegacyToNewCoreCreatesEvent() async throws {
        let (container, ctx, service, bridge) = try makeContext()
        _ = container
        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0)

        // Раньше цель — легаси-карта (случайный UUID, не резолвится в Account) — событий нет.
        let tx = makeTransaction(type: .expense, amount: 100, cardID: UUID().uuidString)
        ctx.insert(tx)
        try ctx.save()
        let txID = tx.uniqueID
        try await bridge.sync(for: tx)
        #expect(try ctx.fetch(FetchDescriptor<AccountEvent>()).contains { $0.sourceTransactionID == txID } == false)

        // Правка: цель меняется на новый счёт.
        tx.cardID = account.id.uuidString
        try await bridge.sync(for: tx)

        let events = try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == txID }
        ))
        #expect(events.count == 1)
    }

    @Test
    func switchingTargetFromNewCoreToLegacyDeletesEvent() async throws {
        let (container, ctx, service, bridge) = try makeContext()
        _ = container
        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0)

        let tx = makeTransaction(type: .expense, amount: 100, cardID: account.id.uuidString)
        ctx.insert(tx)
        try ctx.save()
        let txID = tx.uniqueID
        try await bridge.sync(for: tx)
        #expect(try ctx.fetch(FetchDescriptor<AccountEvent>()).contains { $0.sourceTransactionID == txID })

        // Правка: цель меняется на легаси-карту (случайный UUID вне Account-таблицы).
        tx.cardID = UUID().uuidString
        try await bridge.sync(for: tx)

        #expect(try ctx.fetch(FetchDescriptor<AccountEvent>()).contains { $0.sourceTransactionID == txID } == false)
    }

    // MARK: - Задача 9, пункт 5: переводы новый↔новый (Σ=0) и смешанный (без transferID)

    @Test
    func transferBetweenTwoNewCoreAccountsCreatesTwoLinkedLegs() async throws {
        let (container, ctx, service, bridge) = try makeContext()
        _ = container
        let source = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 1000)
        let destination = try service.createAccount(name: "Счёт", kind: .bankAccount, currency: "RUB", openingBalance: 0)

        let tx = makeTransaction(
            type: .transfer, amount: 400, cardID: source.id.uuidString, toCardID: destination.id.uuidString
        )
        ctx.insert(tx)
        try ctx.save()
        let txID = tx.uniqueID

        try await bridge.sync(for: tx)

        let events = try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == txID }
        ))
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.transferID != nil })
        #expect(Set(events.compactMap(\.transferID)).count == 1) // общий transferID

        let sourceBalance = AccountBalanceEngine.balanceAt(events: source.events ?? [], kind: source.kind, on: Date())
        let destinationBalance = AccountBalanceEngine.balanceAt(events: destination.events ?? [], kind: destination.kind, on: Date())
        #expect(sourceBalance == 600)
        #expect(destinationBalance == 400)
    }

    @Test
    func transferMixedLegacyToNewCoreCreatesSingleEventWithoutTransferID() async throws {
        let (container, ctx, service, bridge) = try makeContext()
        _ = container
        let destination = try service.createAccount(name: "Счёт", kind: .bankAccount, currency: "RUB", openingBalance: 0)

        // cardID — легаси (не резолвится в Account), toCardID — новый счёт.
        let tx = makeTransaction(
            type: .transfer, amount: 250, cardID: UUID().uuidString, toCardID: destination.id.uuidString
        )
        ctx.insert(tx)
        try ctx.save()
        let txID = tx.uniqueID

        try await bridge.sync(for: tx)

        let events = try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == txID }
        ))
        #expect(events.count == 1)
        #expect(events.first?.transferID == nil) // мост — не двуногий перевод ядра
        #expect(events.first?.type == .income)
        #expect(events.first?.note?.contains("легаси-мост") == true)

        let destinationBalance = AccountBalanceEngine.balanceAt(events: destination.events ?? [], kind: destination.kind, on: Date())
        #expect(destinationBalance == 250)
    }

    // MARK: - Задача 9, пункт 6: идемпотентность (повторный upsert не плодит дубликаты)

    @Test
    func repeatedSyncDoesNotDuplicateEvent() async throws {
        let (container, ctx, service, bridge) = try makeContext()
        _ = container
        let account = try service.createAccount(name: "Карта", kind: .cash, currency: "RUB", openingBalance: 0)

        let tx = makeTransaction(type: .income, amount: 100, cardID: account.id.uuidString)
        ctx.insert(tx)
        try ctx.save()
        let txID = tx.uniqueID

        try await bridge.sync(for: tx)
        try await bridge.sync(for: tx) // повторный запуск (напр. recurring-генератор перезапущен)
        try await bridge.sync(for: tx)

        let events = try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == txID }
        ))
        #expect(events.count == 1)
    }

    // MARK: - Задача 9, пункт 7: расход > баланса — валиден, баланс отрицательный

    @Test
    func expenseExceedingBalanceIsAllowedAndGoesNegative() async throws {
        let (container, ctx, service, bridge) = try makeContext()
        _ = container
        let account = try service.createAccount(name: "Наличные", kind: .cash, currency: "RUB", openingBalance: 100)

        let tx = makeTransaction(type: .expense, amount: 500, cardID: account.id.uuidString)
        ctx.insert(tx)
        try ctx.save()

        try await bridge.sync(for: tx) // не должно бросить/отклонить

        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: Date())
        #expect(balance == -400)
    }

    // MARK: - Задача 9, пункт 8: правка суммы задним числом — курс ДАТЫ СОБЫТИЯ, не сегодняшний

    @Test
    func editingAmountRefixesRateAtEventDateNotToday() async throws {
        let rateService = BridgeMockRateService()
        rateService.historicalRatesByPair["USD_RUB"] = 80 // курс на дату события
        let (container, ctx, service, bridge) = try makeContext(rateService: rateService)
        _ = container
        let eventDate = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let openingDate = Calendar.current.date(byAdding: .day, value: -1, to: eventDate)!
        let account = try service.createAccount(
            name: "Карта", kind: .debitCard, currency: "RUB", openingBalance: 2_000, date: openingDate
        )
        let tx = makeTransaction(type: .expense, amount: 10, currency: "USD", cardID: account.id.uuidString, date: eventDate)
        ctx.insert(tx)
        try ctx.save()
        let txID = tx.uniqueID
        try await bridge.sync(for: tx)

        // Курс "сегодня" другой — правка суммы НЕ должна его подхватить, только курс даты события.
        rateService.currentRatesByPair["USD_RUB"] = 999

        tx.amount = 20
        try await bridge.sync(for: tx)

        let event = try #require(try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == txID }
        )).first)
        #expect(event.amount == 1600) // 20 * 80 (курс даты события), не 20 * 999
        #expect(event.fxRateToBase == 80)
    }
}
