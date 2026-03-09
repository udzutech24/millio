import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct FinanceBalanceAuditViewModelTests {
    private static let schema = Schema([
        Card.self,
        Credit.self,
        Investment.self,
        FinanceGroup.self,
        FinanceAccount.self,
        CashflowTransaction.self,
        HistoricalRate.self
    ])
    private static var retainedContainers: [ModelContainer] = []

    private func createTestModelContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        let context = container.mainContext
        try context.save()
        return context
    }

    @Test("Audit показывает реальный исторический баланс карты на выбранную дату")
    func testAuditUsesHistoricalBalanceForSelectedDay() async throws {
        let modelContext = try createTestModelContext()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let createdAt = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 8))!
        let expenseDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 10))!
        let updatedAt = calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 10))!
        let targetDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 12))!

        let card = Card(name: "Фридом $", cardNumber: "0000", bank: .other, cardType: .debit, currency: "USD")
        card.balance = 700
        card.initialBalance = 1000
        card.hasInitialBalance = true
        card.createdAt = createdAt
        card.updatedAt = updatedAt
        modelContext.insert(card)

        let group = FinanceGroup(name: "Иностранные карты", colorHex: "#0F2233")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)

        let expense = CashflowTransaction(
            transactionType: .expense,
            amount: 300,
            currency: "USD",
            transactionDate: expenseDate,
            cardID: card.cardUniqueID,
            note: "test expense"
        )
        modelContext.insert(expense)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: false
        )

        let auditViewModel = FinanceBalanceAuditViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            selectedDate: targetDate
        )

        try await waitUntil(timeout: 1.0) {
            auditViewModel.rows.contains(where: { $0.title == "Фридом $" })
        }

        let freedomRow = auditViewModel.rows.first(where: { $0.title == "Фридом $" })
        #expect(freedomRow != nil)
        #expect(abs((freedomRow?.value ?? 0) - 1000.0) < 0.01)
    }

    @Test("Audit позволяет вручную переопределить значение живого счета за дату и откатить удалением")
    func testAuditAllowsOverrideForLiveAccountAndDeleteOverride() async throws {
        let modelContext = try createTestModelContext()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let createdAt = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 8))!
        let expenseDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 10))!
        let updatedAt = calendar.date(from: DateComponents(year: 2026, month: 3, day: 4, hour: 10))!
        let targetDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 12))!

        let card = Card(name: "Фридом $", cardNumber: "0000", bank: .other, cardType: .debit, currency: "USD")
        card.balance = 700
        card.initialBalance = 1000
        card.hasInitialBalance = true
        card.createdAt = createdAt
        card.updatedAt = updatedAt
        modelContext.insert(card)

        let group = FinanceGroup(name: "Иностранные карты", colorHex: "#0F2233")
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        modelContext.insert(group)
        modelContext.insert(account)

        let expense = CashflowTransaction(
            transactionType: .expense,
            amount: 300,
            currency: "USD",
            transactionDate: expenseDate,
            cardID: card.cardUniqueID,
            note: "test expense"
        )
        modelContext.insert(expense)
        try modelContext.save()

        let financeViewModel = FinanceViewModel(
            modelContext: modelContext,
            currencyService: MockDynamicsCurrencyRateService(),
            skipInitialLoad: false
        )

        let auditViewModel = FinanceBalanceAuditViewModel(
            modelContext: modelContext,
            financeViewModel: financeViewModel,
            selectedDate: targetDate
        )

        try await waitUntil(timeout: 1.0) {
            auditViewModel.rows.contains(where: { $0.title == "Фридом $" })
        }

        guard let row = auditViewModel.rows.first(where: { $0.title == "Фридом $" }) else {
            Issue.record("Row not found")
            return
        }

        #expect(abs(row.value - 1000.0) < 0.01)

        auditViewModel.setValue(777, for: row)
        let afterOverride = auditViewModel.rows.first(where: { $0.id == row.id })
        #expect(afterOverride != nil)
        #expect(abs((afterOverride?.value ?? 0) - 777.0) < 0.01)

        if let overriddenRow = afterOverride {
            auditViewModel.deleteValue(for: overriddenRow)
        }

        try await waitUntil(timeout: 1.0) {
            guard let refreshed = auditViewModel.rows.first(where: { $0.id == row.id }) else { return false }
            return abs(refreshed.value - 1000.0) < 0.01
        }
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async throws {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("Timed out while waiting for condition")
    }
}
