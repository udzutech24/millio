//
//  AccountsCoreDepositCashflowBridgeTests.swift
//  millioTests
//
//  Тесты моста AccountsCore → Cashflow для вкладов (Фаза 0 плана
//  `2026-07-05__cashflow-add-transaction-redesign.md`, §1.8/§4). Покрывает acceptance criteria:
//  видимость due-процентов в дату, идемпотентность, catch-up пропущенных дат, продление горизонта
//  бессрочного вклада, отсутствие влияния на баланс карты/архивные счета.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("AccountsCoreDepositCashflowBridge")
@MainActor
struct AccountsCoreDepositCashflowBridgeTests {

    private func makeContext() throws -> (container: ModelContainer, context: ModelContext, service: AccountsCoreService) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        return (container, ctx, AccountsCoreService(modelContext: ctx))
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func fetchInterestTransactions(_ ctx: ModelContext) throws -> [CashflowTransaction] {
        let sourceTag = AccountsCoreDepositCashflowBridge.interestImportSource
        let descriptor = FetchDescriptor<CashflowTransaction>(
            predicate: #Predicate<CashflowTransaction> { $0.importSourceRaw == sourceTag }
        )
        return try ctx.fetch(descriptor)
    }

    private func markGeneratedInterestConfirmed(_ ctx: ModelContext, through date: Date) throws {
        for event in try ctx.fetch(FetchDescriptor<AccountEvent>())
        where event.type == .interest && event.date <= date {
            event.sourceTransactionID = "confirmed:\(event.id.uuidString)"
        }
        try ctx.save()
    }

    // MARK: - Acceptance: due-проценты появляются доходной транзакцией на верную дату/сумму

    @Test
    func dueInterestEventMaterializesAsVisibleIncomeTransaction() throws {
        let (container, ctx, service) = try makeContext()
        _ = container

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(byAdding: .month, value: 3, to: opening)!
        let account = try service.createAccount(
            name: "Тинькофф Вклад", kind: .deposit, currency: "RUB", openingBalance: 100_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 12, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )
        try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: ctx
        )

        // "Сегодня" — ровно дата первой выплаты процентов (конец месяца 1), не раньше и не позже.
        let firstPayoutDate = calendar.date(byAdding: .month, value: 1, to: opening)!
        let bridge = AccountsCoreDepositCashflowBridge(modelContext: ctx, now: { firstPayoutDate }, calendar: calendar)

        let didMaterialize = bridge.materializeDueInterestIncome()
        #expect(didMaterialize == false)

