//
//  DepositInterestAppliedNoticeTests.swift
//  millioTests
//
//  Гейт фазы 1b плана `2026-09-05__planned-operations-applied-notice.md`:
//  1) отчёт проектора несёт детали вставленных строк, `insertedCount` совпадает с их числом;
//  2) материализация процентов кладёт записи в журнал с `kind == .depositInterest`,
//     именем счёта и суммой;
//  3) без стора поведение моста прежнее (стор опционален).
//
//  Балансовой арифметики здесь нет: проценты двигает `AccountEvent`, запись — информационная.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@MainActor
@Suite("Проценты по вкладу → журнал применённых плановых операций")
struct DepositInterestAppliedNoticeTests {

    // MARK: - Harness

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "tests.cashflow.depositNotice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    /// Вклад с двумя наступившими подтверждёнными начислениями процентов.
    private func makeConfirmedDeposit(
        name: String,
        currency: String
    ) throws -> (container: ModelContainer, context: ModelContext, asOf: Date) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(byAdding: .month, value: 2, to: opening)!
        let account = try service.createAccount(
            name: name, kind: .deposit, currency: currency, openingBalance: 100_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 12, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )
        try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: context
        )

        // Scheduler estimates становятся доходом только после подтверждения — иначе проектор
        // их намеренно игнорирует и вставлять будет нечего.
        let asOf = termEnd
        for event in try context.fetch(FetchDescriptor<AccountEvent>())
        where event.type == .interest && event.date <= asOf {
            event.sourceTransactionID = "confirmed:\(event.id.uuidString)"
        }
        try context.save()

        return (container, context, asOf)
    }

    // MARK: - Отчёт проектора несёт детали

    @Test("Отчёт проектора отдаёт вставленные строки, insertedCount равен их числу")
    func projectionReportCarriesInsertedRows() throws {
        let (container, context, asOf) = try makeConfirmedDeposit(name: "Вклад Альфа", currency: "RUB")
        _ = container

        let events = try context.fetch(FetchDescriptor<AccountEvent>())
        let report = try DepositCashflowProjector.project(
            events: events, through: asOf, context: context
        )

        #expect(report.insertedCount == report.inserted.count)
        #expect(report.insertedCount == 2)
        #expect(report.inserted.allSatisfy { $0.accountName == "Вклад Альфа" })
        #expect(report.inserted.allSatisfy { $0.currencyCode == "RUB" })
        #expect(report.inserted.allSatisfy { $0.amount > 0 })
        #expect(report.inserted.allSatisfy { $0.date <= asOf })

        // Обратная совместимость: счётчик по-прежнему равен числу реально вставленных строк.
        let inserted = try context.fetch(FetchDescriptor<CashflowTransaction>())
            .filter { $0.importSourceRaw == DepositCashflowProjector.importSource }
        #expect(inserted.count == report.insertedCount)
    }

    @Test("Пустой прогон: нет вставок — нет деталей и нулевой счётчик")
    func emptyProjectionReportsZero() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let report = try DepositCashflowProjector.project(events: [], through: Date(), context: context)

        #expect(report.inserted.isEmpty)
        #expect(report.insertedCount == 0)
    }

    // MARK: - Мост пишет в журнал

    @Test("Применение процентов кладёт записи kind == .depositInterest с именем счёта и суммой")
    func materializationWritesDepositInterestEntries() throws {
        let (container, context, asOf) = try makeConfirmedDeposit(name: "Вклад Бета", currency: "USD")
        _ = container

        let defaults = makeDefaults()
        let store = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: "millio_user_owner")
        let bridge = AccountsCoreDepositCashflowBridge(
            modelContext: context,
            now: { asOf },
            calendar: calendar,
            publishCommitted: {},
            appliedNoticeStore: store
        )

        #expect(bridge.materializeDueInterestIncome() == true)

        let digest = try #require(store.takeDigest())
        #expect(digest.totalCount == 2)
        #expect(digest.details.count == 2)
        #expect(digest.details.allSatisfy { $0.kind == .depositInterest })
        #expect(digest.details.allSatisfy { $0.accountName == "Вклад Бета" })
        #expect(digest.details.allSatisfy { $0.currencyCode == "USD" })
        // Проценты — доход: положительный знак и нетто-итог по своей валюте, без конвертации.
        #expect(digest.details.allSatisfy { $0.amount > 0 })
        #expect(digest.incomeCount == 2)
        #expect(digest.expenseCount == 0)
        #expect(digest.totalsByCurrency["USD"] == digest.details.reduce(Decimal(0)) { $0 + $1.amount })

        // Повторный прогон нечего материализовать — журнал не пополняется задним числом.
        #expect(bridge.materializeDueInterestIncome() == false)
        #expect(store.takeDigest() == nil)
    }

    @Test("Без стора мост работает как прежде")
    func materializationWithoutStoreStillWorks() throws {
        let (container, context, asOf) = try makeConfirmedDeposit(name: "Вклад Гамма", currency: "RUB")
        _ = container

        let bridge = AccountsCoreDepositCashflowBridge(
            modelContext: context, now: { asOf }, calendar: calendar, publishCommitted: {}
        )

        #expect(bridge.materializeDueInterestIncome() == true)
        let inserted = try context.fetch(FetchDescriptor<CashflowTransaction>())
            .filter { $0.importSourceRaw == DepositCashflowProjector.importSource }
        #expect(inserted.count == 2)
    }
}
