//
//  CashflowScheduledArchivedAccountRecurringTests.swift
//  millioTests
//
//  Ревью round 2 (зона «Архивные счета»): барьер `requireWritable` (БАГ 6, 74ee608) ловит только
//  ручную правку — генератор повторяющихся операций (`CashflowScheduledService.
//  generateRecurringTransactionsIfNeeded`) о нём не знал вовсе и каждый месяц вставлял новый
//  инстанс шаблона в ленту/бюджеты, даже если счёт-источник шаблона архивирован. Итог для
//  человека: заархивировал кошелёк с ежемесячным доходом — операция продолжает появляться каждый
//  месяц, без единого сигнала, баланса счёта в ядре при этом не касается.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@MainActor
@Suite("CashflowScheduledService: повторяющиеся операции на архивном core-счёте")
struct CashflowScheduledArchivedAccountRecurringTests {

    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "tests.cashflow.scheduled-archived.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("Архивный core-счёт: генератор не вставляет новый инстанс повторяющейся операции")
    func generatorSkipsOccurrenceWhenTemplateAccountIsArchived() async throws {
        let ctx = try makeContext()
        let accountsService = AccountsCoreService(modelContext: ctx)
        let account = try accountsService.createAccount(
            name: "Зарплатная карта", kind: .cash, currency: "RUB", openingBalance: 0
        )
        let bridge = AccountsCoreCashflowBridge(
            modelContext: ctx,
            accountsCoreService: accountsService,
            historicalRateStore: HistoricalRateStore(modelContext: ctx)
        )

        let calendar = Calendar.current
        let anchor = calendar.date(byAdding: .month, value: -2, to: calendar.startOfDay(for: Date()))!
        let template = CashflowTransaction(
            transactionType: .income,
            amount: 50_000,
            currency: "RUB",
            transactionDate: anchor,
            cardID: account.id.uuidString,
            recurrenceRule: .monthly,
            recurrenceSeriesID: UUID().uuidString
        )
        ctx.insert(template)
        try ctx.save()

        // Архивируем счёт-источник ПОСЛЕ создания шаблона — ровно сценарий из ревью.
        try accountsService.archiveAccount(account)

        let defaults = makeDefaults()
        let scope = "test-scope"
        var appliedCallCount = 0
        let service = CashflowScheduledService(
            modelContext: ctx,
            defaults: defaults,
            scopeIdentifier: scope,
            now: { Date() },
            transactionsProvider: { (try? ctx.fetch(FetchDescriptor<CashflowTransaction>())) ?? [] },
            onTransactionsMutated: {},
            onResolveExchangeInfo: { _ in CashflowExchangeInfo(rate: nil, rateDate: nil, rateCurrency: nil) },
            onApplyRecurringToCard: { _ in appliedCallCount += 1 },
            onApplyDuePlannedEffect: { _ in },
            appliedNoticeStore: AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: scope),
            noticeAccountNameResolver: { _ in "" },
            noticeTitleResolver: { _ in "" },
            onIsSourceAccountWritable: { transaction in bridge.isSourceAccountWritable(for: transaction) }
        )

        let didGenerate = await service.generateRecurringTransactionsIfNeeded()

        #expect(didGenerate == false, "На архивном счёте новый инстанс вставляться не должен")
        // ГЛАВНАЯ ПРОВЕРКА: в сторе остаётся только сам шаблон — ни одного сгенерированного
        // инстанса за пропущенные месяцы, и `onApplyRecurringToCard` (значит, и попытка синка в
        // ядро/попадание в сводку «применено») вообще не вызывается.
        let allTransactions = try ctx.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(allTransactions.count == 1, "В ленте не должно быть ничего кроме шаблона")
        #expect(appliedCallCount == 0, "onApplyRecurringToCard не должен вызываться — инстанс не создавался вовсе")
    }
}
