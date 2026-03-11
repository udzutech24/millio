//
//  CashflowBulkExpenseImportTests.swift
//  millioTests
//
//  Created by Codex on 11.03.2026.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct CashflowBulkExpenseImportTests {
    private static let schema = Schema([
        Card.self,
        CashflowTransaction.self,
        CashflowCustomCategory.self,
        CashflowSystemCategoryOverride.self
    ])

    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Self.schema, configurations: [config])
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    @Test("Парсер расходов понимает inline и split форматы и игнорирует переводы")
    func parserSupportsExpenseLayouts() {
        let rows = CashflowBulkExpenseImportParser.parseRecognizedLines([
            "Пятерочка 1 240 ₽",
            "Яндекс Такси",
            "870 ₽",
            "Перевод себе",
            "5 000 ₽",
            "Coffee Point 340"
        ])

        #expect(rows.count == 3)
        #expect(rows.contains { $0.title == "Пятерочка" && abs($0.amount - 1240) < 0.001 })
        #expect(rows.contains { $0.title == "Яндекс Такси" && abs($0.amount - 870) < 0.001 })
        #expect(rows.contains { $0.title == "Coffee Point" && abs($0.amount - 340) < 0.001 })
    }

    @Test("Резолвер маппит очевидные траты в системные категории")
    func resolverMapsKeywordsToCategories() {
        let resolver = CashflowBulkExpenseImportCategoryResolver()
        let options = ExpenseCategory.allCases.map {
            CashflowCategoryOption(
                rawValue: $0.rawValue,
                displayName: $0.displayName,
                icon: $0.icon,
                isCustom: false
            )
        }

        let groceries = resolver.resolve(title: "ВкусВилл у дома", availableOptions: options)
        let transport = resolver.resolve(title: "Yandex Go taxi", availableOptions: options)

        #expect(groceries.option.rawValue == ExpenseCategory.groceries.rawValue)
        #expect(groceries.confidence >= .medium)
        #expect(transport.option.rawValue == ExpenseCategory.transport.rawValue)
        #expect(transport.confidence >= .medium)
    }

    @Test("Пакетный импорт расходов сохраняет операции и уменьшает баланс карты")
    func bulkPersistUpdatesCardBalance() async throws {
        let context = try makeContext()
        let card = Card(name: "Main", cardNumber: "1234", bank: .tinkoff, currency: "RUB", balance: 10_000)
        context.insert(card)
        try context.save()

        let viewModel = CashflowViewModel(
            modelContext: context,
            now: { Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 12)) ?? Date() }
        )

        let saved = try await viewModel.persistBulkExpenseImport(
            CashflowBulkExpensePersistRequest(
                cardID: card.cardUniqueID,
                month: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? Date(),
                shouldAffectCardBalance: true,
                entries: [
                    CashflowBulkExpensePersistEntry(
                        amount: 1_200,
                        expenseCategoryRaw: ExpenseCategory.groceries.rawValue,
                        note: "Пятерочка",
                        sourceOrderIndex: 0
                    ),
                    CashflowBulkExpensePersistEntry(
                        amount: 800,
                        expenseCategoryRaw: ExpenseCategory.transport.rawValue,
                        note: "Такси",
                        sourceOrderIndex: 1
                    )
                ]
            )
        )

        let transactions = try context.fetch(FetchDescriptor<CashflowTransaction>())

        #expect(saved == 2)
        #expect(transactions.count == 2)
        #expect(abs(card.balance - 8_000) < 0.001)
        #expect(transactions.allSatisfy { $0.cardID == card.cardUniqueID })
        #expect(transactions.allSatisfy { $0.currency == "RUB" })
    }

    @Test("Пакетный импорт может не менять текущий остаток карты")
    func bulkPersistCanSkipBalanceChange() async throws {
        let context = try makeContext()
        let card = Card(name: "History only", cardNumber: "4321", bank: .alfa, currency: "RUB", balance: 7_500)
        context.insert(card)
        try context.save()

        let viewModel = CashflowViewModel(modelContext: context)

        _ = try await viewModel.persistBulkExpenseImport(
            CashflowBulkExpensePersistRequest(
                cardID: card.cardUniqueID,
                month: Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? Date(),
                shouldAffectCardBalance: false,
                entries: [
                    CashflowBulkExpensePersistEntry(
                        amount: 2_000,
                        expenseCategoryRaw: ExpenseCategory.bills.rawValue,
                        note: "Интернет",
                        sourceOrderIndex: 0
                    )
                ]
            )
        )

        #expect(abs(card.balance - 7_500) < 0.001)
        let transactions = try context.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(transactions.count == 1)
        #expect(transactions.first?.note == "Интернет")
    }

    @Test("Даты пакетного импорта остаются внутри выбранного месяца")
    func bulkDatesStayInsideSelectedMonth() {
        let calendar = Calendar(identifier: .gregorian)
        let month = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? Date()
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 11, hour: 12)) ?? Date()

        let dates = CashflowViewModel.bulkExpenseTransactionDates(
            for: month,
            count: 3,
            referenceDate: referenceDate,
            calendar: calendar
        )

        #expect(dates.count == 3)
        #expect(dates.allSatisfy { calendar.isDate($0, equalTo: month, toGranularity: .month) })
        #expect(dates == dates.sorted())
    }
}
