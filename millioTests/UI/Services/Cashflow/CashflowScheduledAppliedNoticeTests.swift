//
//  CashflowScheduledAppliedNoticeTests.swift
//  millioTests
//
//  Ф1 плана plans/2026-09-05__planned-operations-applied-notice.md.
//  Инвариант: в журнале сводки оказывается ровно то, что реально применилось и сохранилось.
//  Записи копятся в буфере и уходят в журнал только после успешного modelContext.save().
//

import Foundation
import SwiftData
import Testing
@testable import millio

@MainActor
@Suite("CashflowScheduledService — журнал применённых плановых операций")
struct CashflowScheduledAppliedNoticeTests {

    private static var retainedContainers: [ModelContainer] = []

    private static let scope = "millio_user_owner"
    private static let accountName = "Основная карта"

    // MARK: - Harness

    private func makeContext() throws -> ModelContext {
        let schema = Schema([CashflowTransaction.self, CashflowMonthClosureEvent.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "tests.cashflow.applied-notice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func checkpointKey() -> String {
        CashflowScheduledService.dueAutoApplyCheckpointKeyPrefix + Self.scope
    }

    private func makeService(
        context: ModelContext,
        defaults: UserDefaults,
        store: AppliedPlannedNoticeStore,
        transactions: @escaping () -> [CashflowTransaction],
        now: @escaping () -> Date = { Date() },
        onApply: @escaping (CashflowTransaction) async throws -> Void = { _ in }
    ) -> CashflowScheduledService {
        CashflowScheduledService(
            modelContext: context,
            defaults: defaults,
            scopeIdentifier: Self.scope,
            now: now,
            transactionsProvider: transactions,
            onTransactionsMutated: {},
            onResolveExchangeInfo: { _ in CashflowExchangeInfo(rate: nil, rateDate: nil, rateCurrency: nil) },
            onApplyRecurringToCard: { _ in },
            onApplyDuePlannedEffect: onApply,
            appliedNoticeStore: store,
            noticeAccountNameResolver: { _ in Self.accountName },
            noticeTitleResolver: { $0.note ?? "" }
        )
    }

    private func makeDueExpense(
        context: ModelContext,
        date: Date,
        amount: Double = 1_000,
        note: String = "Аренда"
    ) -> CashflowTransaction {
        let transaction = CashflowTransaction(
            transactionType: .expense,
            amount: amount,
            currency: "RUB",
            transactionDate: date,
            expenseCategory: .other,
            note: note
        )
        context.insert(transaction)
        return transaction
    }

    // MARK: - Успешное применение

    @Test("Применённая разовая плановая операция даёт ровно одну запись с именем счёта и знаком расхода")
    func successfulApplyWritesSingleScheduledEntry() async throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let store = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.scope)
        let referenceNow = Date(timeIntervalSince1970: 1_788_000_000)
        defaults.set(referenceNow.addingTimeInterval(-7_200), forKey: checkpointKey())

        let due = makeDueExpense(context: context, date: referenceNow.addingTimeInterval(-3_600))
        let service = makeService(context: context, defaults: defaults, store: store, transactions: { [due] })

        _ = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)

