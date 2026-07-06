//
//  FinanceLegacyAccountPurgeTests.swift
//  millioTests
//
//  Покрывает физическое удаление легаси-счёта (Card/Credit/Investment): сам объект +
//  junction FinanceAccount + каскад связанных операций Cashflow, при сохранении чужих операций.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@MainActor
struct FinanceLegacyAccountPurgeTests {

    private static let schema = Schema([
        Card.self,
        Credit.self,
        Investment.self,
        AssetCatalogItem.self,
        AssetProviderMapping.self,
        FinanceGroup.self,
        FinanceAccount.self,
        CashflowTransaction.self,
    ])
    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        UserDefaults.standard.set("RUB", forKey: "primaryCurrencyCode")
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        let context = container.mainContext
        try context.save()
        return context
    }

    /// Вставляет легаси-счёт заданного типа + junction в группе и возвращает (accountID, junction).
    private func insertLegacyAccount(
        kind: FinanceAccountType,
        into context: ModelContext,
        group: FinanceGroup
    ) throws -> (accountID: String, junction: FinanceAccount) {
        let accountID: String
        switch kind {
        case .card:
            let card = Card(name: "Тест-карта", cardNumber: "0000", currency: "RUB", balance: 500)
            context.insert(card)
            accountID = card.cardUniqueID
        case .credit:
            let credit = Credit(
                name: "Тест-кредит",
                amount: 1000,
                interestRate: 10,
                monthlyPayment: 100,
                startDate: Date(),
                termMonths: 12,
                currency: "RUB"
            )
            context.insert(credit)
            accountID = credit.creditUniqueID
        case .investment:
            let investment = Investment(
                name: "Альфа вклад",
                investmentType: .positive,
                category: .other,
                amount: 2000,
                currency: "RUB",
                includeInTotal: true,
                priority: .normal,
                isFavorite: false
            )
            context.insert(investment)
            accountID = investment.investmentUniqueID
        }

        let junction = FinanceAccount(accountType: kind, accountID: accountID)
        junction.group = group
        context.insert(junction)
        try context.save()
        return (accountID, junction)
    }

    /// Операция, ссылающаяся на счёт «своим» полем связи по типу счёта.
    private func makeLinkedTransaction(kind: FinanceAccountType, accountID: String) -> CashflowTransaction {
        switch kind {
        case .card:
            return CashflowTransaction(transactionType: .expense, amount: 100, currency: "RUB", transactionDate: Date(), cardID: accountID)
        case .credit:
            return CashflowTransaction(transactionType: .expense, amount: 100, currency: "RUB", transactionDate: Date(), creditID: accountID)
        case .investment:
            return CashflowTransaction(transactionType: .expense, amount: 100, currency: "RUB", transactionDate: Date(), investmentID: accountID)
        }
    }

    @Test("Физическое удаление легаси-счёта сносит объект, junction и связанные операции",
          arguments: [FinanceAccountType.card, .credit, .investment])
    func purgeRemovesAccountJunctionAndTransactions(kind: FinanceAccountType) throws {
        let context = try makeContext()
        let group = FinanceGroup(name: "Основные", colorHex: "#00AAFF")
        context.insert(group)
        try context.save()

        let (accountID, junction) = try insertLegacyAccount(kind: kind, into: context, group: group)

        // Две связанные операции + одна чужая (должна выжить).
        let linked1 = makeLinkedTransaction(kind: kind, accountID: accountID)
        let linked2 = makeLinkedTransaction(kind: kind, accountID: accountID)
        let foreign = CashflowTransaction(transactionType: .income, amount: 999, currency: "RUB", transactionDate: Date(), cardID: "someone-else")
        context.insert(linked1)
        context.insert(linked2)
        context.insert(foreign)
        try context.save()

        let viewModel = FinanceViewModel(modelContext: context, skipInitialLoad: true)

        // Счётчик для алерта — до удаления.
        #expect(viewModel.legacyRelatedTransactionCount(for: junction) == 2)

        viewModel.handle(.physicallyDeleteLegacyAccount(junction))

        // Junction удалён.
        let junctions = try context.fetch(FetchDescriptor<FinanceAccount>())
        #expect(junctions.isEmpty)

        // Underlying-объект удалён.
        switch kind {
        case .card:
            #expect((try context.fetch(FetchDescriptor<Card>())).isEmpty)
        case .credit:
            #expect((try context.fetch(FetchDescriptor<Credit>())).isEmpty)
        case .investment:
            #expect((try context.fetch(FetchDescriptor<Investment>())).isEmpty)
        }

        // Связанные операции удалены, чужая — на месте.
        let remainingTx = try context.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(remainingTx.count == 1)
        #expect(remainingTx.first?.cardID == "someone-else")

        // Тотал/список счетов больше не содержат удалённый счёт.
        #expect(viewModel.legacyRelatedTransactionCount(for: junction) == 0)
    }

    @Test("Удаление счёта без операций проходит, счётчик = 0")
    func purgeWithNoTransactions() throws {
        let context = try makeContext()
        let group = FinanceGroup(name: "Основные", colorHex: "#00AAFF")
        context.insert(group)
        try context.save()

        let (_, junction) = try insertLegacyAccount(kind: .investment, into: context, group: group)
        let viewModel = FinanceViewModel(modelContext: context, skipInitialLoad: true)

        #expect(viewModel.legacyRelatedTransactionCount(for: junction) == 0)
        viewModel.handle(.physicallyDeleteLegacyAccount(junction))

        #expect((try context.fetch(FetchDescriptor<Investment>())).isEmpty)
        #expect((try context.fetch(FetchDescriptor<FinanceAccount>())).isEmpty)
    }
}
