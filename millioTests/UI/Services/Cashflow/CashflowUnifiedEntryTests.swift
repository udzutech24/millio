//
//  CashflowUnifiedEntryTests.swift
//  millioTests
//
//  Регресс-тесты Фазы 3 редизайна add-flow (чекпоинт 3d):
//  per-tab черновики быстрого ввода, идемпотентность открытия шита и
//  anti-double-tap при сохранении транзакции.
//

import Foundation
import Testing
import SwiftData
@testable import millio

@MainActor
struct CashflowUnifiedEntryTests {
    private static let schema = Schema([
        Card.self,
        Investment.self,
        FinanceGroup.self,
        FinanceAccount.self,
        CashflowTransaction.self,
        CashflowCustomCategory.self,
        CashflowSystemCategoryOverride.self,
        BudgetPlan.self,
        BudgetCategoryLimit.self,
        HistoricalRate.self
    ])
    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        let context = container.mainContext
        try context.save()
        return context
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "CashflowUnifiedEntryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set("RUB", forKey: "primaryCurrencyCode")
        return defaults
    }

    // MARK: - Per-tab drafts

    @Test("Черновик быстрого ввода: сумма+валюта переживают переоткрытие для каждого таба")
    func draftsPersistPerTab() throws {
        let vm = CashflowViewModel(modelContext: try makeContext(), defaults: makeIsolatedDefaults())

        // По умолчанию черновик пуст.
        #expect(vm.quickEntryDraft(for: .expense) == CashflowQuickEntryDraft())
        #expect(vm.quickEntryDraft(for: .income) == CashflowQuickEntryDraft())

        vm.updateQuickEntryDraft(
            CashflowQuickEntryDraft(amountText: "150", note: "обед", selectedCardID: "card-1", overrideCurrency: "USD"),
            for: .expense
        )
        vm.updateQuickEntryDraft(
            CashflowQuickEntryDraft(amountText: "5000", overrideCurrency: "EUR"),
            for: .income
        )
        vm.updateQuickEntryDraft(
            CashflowQuickEntryDraft(amountText: "42", overrideCurrency: "GBP"),
            for: .transfer
        )

        // Черновики независимы по табам (переживают «переоткрытие» = повторное чтение из VM).
        #expect(vm.quickEntryDraft(for: .expense).amountText == "150")
        #expect(vm.quickEntryDraft(for: .expense).overrideCurrency == "USD")
        #expect(vm.quickEntryDraft(for: .income).amountText == "5000")
        #expect(vm.quickEntryDraft(for: .income).overrideCurrency == "EUR")
        #expect(vm.quickEntryDraft(for: .transfer).amountText == "42")
        #expect(vm.quickEntryDraft(for: .transfer).overrideCurrency == "GBP")

        // Расходный черновик не протёк в доходный.
        #expect(vm.quickEntryDraft(for: .income).note == "")
    }

    @Test("Пустой черновик очищается из VM, непустой — сохраняется")
    func emptyDraftIsCleared() throws {
        let vm = CashflowViewModel(modelContext: try makeContext(), defaults: makeIsolatedDefaults())

        vm.updateQuickEntryDraft(CashflowQuickEntryDraft(amountText: "10"), for: .expense)
        #expect(vm.quickEntryDrafts[.expense] != nil)

        vm.updateQuickEntryDraft(CashflowQuickEntryDraft(), for: .expense)
        #expect(vm.quickEntryDrafts[.expense] == nil)

        vm.updateQuickEntryDraft(CashflowQuickEntryDraft(amountText: "20"), for: .expense)
        vm.clearQuickEntryDraft(for: .expense)
        #expect(vm.quickEntryDrafts[.expense] == nil)
    }

    // MARK: - Idempotent open

    @Test("Повторный addTransaction при открытом шите не пере-инициализирует состояние")
    func addTransactionIsIdempotentWhileEditorShown() throws {
        let vm = CashflowViewModel(modelContext: try makeContext(), defaults: makeIsolatedDefaults())

        vm.handle(.addTransaction(.expense))
        #expect(vm.state.showTransactionEditor)
        #expect(vm.state.creatingTransactionType == .expense)

        // Повторный тап другим типом игнорируется, пока шит открыт.
        vm.handle(.addTransaction(.income))
        #expect(vm.state.creatingTransactionType == .expense)
    }

    // MARK: - Anti-double-tap

    @Test("Anti-double-tap: одновременный второй persist отклоняется, дубль не создаётся")
    func concurrentPersistIsRejected() async throws {
        let context = try makeContext()
        let card = Card(name: "Карта", cardNumber: "1", bank: .other, cardType: .debit, currency: "RUB", balance: 10_000)
        context.insert(card)
        try context.save()

        let vm = CashflowViewModel(modelContext: context, defaults: makeIsolatedDefaults())
        vm.handle(.loadCards)

        func makeExpense() -> CashflowTransaction {
            CashflowTransaction(
                transactionType: .expense,
                amount: 100,
                currency: "RUB",
                transactionDate: Date(),
                cardID: card.cardUniqueID,
                expenseCategory: .bills,
                affectsCardBalance: false
            )
        }

        async let first = vm.persistTransaction(makeExpense())
        async let second = vm.persistTransaction(makeExpense())
        let results = await [first, second]

        // Ровно один вызов прошёл — второй отклонён guard'ом.
        #expect(results.filter { $0 }.count == 1)
        #expect(!vm.isPersistingTransaction)

        // В сторе ровно одна транзакция (дубля нет).
        let stored = try context.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(stored.count == 1)
    }
}
