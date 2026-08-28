//
//  CashflowAccountPickerTests.swift
//  millioTests
//
//  Шаг 2 плана 2026-08-27__cashflow-save-error-and-account-picker: редизайн пикера счёта
//  (bottom sheet, избранные, остатки) + фикс резолва валюты счёта-получателя перевода.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Cashflow: пикер счёта")
@MainActor
struct CashflowAccountPickerTests {

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

    private func options(cards: [Card], coreAccounts: [Account]) -> [CashflowSelectableAccount] {
        CashflowSelectableAccountResolver.options(
            cards: cards,
            investments: [],
            linkedInvestmentIDs: [],
            transactionType: .expense,
            currency: "RUB",
            newCoreAccounts: coreAccounts
        )
    }

    // MARK: - 1. Коллизии id между двумя мирами счетов

    @Test("62 пары «core ↔ легаси по имени» дают уникальные id строк пикера")
    func twinAccountsDoNotCollideByID() throws {
        let ctx = try makeContext()
        let service = AccountsCoreService(modelContext: ctx)

        var cards: [Card] = []
        var accounts: [Account] = []
        for index in 0..<62 {
            let name = "Счёт \(index)"
            let card = Card(name: name, cardNumber: "\(1000 + index)", cardType: .debit, currency: "RUB", balance: 100)
            ctx.insert(card)
            cards.append(card)
            accounts.append(try service.createAccount(name: name, kind: .debitCard, currency: "RUB", openingBalance: 100))
        }
        try ctx.save()

        let resolved = options(cards: cards, coreAccounts: accounts)
        #expect(resolved.count == 124)
        #expect(Set(resolved.map(\.id)).count == resolved.count, "id строк пикера обязаны быть уникальны")
    }

    @Test("Одинаковый строковый ID в разных мирах даёт разные id строк")
    func sameRawIDInBothWorldsProducesDifferentRowIDs() {
        let sharedID = UUID()
        let legacy = CashflowSelectableAccount(
            kind: .legacyCard(cardID: sharedID.uuidString),
            title: "Легаси",
            currency: "RUB",
            isFavorite: false,
            prioritySortOrder: 0,
            updatedAt: Date()
        )
        let core = CashflowSelectableAccount(
            kind: .coreAccount(accountID: sharedID.uuidString),
            title: "Core",
            currency: "RUB",
            isFavorite: false,
            prioritySortOrder: 0,
            updatedAt: Date()
        )

        #expect(legacy.id != core.id)
        #expect(legacy.cardID == core.cardID, "В транзакцию оба мира кладут ID в одно поле cardID")
        #expect(core.isCoreAccount)
        #expect(legacy.isCoreAccount == false)
    }

    // MARK: - 2. Секции пикера

    @Test("Секция «Избранные» отделяется, порядок внутри секций сохраняется")
    func favoritesSectionKeepsSourceOrder() {
        func account(_ title: String, favorite: Bool) -> CashflowSelectableAccount {
            CashflowSelectableAccount(
                kind: .legacyCard(cardID: title),
                title: title,
                currency: "RUB",
                isFavorite: favorite,
                prioritySortOrder: 0,
                updatedAt: Date()
            )
        }
        let input = [
            account("A", favorite: false),
            account("B", favorite: true),
            account("C", favorite: false),
            account("D", favorite: true)
        ]

        let sections = CashflowAccountPickerSections.split(input)

        #expect(sections.favorites.map(\.title) == ["B", "D"])
        #expect(sections.others.map(\.title) == ["A", "C"])
    }

