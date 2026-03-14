//
//  CashflowTransactionsHistoryViewTests.swift
//  millioTests
//
//  Created by Assistant on 13.03.2026.
//

import Foundation
import SwiftData
import Testing
@testable import millio

struct CashflowTransactionsHistoryViewTests {
    private static let container: ModelContainer = {
        let schema = Schema([CashflowTransaction.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    @MainActor
    private func makeContext() -> ModelContext {
        Self.container.mainContext
    }

    @Test("Активная группа фильтров показывает выбранный тип и диапазон дат")
    func activeFiltersIncludeSelectedTypeAndDate() {
        let items = CashflowHistoryFilterPresentation.activeItems(
            selectedFilter: .income,
            dateFilterTitle: "10 марта - 13 марта",
            isDateFilterActive: true
        )

        #expect(items == [
            .type(.income),
            .date("10 марта - 13 марта")
        ])
    }

    @Test("Активная группа фильтров скрыта для фильтра Все без дат")
    func activeFiltersStayEmptyForDefaultState() {
        let items = CashflowHistoryFilterPresentation.activeItems(
            selectedFilter: .all,
            dateFilterTitle: "Период",
            isDateFilterActive: false
        )

        #expect(items.isEmpty)
    }

    @Test("История берет актуальную операцию после редактирования")
    @MainActor
    func historyResolvesUpdatedTransactionFromViewModelState() throws {
        let context = makeContext()
        try context.deleteAll(CashflowTransaction.self)
        try context.save()

        let original = CashflowTransaction(
            transactionType: .expense,
            amount: 100,
            currency: "RUB",
            transactionDate: Date()
        )
        context.insert(original)
        try context.save()

        let fetched = try #require(context.fetch(FetchDescriptor<CashflowTransaction>()).first)

        let resolved = cashflowHistoryResolvedTransaction(for: original, in: [fetched])

        #expect(resolved === fetched)
        #expect(resolved.persistentModelID == original.persistentModelID)
    }
}