        let digest = try #require(store.takeDigest())
        #expect(digest.totalCount == 1)
        #expect(digest.details.count == 1)
        let entry = try #require(digest.details.first)
        #expect(entry.kind == .scheduled)
        #expect(entry.accountName == Self.accountName)
        #expect(entry.title == "Аренда")
        #expect(entry.currencyCode == "RUB")
        // Расход обязан быть отрицательным: нетто-итог сводки — простое сложение сумм.
        #expect(entry.amount == Decimal(-1_000))
        #expect(digest.expenseCount == 1)
        #expect(digest.totalsByCurrency["RUB"] == Decimal(-1_000))
    }

    @Test("Доходная плановая операция пишется положительной суммой")
    func appliedIncomeKeepsPositiveSign() async throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let store = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.scope)
        let referenceNow = Date(timeIntervalSince1970: 1_788_000_000)
        defaults.set(referenceNow.addingTimeInterval(-7_200), forKey: checkpointKey())

        let income = CashflowTransaction(
            transactionType: .income,
            amount: 5_000,
            currency: "RUB",
            transactionDate: referenceNow.addingTimeInterval(-3_600),
            incomeCategory: .salary
        )
        context.insert(income)

        let service = makeService(context: context, defaults: defaults, store: store, transactions: { [income] })
        _ = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)

        let digest = try #require(store.takeDigest())
        #expect(digest.details.first?.amount == Decimal(5_000))
        #expect(digest.incomeCount == 1)
    }

    // MARK: - Провал применения

    @Test("Упавшее применение не оставляет в журнале ничего")
    func failedApplyWritesNothing() async throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let store = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.scope)
        let referenceNow = Date(timeIntervalSince1970: 1_788_000_000)
        defaults.set(referenceNow.addingTimeInterval(-7_200), forKey: checkpointKey())

        let due = makeDueExpense(context: context, date: referenceNow.addingTimeInterval(-3_600))
        let service = makeService(
            context: context,
            defaults: defaults,
            store: store,
            transactions: { [due] },
            onApply: { _ in throw CashflowMonthMutationPolicyError.closedMonth }
        )

        _ = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)

        #expect(!due.hasAppliedBalanceEffect)
        #expect(!store.hasPending)
        #expect(store.takeDigest() == nil)
    }

    @Test("В журнал идут только применённые; повтор провалившейся не дублирует успешную")
    func mixedRunJournalsOnlyAppliedAndRetryDoesNotDuplicate() async throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let store = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.scope)
        let referenceNow = Date(timeIntervalSince1970: 1_788_000_000)
        defaults.set(referenceNow.addingTimeInterval(-7_200), forKey: checkpointKey())

        let healthy = makeDueExpense(
            context: context,
            date: referenceNow.addingTimeInterval(-5_400),
            amount: 100,
            note: "Связь"
        )
        let failing = makeDueExpense(
            context: context,
            date: referenceNow.addingTimeInterval(-3_600),
            amount: 200,
            note: "Подписка"
        )

        var shouldFail = true
        let service = makeService(
            context: context,
            defaults: defaults,
            store: store,
            transactions: { [healthy, failing] },
            onApply: { transaction in
                if shouldFail && transaction.amount == 200 {
                    throw CashflowMonthMutationPolicyError.closedMonth
                }
            }
        )

        _ = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)
        #expect(store.hasPending)

        // Второй прогон дожимает провалившуюся. Чекпойнт удержан, поэтому окно то же — но успешная
        // операция второй записи не даёт: её отсекает hasAppliedBalanceEffect.
        shouldFail = false
        _ = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow.addingTimeInterval(60))

        let digest = try #require(store.takeDigest())
        #expect(digest.totalCount == 2)
        #expect(digest.details.map(\.title) == ["Связь", "Подписка"])
        #expect(digest.totalsByCurrency["RUB"] == Decimal(-300))
    }

    // MARK: - Повторяющиеся

    @Test("Сгенерированная повторяющаяся операция пишется с kind == .recurring")
    func recurringGenerationWritesRecurringKind() async throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let store = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.scope)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let anchor = try #require(calendar.date(byAdding: .day, value: -7, to: today))

        // Недельный шаблон, якорь неделю назад: ровно одно вхождение (сегодня) попадает в окно.
        let template = CashflowTransaction(
            transactionType: .expense,
            amount: 750,
            currency: "RUB",
            transactionDate: anchor,
            expenseCategory: .other,
            note: "Тренировки",
            recurrenceRule: .weekly,
            recurrenceSeriesID: UUID().uuidString
        )
        context.insert(template)

        let service = makeService(
            context: context,
            defaults: defaults,
            store: store,
            transactions: { [template] },
            now: { today }
        )

        let didGenerate = await service.generateRecurringTransactionsIfNeeded()
        #expect(didGenerate)

        let digest = try #require(store.takeDigest())
        #expect(digest.totalCount == 1)
        let entry = try #require(digest.details.first)
        #expect(entry.kind == .recurring)
        #expect(entry.title == "Тренировки")
        #expect(entry.accountName == Self.accountName)
        #expect(entry.amount == Decimal(-750))
    }
}
