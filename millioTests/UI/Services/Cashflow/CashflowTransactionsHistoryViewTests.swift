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
        let schema = Schema([CashflowTransaction.self, Card.self, HistoricalRate.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    @MainActor
    private func makeContext() -> ModelContext {
        Self.container.mainContext
    }

    @Test("Summary график показывается только для расходов и доходов")
    func summaryPresentationAllowsOnlyExpenseAndIncomeModes() {
        #expect(CashflowHistorySummaryPresentation.shouldShow(
            selectedFilter: .expense,
            isSearchActive: false,
            searchText: "",
            entryCount: 3,
            totalAmount: 10_000
        ))
        #expect(CashflowHistorySummaryPresentation.shouldShow(
            selectedFilter: .income,
            isSearchActive: false,
            searchText: "",
            entryCount: 2,
            totalAmount: 8_000
        ))
        #expect(!CashflowHistorySummaryPresentation.shouldShow(
            selectedFilter: .all,
            isSearchActive: false,
            searchText: "",
            entryCount: 4,
            totalAmount: 12_000
        ))
        #expect(!CashflowHistorySummaryPresentation.shouldShow(
            selectedFilter: .transfer,
            isSearchActive: false,
            searchText: "",
            entryCount: 4,
            totalAmount: 12_000
        ))
    }

    @Test("Summary график скрывается для поиска и неполных данных")
    func summaryPresentationHidesForSearchAndWeakBreakdown() {
        #expect(!CashflowHistorySummaryPresentation.shouldShow(
            selectedFilter: .expense,
            isSearchActive: true,
            searchText: "кафе",
            entryCount: 3,
            totalAmount: 10_000
        ))
        #expect(!CashflowHistorySummaryPresentation.shouldShow(
            selectedFilter: .expense,
            isSearchActive: false,
            searchText: "",
            entryCount: 1,
            totalAmount: 10_000
        ))
        #expect(!CashflowHistorySummaryPresentation.shouldShow(
            selectedFilter: .expense,
            isSearchActive: false,
            searchText: "",
            entryCount: 2,
            totalAmount: 0
        ))
    }

    @Test("Summary builder агрегирует категории и сортирует по сумме")
    func summaryBuilderAggregatesAndSortsCategories() {
        let entries = CashflowHistorySummaryBuilder.build(
            totalsByRawValue: [
                "salary": 150_000,
                "gift": 12_000,
                "bonus": 38_000
            ],
            mode: .income,
            resolver: { rawValue in
                CashflowHistorySummaryResolvedCategory(
                    rawValue: rawValue,
                    title: rawValue.capitalized,
                    icon: "•"
                )
            }
        )

        #expect(entries.map(\.rawValue) == ["salary", "bonus", "gift"])
        #expect(abs(entries[0].share - 0.75) < 0.0001)
    }

    @Test("Summary builder игнорирует NaN и infinity")
    func summaryBuilderSkipsInvalidAmounts() {
        let entries = CashflowHistorySummaryBuilder.build(
            totalsByRawValue: [
                "valid": 1_000,
                "nan": .nan,
                "infinity": .infinity
            ],
            mode: .expense,
            resolver: { rawValue in
                CashflowHistorySummaryResolvedCategory(
                    rawValue: rawValue,
                    title: rawValue,
                    icon: "•"
                )
            }
        )

        #expect(entries.count == 1)
        #expect(entries.first?.rawValue == "valid")
        #expect(entries.first?.share == 1)
    }

    @Test("History helpers санитизируют невалидные числа для UI")
    func historyHelpersSanitizeInvalidNumbers() {
        #expect(cashflowHistoryPercentText(share: .nan) == "0%")
        #expect(cashflowHistoryPercentText(share: .infinity) == "0%")
        #expect(cashflowHistoryPercentText(share: 0.375) == "38%")

        #expect(cashflowHistoryTimeToken(for: nil) == "0")
        #expect(cashflowHistoryTimeToken(for: Date(timeIntervalSince1970: 1_710_000_000)) == "1710000000")
        #expect(cashflowHistoryFormattedNumberText(15.125, maxFractionDigits: 4) == "15,125")
    }

    @Test("История изменения актива показывает было и стало для акций")
    func historyBuildsAssetChangeSummary() {
        let transaction = CashflowTransaction(
            transactionType: .balanceAdjustment,
            amount: 440,
            currency: "USD",
            transactionDate: Date()
        )
        transaction.applyAssetChangeSnapshot(
            before: CashflowAssetChangeSnapshot(
                quantity: 10,
                unitPrice: 100,
                totalAmount: 1_000
            ),
            after: CashflowAssetChangeSnapshot(
                quantity: 12,
                unitPrice: 120,
                totalAmount: 1_440
            )
        )

        let lines = cashflowHistoryAssetChangeLines(
            for: transaction,
            currencyCode: "USD",
            locale: Locale(identifier: "ru_RU")
        )
        let summary = cashflowHistoryAssetChangeSummary(
            for: transaction,
            currencyCode: "USD",
            locale: Locale(identifier: "ru_RU")
        )

        #expect(lines == [
            "Кол-во: 10 -> 12",
            "Цена: 100 USD -> 120 USD",
            "Стоимость: 1 000 USD -> 1 440 USD"
        ])
        #expect(summary == "Кол-во: 10 -> 12. Цена: 100 USD -> 120 USD. Стоимость: 1 000 USD -> 1 440 USD")
    }

    @Test("История изменения актива не показывает поля без реального изменения")
    func historySkipsUnchangedAssetFields() {
        let transaction = CashflowTransaction(
            transactionType: .balanceAdjustment,
            amount: 0,
            currency: "USD",
            transactionDate: Date()
        )
        transaction.applyAssetChangeSnapshot(
            before: CashflowAssetChangeSnapshot(
                quantity: 10,
                unitPrice: 100,
                totalAmount: 1_000
            ),
            after: CashflowAssetChangeSnapshot(
                quantity: 10,
                unitPrice: 120,
                totalAmount: 1_200
            )
        )

        let lines = cashflowHistoryAssetChangeLines(
            for: transaction,
            currencyCode: "USD",
            locale: Locale(identifier: "en_US")
        )

        #expect(lines == [
            "Price: 100 USD -> 120 USD",
            "Value: 1 000 USD -> 1 200 USD"
        ])
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

    @Test("Фильтр по карте оставляет только операции выбранной карты")
    @MainActor
    func historyFiltersTransactionsByCard() throws {
        let context = makeContext()
        try context.deleteAll(CashflowTransaction.self)
        try context.deleteAll(Card.self)
        try context.save()

        let firstCard = Card(name: "Основная", cardNumber: "1111")
        let secondCard = Card(name: "Резерв", cardNumber: "2222")
        context.insert(firstCard)
        context.insert(secondCard)
        context.insert(CashflowTransaction(
            transactionType: .expense,
            amount: 100,
            currency: "RUB",
            transactionDate: Date(),
            cardID: firstCard.cardUniqueID,
            expenseCategoryRaw: ExpenseCategory.groceries.rawValue
        ))
        context.insert(CashflowTransaction(
            transactionType: .expense,
            amount: 200,
            currency: "RUB",
            transactionDate: Date(),
            cardID: secondCard.cardUniqueID,
            expenseCategoryRaw: ExpenseCategory.cafe.rawValue
        ))
        try context.save()

        let viewModel = CashflowViewModel(modelContext: context)
        let filtered = viewModel.historyTransactions(matching: CashflowHistoryQuery(cardID: firstCard.cardUniqueID))

        #expect(filtered.count == 1)
        #expect(filtered.first?.cardID == firstCard.cardUniqueID)
    }
}
