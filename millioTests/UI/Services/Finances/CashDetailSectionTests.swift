import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф2: сверка наличных — единственная операция, которую экран `.cash` показывает сам.
/// Проверяем витрину даты сверки и то, что сверка не плодит доход/расход, а пишет корректировку.
@Suite("Наличные: сверка кошелька")
@MainActor
struct CashDetailSectionTests {

    /// Контейнер держим живым на весь прогон: без сильной ссылки `mainContext` переживает
    /// свой контейнер и падает на первом же обращении (та же ловушка, что в counter-тестах).
    private static var retained: [AnyObject] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retained.append(container)
        return container.mainContext
    }

    @Test("Без корректировок — «сверки ещё не было»")
    func noAdjustmentsMeansNeverReconciled() {
        #expect(CashReconciliationPresentation.lastReconciliationDate(events: []) == nil)

        let subtitle = CashReconciliationPresentation.subtitle(
            lastReconciliation: nil, locale: Locale(identifier: "ru")
        )
        #expect(subtitle == "Сверки ещё не было")
    }

    @Test("Дата сверки — самая поздняя корректировка, доходы/расходы её не задают")
    func lastReconciliationIgnoresNonAdjustmentEvents() throws {
        let context = try makeContext()
        let service = AccountsCoreService(modelContext: context)
        let account = try service.createAccount(
            name: "Кошелёк", kind: .cash, currency: "RUB", openingBalance: 1_000
        )
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = old.addingTimeInterval(86_400 * 10)

        _ = try service.adjustBalance(account: account, to: 900, on: old)
        try service.recordEvent(account: account, type: .expense, amount: 100, date: recent.addingTimeInterval(60))
        _ = try service.adjustBalance(account: account, to: 750, on: recent)

        let date = try #require(
            CashReconciliationPresentation.lastReconciliationDate(events: account.events ?? [])
        )
        #expect(date == recent)
    }

    @Test("Сверка пишет одну корректировку на разницу, а не новую операцию")
    func reconciliationRecordsSingleAdjustmentDelta() throws {
        let context = try makeContext()
        let service = AccountsCoreService(modelContext: context)
        let account = try service.createAccount(
            name: "Кошелёк", kind: .cash, currency: "RUB", openingBalance: 1_000
        )

        _ = try service.adjustBalance(account: account, to: 820)

        let events = account.events ?? []
        let adjustments = events.filter { $0.type == .adjustment }
        #expect(adjustments.count == 1)
        #expect(adjustments.first?.amount == -180)
        #expect(!events.contains { $0.type == .expense || $0.type == .income })
        #expect(AccountBalanceEngine.balanceAt(events: events, kind: .cash, on: Date()) == 820)
    }
}
