//
//  CashflowArchivedAccountDeletionTests.swift
//  millioTests
//
//  Ревью round 2 (продолжение A2, зона «Архивные счета»): правка суммы блокировалась (A2, round 1),
//  а удаление строки ленты — нет. `deleteTransactionAsync`/`deleteTransactionWithoutRecalculation`
//  ловили ЛЮБУЮ ошибку `bridge.deleteEvents` только логом и всё равно удаляли `CashflowTransaction` —
//  строка исчезала из ленты, а `AccountEvent` архивного счёта оставался (обратное расхождение A2).
//  Тест идёт через реальный `CashflowViewModel`/`CashflowPersistenceService`, путь создания →
//  архивации → удаления целиком — урок `millio-integration-test-creation-path`.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Cashflow: удаление строки ленты на архивном счёте (не-Debit продукт)")
@MainActor
struct CashflowArchivedAccountDeletionTests {

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

    private func makeArchivedAccountWithTransaction(
        _ ctx: ModelContext
    ) async throws -> (service: AccountsCoreService, viewModel: CashflowViewModel, persistedID: String) {
        let service = AccountsCoreService(modelContext: ctx)
        // .cash — недебетовый продукт (не входит в DebitCardContract.products), тот же выбор
        // счёта, что в CashflowArchivedAccountPersistenceTests (A2, round 1).
        let account = try service.createAccount(name: "Кошелёк", kind: .cash, currency: "RUB", openingBalance: 0)
        try ctx.save()

        let viewModel = makeViewModel(ctx)
        let created = CashflowTransaction(
            transactionType: .income, amount: 1_000, currency: "RUB", transactionDate: Date(), cardID: account.id.uuidString
        )
        #expect(await viewModel.persistTransaction(created, dismissEditorOnSuccess: false))
        let persisted = try #require(
            try ctx.fetch(FetchDescriptor<CashflowTransaction>()).first,
            "После создания в сторе должна быть ровно одна транзакция"
        )
        let persistedID = persisted.uniqueID

        try service.archiveAccount(account)
        return (service, viewModel, persistedID)
    }

    @Test("deleteTransactionAsync: удаление на архивном счёте блокируется, история ядра не меняется")
    func deleteTransactionAsyncOnArchivedAccountIsRejectedAndKeepsCoreHistory() async throws {
        let ctx = try makeContext()
        let (_, viewModel, persistedID) = try await makeArchivedAccountWithTransaction(ctx)
        let persisted = try #require(try ctx.fetch(FetchDescriptor<CashflowTransaction>(
            predicate: #Predicate<CashflowTransaction> { $0.uniqueID == persistedID }
        )).first)

        await viewModel.persistenceService.deleteTransactionAsync(persisted, recalculate: true)

        // ГЛАВНАЯ ПРОВЕРКА: строка ленты НЕ удалена (раньше удалялась несмотря на отказ ядра),
        // и событие ядра тоже осталось на месте (не только не удалено сейчас — вообще нетронуто).
        let transactionsAfter = try ctx.fetch(FetchDescriptor<CashflowTransaction>(
            predicate: #Predicate<CashflowTransaction> { $0.uniqueID == persistedID }
        ))
        #expect(transactionsAfter.count == 1, "Удаление строки ленты на архивном счёте должно блокироваться")

        let events = try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == persistedID }
        ))
        #expect(events.count == 1, "Событие ядра архивного счёта не должно исчезать вместе со строкой ленты")
    }

    @Test("deleteTransactionWithoutRecalculation: удаление на архивном счёте тоже блокируется")
    func deleteTransactionWithoutRecalculationOnArchivedAccountIsRejected() async throws {
        let ctx = try makeContext()
        let (_, viewModel, persistedID) = try await makeArchivedAccountWithTransaction(ctx)
        let persisted = try #require(try ctx.fetch(FetchDescriptor<CashflowTransaction>(
            predicate: #Predicate<CashflowTransaction> { $0.uniqueID == persistedID }
        )).first)

        viewModel.persistenceService.deleteTransactionWithoutRecalculation(persisted)

        let transactionsAfter = try ctx.fetch(FetchDescriptor<CashflowTransaction>(
            predicate: #Predicate<CashflowTransaction> { $0.uniqueID == persistedID }
        ))
        #expect(transactionsAfter.count == 1, "Удаление без пересчёта на архивном счёте тоже должно блокироваться")

        let events = try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == persistedID }
        ))
        #expect(events.count == 1)
    }
}