    @Test("Секции пикера не меняют порядок резолвера — дефолтный счёт формы остаётся прежним")
    func sectionsDoNotChangeDefaultAccount() throws {
        let ctx = try makeContext()
        let top = Card(name: "Приоритетный", cardNumber: "1", cardType: .debit, currency: "RUB", balance: 10)
        top.priorityRaw = CardPriority.high.rawValue
        let favorite = Card(name: "Избранный", cardNumber: "2", cardType: .debit, currency: "RUB", balance: 10)
        favorite.isFavorite = true
        favorite.priorityRaw = CardPriority.low.rawValue
        [top, favorite].forEach(ctx.insert)
        try ctx.save()

        let resolved = options(cards: [favorite, top], coreAccounts: [])
        let sections = CashflowAccountPickerSections.split(resolved)

        #expect(resolved.first?.title == "Приоритетный", "Сортировка по приоритету, а не по избранному")
        #expect(sections.favorites.first?.title == "Избранный", "Избранное — только визуальная секция")
    }

    // MARK: - 3. Детали строк (иконка + «доступно к трате»)

    @Test("Детали строк считаются для обоих миров, нерезолвленный счёт остаётся без баланса")
    func detailsCoverBothWorldsAndSkipUnknownAccounts() async throws {
        let ctx = try makeContext()
        let service = AccountsCoreService(modelContext: ctx)
        let card = Card(name: "Карта", cardNumber: "1", cardType: .debit, currency: "RUB", balance: 2_500)
        ctx.insert(card)
        let account = try service.createAccount(name: "Сбер счёт", kind: .debitCard, currency: "RUB", openingBalance: 7_000)
        try ctx.save()

        let phantom = CashflowSelectableAccount(
            kind: .coreAccount(accountID: UUID().uuidString),
            title: "Удалённый",
            currency: "RUB",
            isFavorite: false,
            prioritySortOrder: 0,
            updatedAt: Date()
        )
        let viewModel = makeViewModel(ctx)
        let resolved = options(cards: [card], coreAccounts: [account]) + [phantom]
        let details = await viewModel.accountPickerDetails(for: resolved)

        let cardRow = try #require(details["card:\(card.cardUniqueID)"])
        #expect(cardRow.availableAmount == Decimal(2_500))

        let coreRow = try #require(details["core:\(account.id.uuidString)"])
        #expect(coreRow.availableAmount == Decimal(7_000))
        #expect(coreRow.iconName == AccountIconSet.monogramIconName("Сбер счёт"))

        #expect(details[phantom.id] == nil, "Нет данных — прочерк в UI, а не «0 ₽»")
    }

    @Test("Кредитка показывает доступный лимит, а не сумму долга")
    func creditCardShowsAvailableLimit() throws {
        let ctx = try makeContext()
        let card = Card(name: "Кредитка", cardNumber: "1", cardType: .credit, currency: "RUB", balance: 30_000)
        card.creditLimit = 100_000
        ctx.insert(card)
        try ctx.save()

        let details = CashflowAccountPickerDetailsFactory.details(for: card)
        #expect(details.availableAmount == Decimal(30_000))
    }

    // MARK: - 4. Резолв валюты счёта-получателя перевода (риск 4 стресс-теста)

    @Test("Валюта счёта-получателя резолвится и для core-счёта")
    func destinationCurrencyResolvesCoreAccount() throws {
        let ctx = try makeContext()
        let service = AccountsCoreService(modelContext: ctx)
        let core = try service.createAccount(name: "USD счёт", kind: .bankAccount, currency: "USD", openingBalance: 100)
        let card = Card(name: "Карта", cardNumber: "1", cardType: .debit, currency: "EUR", balance: 100)
        ctx.insert(card)
        try ctx.save()

        let viewModel = makeViewModel(ctx)
        let persistence = viewModel.persistenceService

        #expect(persistence.destinationCurrency(for: card.cardUniqueID) == "EUR")
        #expect(
            persistence.destinationCurrency(for: core.id.uuidString) == "USD",
            "Раньше здесь был nil → проверка курса молча отключалась и сумма перевода портилась"
        )
        #expect(persistence.destinationCurrency(for: nil) == nil)
        #expect(persistence.destinationCurrency(for: UUID().uuidString) == nil)
    }
}
