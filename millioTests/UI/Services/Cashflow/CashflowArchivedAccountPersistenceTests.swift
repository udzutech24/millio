//
//  CashflowArchivedAccountPersistenceTests.swift
//  millioTests
//
//  A2 (ревью round 1, зона «Архивные счета»): до фикса `upsertEvent` бросал `accountNotWritable`
//  ДО мутации ядра, но `CashflowPersistenceService` для недебетовых счетов не считал эту ошибку
//  блокирующей — легаси `CashflowTransaction` сохранялась с новой суммой, а событие ядра
//  оставалось старым (расхождение ленты и ядра без единого сигнала человеку).
//  Тест идёт через реальный `CashflowViewModel.persistTransaction` (путь создания → правки
//  целиком), а не через изолированную проверку одной функции — урок
//  `millio-integration-test-creation-path`.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Cashflow: правка транзакции на архивном счёте (не-Debit продукт)")
@MainActor
struct CashflowArchivedAccountPersistenceTests {

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

    private func income(amount: Double, cardID: String) -> CashflowTransaction {
        CashflowTransaction(transactionType: .income, amount: amount, currency: "RUB", transactionDate: Date(), cardID: cardID)
    }

    @Test("Правка суммы дохода на архивированном наличном счёте блокируется, а не расходится с ядром")
    func editingIncomeOnArchivedCashAccountIsRejectedAndKeepsBothWorldsInSync() async throws {
        let ctx = try makeContext()
        let service = AccountsCoreService(modelContext: ctx)
        // .cash — недебетовый продукт (не входит в DebitCardContract.products), именно про такие
        // счета говорит A2: они не проходят через DebitCardOperationCoordinator.
        let account = try service.createAccount(name: "Кошелёк", kind: .cash, currency: "RUB", openingBalance: 0)
        try ctx.save()

        let viewModel = makeViewModel(ctx)
        let created = income(amount: 1_000, cardID: account.id.uuidString)
        #expect(await viewModel.persistTransaction(created, dismissEditorOnSuccess: false))

        let persisted = try #require(
            try ctx.fetch(FetchDescriptor<CashflowTransaction>()).first,
            "После создания в сторе должна быть ровно одна транзакция"
        )
        let persistedID = persisted.uniqueID

        // Архивируем счёт — правки задним числом запрещены (requireWritable).
        try service.archiveAccount(account)

        let edited = await viewModel.persistTransaction(
            income(amount: 5_000, cardID: account.id.uuidString),
            replacing: persisted,
            dismissEditorOnSuccess: false
        )

        #expect(edited == false, "A2: правка легаси-транзакции на архивном счёте должна блокироваться, не расходиться молча")

        // ГЛАВНАЯ ПРОВЕРКА (A2): читаем из контекста, а не полагаемся на return-значение — rollback
        // должен был откатить И CashflowTransaction.amount, И оставить AccountEvent нетронутым.
        let transactionAfter = try #require(
            try ctx.fetch(FetchDescriptor<CashflowTransaction>(
                predicate: #Predicate<CashflowTransaction> { $0.uniqueID == persistedID }
            )).first
        )
        #expect(transactionAfter.amount == 1_000, "Старая сумма транзакции должна остаться на месте после отката")

        let events = try ctx.fetch(FetchDescriptor<AccountEvent>(
            predicate: #Predicate<AccountEvent> { $0.sourceTransactionID == persistedID }
        ))
        #expect(events.count == 1)
        #expect(events.first?.amount == 1_000, "Событие ядра не должно было отстать от отменённой правки ленты")

        // Ревью round 2 (A2, «сигнал человеку не понятный»): редактор раньше показывал ОДИНАКОВЫЙ
        // generic-алерт независимо от причины отказа — человек проверял бы баланс/дату впустую.
        // `state.saveBlockedErrorMessage` — конкретный человекочитаемый текст для ИМЕННО этой причины.
        #expect(
            viewModel.state.saveBlockedErrorMessage == AccountsCoreServiceError.accountNotWritable.errorDescription,
            "Причина отказа должна быть точно определена как «архивный/удалённый счёт», а не общей"
        )
    }

    @Test("saveBlockedErrorMessage сбрасывается на успешном сохранении, не остаётся от прошлой ошибки")
    func saveBlockedErrorMessageResetsAfterSuccessfulSave() async throws {
        let ctx = try makeContext()
        let service = AccountsCoreService(modelContext: ctx)
        let account = try service.createAccount(name: "Кошелёк", kind: .cash, currency: "RUB", openingBalance: 0)
        try ctx.save()

        let viewModel = makeViewModel(ctx)
        let created = income(amount: 1_000, cardID: account.id.uuidString)
        #expect(await viewModel.persistTransaction(created, dismissEditorOnSuccess: false))
        let persisted = try #require(try ctx.fetch(FetchDescriptor<CashflowTransaction>()).first)

        try service.archiveAccount(account)
        _ = await viewModel.persistTransaction(
            income(amount: 5_000, cardID: account.id.uuidString),
            replacing: persisted,
            dismissEditorOnSuccess: false
        )
        #expect(viewModel.state.saveBlockedErrorMessage != nil, "Предварительное условие: сообщение установлено")

        // Восстанавливаем счёт и сохраняем снова — сообщение от ПРЕДЫДУЩЕЙ заблокированной попытки
        // не должно остаться видимым для следующей, успешной.
        try service.restoreAccount(account)
        let succeeded = await viewModel.persistTransaction(
            income(amount: 2_000, cardID: account.id.uuidString),
            replacing: persisted,
            dismissEditorOnSuccess: false
        )
        #expect(succeeded)
        #expect(viewModel.state.saveBlockedErrorMessage == nil, "Сообщение об архиве не должно пережить успешное сохранение")
    }
}
