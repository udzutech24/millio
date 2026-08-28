//
//  CashflowCoreAccountPersistenceTests.swift
//  millioTests
//
//  Шаг 1 плана 2026-08-27__cashflow-save-error-and-account-picker.
//  Баг владельца: расход на счёт нового ядра (Account) не сохранялся — алерт «Транзакция не
//  сохранена». Причина: `isAmountAvailable` резолвил счёт только через легаси `Card`, а пикер
//  кладёт в то же поле `cardID` идентификатор core-счёта.
//  Тесты идут через реальный `CashflowViewModel.persistTransaction` (путь создания целиком),
//  а не через изолированную проверку — урок `millio-integration-test-creation-path`.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Cashflow: сохранение расхода на счёт нового ядра")
@MainActor
struct CashflowCoreAccountPersistenceTests {

    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    private func makeViewModel(_ ctx: ModelContext) -> CashflowViewModel {
        let viewModel = CashflowViewModel(modelContext: ctx)
        viewModel.state.displayCurrency = "RUB"
        return viewModel
    }

    private func expense(amount: Double, cardID: String, date: Date = Date()) -> CashflowTransaction {
        CashflowTransaction(
            transactionType: .expense,
            amount: amount,
            currency: "RUB",
            transactionDate: date,
            cardID: cardID
        )
    }

    private func balance(of account: Account) -> Double {
        NSDecimalNumber(
            decimal: AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: Date())
        ).doubleValue
    }

    // MARK: - 1. Расход на core-счёт сохраняется (репро владельца)

    @Test("Расход на счёт нового ядра сохраняется и списывает баланс")
    func expenseOnCoreAccountIsPersisted() async throws {
        let ctx = try makeContext()
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Кв Светлогорск", kind: .debitCard, currency: "RUB", openingBalance: 100_000)
        try ctx.save()

        let viewModel = makeViewModel(ctx)
        let saved = await viewModel.persistTransaction(
            expense(amount: 53_500, cardID: account.id.uuidString),
            dismissEditorOnSuccess: false
        )

        #expect(saved, "Расход на core-счёт должен сохраняться (баг: возвращалось false → алерт)")
        #expect(abs(balance(of: account) - 46_500) < 0.01)
    }

    // MARK: - 2. Защита от овердрафта жива в обоих мирах

    @Test("Расход сверх остатка легаси-карты по-прежнему блокируется")
    func expenseOverLegacyCardBalanceIsRejected() async throws {
        let ctx = try makeContext()
        let card = Card(name: "Легаси карта", cardNumber: "1234", cardType: .debit, currency: "RUB", balance: 1_000)
        ctx.insert(card)
        try ctx.save()

        let viewModel = makeViewModel(ctx)
        let saved = await viewModel.persistTransaction(
            expense(amount: 5_000, cardID: card.cardUniqueID),
            dismissEditorOnSuccess: false
        )

        #expect(saved == false, "Проверка достаточности средств для легаси-карт не должна быть ослаблена фиксом")
        #expect(abs(card.balance - 1_000) < 0.01)
    }

    @Test("Расход сверх остатка core-счёта блокируется (фикс не возвращает безусловное true)")
    func expenseOverCoreAccountBalanceIsRejected() async throws {
        let ctx = try makeContext()
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Наличные", kind: .cash, currency: "RUB", openingBalance: 1_000)
        try ctx.save()

        let viewModel = makeViewModel(ctx)
        let saved = await viewModel.persistTransaction(
            expense(amount: 5_000, cardID: account.id.uuidString),
            dismissEditorOnSuccess: false
        )

        #expect(saved == false, "Антипаттерн №1 стресс-теста: овердрафт core-счёта не должен проходить молча")
        #expect(abs(balance(of: account) - 1_000) < 0.01)
    }

    // MARK: - 3. create → edit суммы → баланс сошёлся

    @Test("Правка суммы расхода на core-счёте не двоит событие и сходит по балансу")
    func editingCoreAccountExpenseKeepsBalanceConsistent() async throws {
        let ctx = try makeContext()
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Основной счёт", kind: .debitCard, currency: "RUB", openingBalance: 100_000)
        try ctx.save()

        let viewModel = makeViewModel(ctx)
        let created = expense(amount: 10_000, cardID: account.id.uuidString)
        #expect(await viewModel.persistTransaction(created, dismissEditorOnSuccess: false))
        #expect(abs(balance(of: account) - 90_000) < 0.01)

        let persisted = try #require(
            try ctx.fetch(FetchDescriptor<CashflowTransaction>()).first,
            "После создания в сторе должна быть ровно одна транзакция"
        )
        let edited = await viewModel.persistTransaction(
            expense(amount: 30_000, cardID: account.id.uuidString),
            replacing: persisted,
            dismissEditorOnSuccess: false
        )

        #expect(edited, "Правка суммы должна сохраняться: старое событие исключается из проверки средств")
        #expect(abs(balance(of: account) - 70_000) < 0.01, "Баланс = 100 000 − 30 000, без учёта старой суммы")

        let expenseRaw = AccountEventType.expense.rawValue
        let events = try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.typeRaw == expenseRaw }
        ))
        #expect(events.count == 1, "Событие правится, а не дублируется")
    }
}