        let transactions = try fetchInterestTransactions(ctx)
        #expect(transactions.isEmpty) // due scheduler estimate — всё ещё прогноз, а не доход
    }

    // MARK: - Идемпотентность: повторный вызов не плодит дубликаты

    @Test
    func repeatedCallsDoNotDuplicateMaterializedTransactions() throws {
        let (container, ctx, service) = try makeContext()
        _ = container

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(byAdding: .month, value: 2, to: opening)!
        let account = try service.createAccount(
            name: "Накопительный", kind: .deposit, currency: "RUB", openingBalance: 50_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 10, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: true, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )
        try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: ctx
        )

        let asOf = calendar.date(byAdding: .month, value: 2, to: opening)!
        try markGeneratedInterestConfirmed(ctx, through: asOf)
        let bridge = AccountsCoreDepositCashflowBridge(modelContext: ctx, now: { asOf }, calendar: calendar)

        #expect(bridge.materializeDueInterestIncome() == true)
        #expect(bridge.materializeDueInterestIncome() == false) // нечего материализовывать повторно

        let transactions = try fetchInterestTransactions(ctx)
        #expect(transactions.count == 2) // ровно 2 периода, не 4
    }

    @Test("Phase 1: two serial ModelContexts do not duplicate the same due projection")
    func serialMultiContextCallsDoNotDuplicateMaterializedTransaction() throws {
        let (container, context, service) = try makeContext()
        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let payout = calendar.date(byAdding: .month, value: 1, to: opening)!
        let account = try service.createAccount(
            name: "Multi-context", kind: .deposit, currency: "RUB", openingBalance: 100_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 12, capitalization: .monthly, termEnd: payout, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )
        try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: context
        )

        let firstContext = ModelContext(container)
        let secondContext = ModelContext(container)
        try markGeneratedInterestConfirmed(context, through: payout)
        let firstBridge = AccountsCoreDepositCashflowBridge(
            modelContext: firstContext, now: { payout }, calendar: calendar
        )
        let secondBridge = AccountsCoreDepositCashflowBridge(
            modelContext: secondContext, now: { payout }, calendar: calendar
        )

        #expect(firstBridge.materializeDueInterestIncome())
        #expect(secondBridge.materializeDueInterestIncome() == false)
        let verificationContext = ModelContext(container)
        #expect(try fetchInterestTransactions(verificationContext).count == 1)
    }

    // MARK: - Будущие (ещё не наступившие) события не показываются раньше срока

    @Test
    func notYetDueInterestIsNotMaterializedEarly() throws {
        let (container, ctx, service) = try makeContext()
        _ = container

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(byAdding: .month, value: 6, to: opening)!
        let account = try service.createAccount(
            name: "Вклад", kind: .deposit, currency: "RUB", openingBalance: 200_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 15, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )
        try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: ctx
        )

        // "Сегодня" — день открытия, ни один период ещё не наступил.
        let bridge = AccountsCoreDepositCashflowBridge(modelContext: ctx, now: { opening }, calendar: calendar)
        #expect(bridge.materializeDueInterestIncome() == false)
        #expect(try fetchInterestTransactions(ctx).isEmpty)
    }

    // MARK: - Catch-up: приложение не открывали несколько месяцев — все пропущенные периоды

    @Test
    func catchUpMaterializesAllMissedPeriodsWithHistoricalDatesAtOnce() throws {
        let (container, ctx, service) = try makeContext()
        _ = container

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(byAdding: .month, value: 6, to: opening)!
        let account = try service.createAccount(
            name: "Вклад «Надёжный»", kind: .deposit, currency: "RUB", openingBalance: 1_000_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 12, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )
        try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: ctx
        )

        // Пользователь не открывал приложение с даты создания до конца 4-го месяца — 4 периода
        // должны материализоваться ОДНИМ вызовом с их исторически верными датами.
        let asOf = calendar.date(byAdding: .month, value: 4, to: opening)!
        try markGeneratedInterestConfirmed(ctx, through: asOf)
        let bridge = AccountsCoreDepositCashflowBridge(modelContext: ctx, now: { asOf }, calendar: calendar)

        #expect(bridge.materializeDueInterestIncome() == true)

        let transactions = try fetchInterestTransactions(ctx).sorted { $0.transactionDate < $1.transactionDate }
        #expect(transactions.count == 4)
        for (index, tx) in transactions.enumerated() {
            let expectedDate = calendar.date(byAdding: .month, value: index + 1, to: opening)!
            #expect(calendar.isDate(tx.transactionDate, inSameDayAs: expectedDate))
        }

        // Повторный запуск (следующее открытие приложения в тот же день) — без дублей.
        #expect(bridge.materializeDueInterestIncome() == false)
        #expect(try fetchInterestTransactions(ctx).count == 4)
    }

    // MARK: - Продление горизонта: бессрочный вклад старше исходных 12 месяцев продолжает начислять

    @Test
    func syncExtendsHorizonForPerpetualDepositBeyondOriginalWindow() throws {
        let (container, ctx, service) = try makeContext()
        _ = container

        let opening = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let account = try service.createAccount(
            name: "Накопительный без срока", kind: .deposit, currency: "RUB", openingBalance: 100_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 6, capitalization: .monthly, termEnd: nil, payoutDay: nil,
            allowsTopUp: true, allowsEarlyClose: true, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )
        // Изначальная генерация (как при создании счёта) — горизонт 12 месяцев от opening.
        try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: ctx
        )
        let eventsBefore = try ctx.fetch(FetchDescriptor<AccountEvent>()).filter {
            $0.account?.id == account.id && $0.type == .interest
        }
        #expect(eventsBefore.count == 12)

        // Прошло чуть больше 13 месяцев без единого открытия экрана правки вклада — старый горизонт
        // исчерпан. +1 день после ровной границы периода — реалистичный сценарий (пользователь открыл
        // приложение НЕ в тот же миг начисления, `DepositInterestScheduler.generate` считает период
        // «прошедшим» строго по `date > asOf`, поэтому проверка ровно на границе периода — не наш кейс).
        let asOf = calendar.date(byAdding: .day, value: 1, to: calendar.date(byAdding: .month, value: 13, to: opening)!)!
        let bridge = AccountsCoreDepositCashflowBridge(modelContext: ctx, now: { asOf }, calendar: calendar)
        let didMaterialize = bridge.syncDepositInterestLedger()
        #expect(didMaterialize == false) // горизонт продлён, но estimates не стали доходом

        let eventsAfter = try ctx.fetch(FetchDescriptor<AccountEvent>()).filter {
            $0.account?.id == account.id && $0.type == .interest
        }
        #expect(eventsAfter.count > 12) // горизонт продлён за пределы исходных 12 периодов

        let transactions = try fetchInterestTransactions(ctx)
        #expect(transactions.isEmpty)
    }

    // MARK: - Архивный (закрытый) вклад не продлевает горизонт, но прошлые due-события материализуются

    @Test
    func archivedDepositIsExcludedFromHorizonExtensionButPastDueEventsStillMaterialize() throws {
        let (container, ctx, service) = try makeContext()
        _ = container

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(byAdding: .month, value: 3, to: opening)!
        let account = try service.createAccount(
            name: "Закрытый вклад", kind: .deposit, currency: "RUB", openingBalance: 100_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 12, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: true, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )
        try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: ctx
        )
        account.archivedAt = calendar.date(byAdding: .month, value: 1, to: opening)

        let asOf = calendar.date(byAdding: .month, value: 1, to: opening)!
        let generatedByExtension = DepositInterestScheduler.extendActiveDepositHorizons(context: ctx, asOf: asOf)
        #expect(generatedByExtension == 0) // архивный счёт исключён из продления горизонта

        let bridge = AccountsCoreDepositCashflowBridge(modelContext: ctx, now: { asOf }, calendar: calendar)
        #expect(bridge.materializeDueInterestIncome() == false)
        #expect(try fetchInterestTransactions(ctx).isEmpty)
    }

    // MARK: - upcomingInterestEvents (Фаза 0, Шаг 6 — секция «Предстоящие»)

    @Test
    func upcomingInterestEventsExcludesDueAndReturnsOnlyFuturePeriods() throws {
        let (container, ctx, service) = try makeContext()
        _ = container

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(byAdding: .month, value: 4, to: opening)!
        let account = try service.createAccount(
            name: "Вклад «Растущий»", kind: .deposit, currency: "RUB", openingBalance: 100_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 12, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )
        try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: ctx
        )

        // "Сегодня" — конец 1 месяца: 1-й период due, 2-3-4 — ещё впереди.
        let asOf = calendar.date(byAdding: .month, value: 1, to: opening)!
        let bridge = AccountsCoreDepositCashflowBridge(modelContext: ctx, now: { asOf }, calendar: calendar)

        let upcoming = bridge.upcomingInterestEvents()
        #expect(upcoming.count == 3) // периоды 2, 3, 4 — due-период 1 сюда не входит

        let expectedFirst = calendar.date(byAdding: .month, value: 2, to: opening)!
        #expect(calendar.isDate(upcoming.first!.date, inSameDayAs: expectedFirst))
        // Капитализация .monthly: 2-й период начисляется на 100 000 + 1 000 (1-й период) = 101 000.
        #expect(upcoming.first?.amount == 1_010) // 101 000 * 12% / 12
        #expect(upcoming.first?.currencyCode == "RUB")
        #expect(upcoming.first?.accountName == "Вклад «Растущий»")
        #expect(upcoming.first?.accountID == account.id)

        // Отсортировано по возрастанию даты.
        #expect(upcoming.map(\.date) == upcoming.map(\.date).sorted())

        // Материализация due-периода не пересекается с upcoming (разные множества).
        #expect(bridge.materializeDueInterestIncome() == false)
        #expect(try fetchInterestTransactions(ctx).isEmpty)
        #expect(bridge.upcomingInterestEvents().count == 3) // материализация 1-го периода не трогает будущие
    }

    @Test
    func upcomingInterestEventsRespectsLimit() throws {
        let (container, ctx, service) = try makeContext()
        _ = container

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let account = try service.createAccount(
            name: "Бессрочный вклад", kind: .deposit, currency: "RUB", openingBalance: 100_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 12, capitalization: .monthly, termEnd: nil, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )
        try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: ctx
        )

        let bridge = AccountsCoreDepositCashflowBridge(modelContext: ctx, now: { opening }, calendar: calendar)
        #expect(bridge.upcomingInterestEvents(limit: 2).count == 2)
    }

    @Test
    func upcomingInterestEventsEmptyWhenNoDeposits() throws {
        let (container, ctx, _) = try makeContext()
        _ = container

        let bridge = AccountsCoreDepositCashflowBridge(modelContext: ctx, now: { Date() }, calendar: calendar)
        #expect(bridge.upcomingInterestEvents().isEmpty)
    }
}
