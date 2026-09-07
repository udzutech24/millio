//
//  CashflowScheduledCheckpointTests.swift
//  millioTests
//
//  Регрессии денежного пути авто-применения плановых операций:
//  1) чекпойнт разделён по scope (гостевая сессия не двигает чекпойнт владельца);
//  2) общий (до-scope) чекпойнт мигрирует в per-scope ключ ровно один раз;
//  3) провал применения не двигает чекпойнт — операция не теряется молча.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@MainActor
@Suite("CashflowScheduledService — чекпойнт авто-применения")
struct CashflowScheduledCheckpointTests {

    private static var retainedContainers: [ModelContainer] = []

    private static let ownerScope = "millio_user_owner"
    private static let guestScope = "millio_guest"

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
        let suiteName = "tests.cashflow.checkpoint.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func checkpointKey(_ scope: String) -> String {
        CashflowScheduledService.dueAutoApplyCheckpointKeyPrefix + scope
    }

    private func makeService(
        context: ModelContext,
        defaults: UserDefaults,
        scope: String,
        transactions: @escaping () -> [CashflowTransaction],
        onApply: @escaping (CashflowTransaction) async throws -> Void = { _ in }
    ) -> CashflowScheduledService {
        CashflowScheduledService(
            modelContext: context,
            defaults: defaults,
            scopeIdentifier: scope,
            now: { Date() },
            transactionsProvider: transactions,
            onTransactionsMutated: {},
            onResolveExchangeInfo: { _ in CashflowExchangeInfo(rate: nil, rateDate: nil, rateCurrency: nil) },
            onApplyRecurringToCard: { _ in },
            onApplyDuePlannedEffect: onApply,
            appliedNoticeStore: AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: scope),
            noticeAccountNameResolver: { _ in "" },
            noticeTitleResolver: { _ in "" }
        )
    }

    /// Плановый расход, дата которого уже наступила (due) и эффект ещё не применён.
    private func makeDueExpense(context: ModelContext, date: Date, amount: Double = 1_000) -> CashflowTransaction {
        let transaction = CashflowTransaction(
            transactionType: .expense,
            amount: amount,
            currency: "RUB",
            transactionDate: date,
            expenseCategory: .other
        )
        context.insert(transaction)
        return transaction
    }

    // MARK: - Дефект 1: изоляция по scope

    @Test("Гостевая сессия не двигает чекпойнт владельца")
    func guestDoesNotMoveOwnerCheckpoint() async throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let referenceNow = Date(timeIntervalSince1970: 1_788_000_000)
        let ownerCheckpoint = referenceNow.addingTimeInterval(-7_200)
        defaults.set(ownerCheckpoint, forKey: checkpointKey(Self.ownerScope))

        // Плановая операция владельца, наступившая после его чекпойнта.
        let ownerDue = makeDueExpense(context: context, date: referenceNow.addingTimeInterval(-3_600))

        // Гостевой стор своих плановых операций не имеет — провайдер пуст, как и его store.
        let guestService = makeService(context: context, defaults: defaults, scope: Self.guestScope, transactions: { [] })
        _ = await guestService.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)

        #expect(defaults.object(forKey: checkpointKey(Self.guestScope)) as? Date == referenceNow)
        #expect(defaults.object(forKey: checkpointKey(Self.ownerScope)) as? Date == ownerCheckpoint)

        // Чекпойнт владельца остался на месте — его операция всё ещё применяется.
        var applied: [CashflowTransaction] = []
        let ownerService = makeService(
            context: context,
            defaults: defaults,
            scope: Self.ownerScope,
            transactions: { [ownerDue] },
            onApply: { applied.append($0) }
        )
        _ = await ownerService.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)

        #expect(applied.count == 1)
        #expect(ownerDue.hasAppliedBalanceEffect)
        #expect(defaults.object(forKey: checkpointKey(Self.ownerScope)) as? Date == referenceNow)
    }

    // MARK: - Дефект 1: миграция старого общего ключа

    @Test("Общий чекпойнт мигрирует в per-scope ключ и не сбрасывает окно")
    func legacyCheckpointMigratesWithoutLosingWindow() async throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let referenceNow = Date(timeIntervalSince1970: 1_788_000_000)
        let legacyCheckpoint = referenceNow.addingTimeInterval(-7_200)
        defaults.set(legacyCheckpoint, forKey: CashflowScheduledService.legacyDueAutoApplyCheckpointKey)

        let due = makeDueExpense(context: context, date: referenceNow.addingTimeInterval(-3_600))
        var appliedCount = 0
        let service = makeService(
            context: context,
            defaults: defaults,
            scope: Self.ownerScope,
            transactions: { [due] },
            onApply: { _ in appliedCount += 1 }
        )

        _ = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)

        // Значение перенесено, а не обнулено: операция из окна [legacy, now] применилась.
        #expect(appliedCount == 1)
        #expect(defaults.object(forKey: checkpointKey(Self.ownerScope)) as? Date == referenceNow)
        #expect(defaults.object(forKey: CashflowScheduledService.legacyDueAutoApplyCheckpointKey) as? Date == legacyCheckpoint)
    }

    @Test("Повторный запуск не мигрирует общий ключ второй раз")
    func legacyMigrationRunsOnlyOnce() async throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let referenceNow = Date(timeIntervalSince1970: 1_788_000_000)
        let legacyCheckpoint = referenceNow.addingTimeInterval(-7_200)
        defaults.set(legacyCheckpoint, forKey: CashflowScheduledService.legacyDueAutoApplyCheckpointKey)

        var visible: [CashflowTransaction] = []
        var applied: [CashflowTransaction] = []
        let service = makeService(
            context: context,
            defaults: defaults,
            scope: Self.ownerScope,
            transactions: { visible },
            onApply: { applied.append($0) }
        )

        // Первый прогон: миграция + сдвиг чекпойнта на referenceNow.
        _ = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)
        #expect(defaults.object(forKey: checkpointKey(Self.ownerScope)) as? Date == referenceNow)

        // Второй прогон: операция из ДО-чекпойнтного окна. Повторная миграция откатила бы чекпойнт
        // к legacy-значению и применила бы её задним числом — этого быть не должно.
        let stale = makeDueExpense(context: context, date: referenceNow.addingTimeInterval(-3_600))
        visible = [stale]
        let laterNow = referenceNow.addingTimeInterval(3_600)
        _ = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: laterNow)

        #expect(applied.isEmpty)
        #expect(!stale.hasAppliedBalanceEffect)
        #expect(defaults.object(forKey: checkpointKey(Self.ownerScope)) as? Date == laterNow)
    }

    // MARK: - Дефект 2: провал применения не двигает чекпойнт

    @Test("Упавшее применение оставляет чекпойнт и повторяется в следующем прогоне")
    func failedApplyKeepsCheckpoint() async throws {
        let context = try makeContext()
        let defaults = makeDefaults()
        let referenceNow = Date(timeIntervalSince1970: 1_788_000_000)
        let checkpoint = referenceNow.addingTimeInterval(-7_200)
        defaults.set(checkpoint, forKey: checkpointKey(Self.ownerScope))

        let healthy = makeDueExpense(context: context, date: referenceNow.addingTimeInterval(-5_400), amount: 100)
        let failing = makeDueExpense(context: context, date: referenceNow.addingTimeInterval(-3_600), amount: 200)

        var shouldFail = true
        var applyCalls: [Double] = []
        let service = makeService(
            context: context,
            defaults: defaults,
            scope: Self.ownerScope,
            transactions: { [healthy, failing] },
            onApply: { transaction in
                if shouldFail && transaction.amount == 200 {
                    throw CashflowMonthMutationPolicyError.closedMonth
                }
                applyCalls.append(transaction.amount)
            }
        )

        _ = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: referenceNow)

        #expect(applyCalls == [100])
        #expect(healthy.hasAppliedBalanceEffect)
        #expect(!failing.hasAppliedBalanceEffect)
        // Ключевой инвариант: провалившаяся операция осталась внутри окна.
        #expect(defaults.object(forKey: checkpointKey(Self.ownerScope)) as? Date == checkpoint)

        // Следующий прогон дожимает только её — успешная отсекается hasAppliedBalanceEffect.
        shouldFail = false
        let laterNow = referenceNow.addingTimeInterval(60)
        _ = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: laterNow)

        #expect(applyCalls == [100, 200])
        #expect(failing.hasAppliedBalanceEffect)
        #expect(defaults.object(forKey: checkpointKey(Self.ownerScope)) as? Date == laterNow)
    }
}
