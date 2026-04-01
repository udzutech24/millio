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
                purchaseUnitPrice: nil,
                purchaseCost: nil,
                totalAmount: 1_000
            ),
            after: CashflowAssetChangeSnapshot(
                quantity: 12,
                unitPrice: 120,
                purchaseUnitPrice: nil,
                purchaseCost: nil,
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
                purchaseUnitPrice: nil,
                purchaseCost: nil,
                totalAmount: 1_000
            ),
            after: CashflowAssetChangeSnapshot(
                quantity: 10,
                unitPrice: 120,
                purchaseUnitPrice: nil,
                purchaseCost: nil,
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

    @Test("История изменения актива локализуется для zh-Hans")
    func historyAssetChangeLinesUseSimplifiedChineseLabels() {
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
                purchaseUnitPrice: nil,
                purchaseCost: nil,
                totalAmount: 1_000
            ),
            after: CashflowAssetChangeSnapshot(
                quantity: 12,
                unitPrice: 120,
                purchaseUnitPrice: nil,
                purchaseCost: nil,
                totalAmount: 1_440
            )
        )

        let lines = cashflowHistoryAssetChangeLines(
            for: transaction,
            currencyCode: "USD",
            locale: Locale(identifier: "zh-Hans")
        )

        #expect(lines == [
            "数量: 10 -> 12",
            "价格: 100 USD -> 120 USD",
            "价值: 1 000 USD -> 1 440 USD"
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

    @Test("Фильтр истории по категории оставляет только операции этой категории")
    @MainActor
    func historyFiltersTransactionsByCategory() throws {
        let context = makeContext()
        try context.deleteAll(CashflowTransaction.self)
        try context.save()

        context.insert(CashflowTransaction(
            transactionType: .expense,
            amount: 100,
            currency: "RUB",
            transactionDate: Date(),
            expenseCategoryRaw: ExpenseCategory.groceries.rawValue
        ))
        context.insert(CashflowTransaction(
            transactionType: .expense,
            amount: 200,
            currency: "RUB",
            transactionDate: Date(),
            expenseCategoryRaw: ExpenseCategory.cafe.rawValue
        ))
        try context.save()

        let viewModel = CashflowViewModel(modelContext: context)
        let filtered = viewModel.historyTransactions(
            matching: CashflowHistoryQuery(
                typeFilter: .expense,
                categoryRawValue: ExpenseCategory.groceries.rawValue
            )
        )

        #expect(filtered.count == 1)
        #expect(filtered.first?.expenseCategoryRaw == ExpenseCategory.groceries.rawValue)
    }

    @Test("История покупки актива показывает карту списания из связанной операции")
    func historyResolvesLinkedSettlementCardForAssetTrade() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        LanguageManager.shared.setLanguage(.russian)
        defer { LanguageManager.shared.setLanguage(previousLanguage) }
        let localizedBuyNote = AppLocalization.string(
            "finances.transaction.note.investment_buy",
            locale: AppLocalization.currentAppLocale
        )

        let investmentTrade = CashflowTransaction(
            transactionType: .balanceAdjustment,
            amount: 676.33,
            currency: "USD",
            transactionDate: Date(),
            investmentID: "asset-1",
            note: localizedBuyNote,
            operationGroupID: "trade-1"
        )
        investmentTrade.applyAssetChangeSnapshot(
            before: CashflowAssetChangeSnapshot(
                quantity: 18,
                unitPrice: 676.33,
                purchaseUnitPrice: nil,
                purchaseCost: nil,
                totalAmount: 12_173.94
            ),
            after: CashflowAssetChangeSnapshot(
                quantity: 19,
                unitPrice: 676.33,
                purchaseUnitPrice: nil,
                purchaseCost: nil,
                totalAmount: 12_850.27
            )
        )

        let settlement = CashflowTransaction(
            transactionType: .expense,
            amount: 676.33,
            currency: "USD",
            transactionDate: Date(),
            cardID: "card-main",
            investmentID: "asset-1",
            expenseCategory: .other,
            note: localizedBuyNote,
            operationGroupID: "trade-1",
            affectsCashflowTotals: false
        )

        let related = cashflowHistoryRelatedTransactions(for: investmentTrade, in: [investmentTrade, settlement])
        let context = cashflowHistorySettlementAccountContext(
            for: investmentTrade,
            in: [investmentTrade, settlement]
        )
        let description = cashflowHistoryDescription(
            for: investmentTrade,
            relatedTransactions: [investmentTrade, settlement],
            cardNameResolver: { cardID in
                cardID == "card-main" ? "Black Card" : nil
            },
            investmentNameResolver: { investmentID in
                investmentID == "asset-1" ? "Apple" : nil
            },
            incomeCategoryResolver: { _ in "" },
            expenseCategoryResolver: { _ in "" },
            locale: Locale(identifier: "ru_RU")
        )

        #expect(related.count == 1)
        #expect(context == CashflowHistorySettlementAccountContext(cardID: "card-main", direction: .debit))
        #expect(cashflowHistoryPrimaryTitle(for: investmentTrade) == "Покупка актива")
        #expect(description?.contains("Счет списания: Black Card") == true)
    }

    @Test("История покупки актива локализует legacy note key в title")
    func historyLocalizesInvestmentTradeTitleFromRawLocalizationKey() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        LanguageManager.shared.setLanguage(.russian)
        defer { LanguageManager.shared.setLanguage(previousLanguage) }

        let investmentTrade = CashflowTransaction(
            transactionType: .balanceAdjustment,
            amount: 100,
            currency: "USD",
            transactionDate: Date(),
            investmentID: "asset-1",
            note: "finances.transaction.note.investment_buy"
        )

        #expect(
            cashflowHistoryPrimaryTitle(
                for: investmentTrade,
                locale: Locale(identifier: "ru_RU")
            ) == "Покупка актива"
        )
    }

    @Test("Фильтр по карте находит покупку актива через settlement leg")
    @MainActor
    func historyFiltersInvestmentTradeByLinkedSettlementCard() throws {
        let context = makeContext()
        try context.deleteAll(CashflowTransaction.self)
        try context.deleteAll(Card.self)
        try context.save()
        let localizedBuyNote = AppLocalization.string(
            "finances.transaction.note.investment_buy",
            locale: AppLocalization.currentAppLocale
        )

        let card = Card(name: "Broker Card", cardNumber: "3333")
        context.insert(card)

        let investmentTrade = CashflowTransaction(
            transactionType: .balanceAdjustment,
            amount: 500,
            currency: "USD",
            transactionDate: Date(),
            investmentID: "asset-1",
            note: localizedBuyNote,
            operationGroupID: "trade-2"
        )
        investmentTrade.applyAssetChangeSnapshot(
            before: CashflowAssetChangeSnapshot(
                quantity: 1,
                unitPrice: 100,
                purchaseUnitPrice: nil,
                purchaseCost: nil,
                totalAmount: 100
            ),
            after: CashflowAssetChangeSnapshot(
                quantity: 2,
                unitPrice: 300,
                purchaseUnitPrice: nil,
                purchaseCost: nil,
                totalAmount: 600
            )
        )

        let settlement = CashflowTransaction(
            transactionType: .expense,
            amount: 500,
            currency: "USD",
            transactionDate: Date(),
            cardID: card.cardUniqueID,
            investmentID: "asset-1",
            expenseCategory: .other,
            note: localizedBuyNote,
            operationGroupID: "trade-2",
            affectsCashflowTotals: false
        )

        context.insert(investmentTrade)
        context.insert(settlement)
        try context.save()

        let viewModel = CashflowViewModel(modelContext: context)
        let filtered = viewModel.historyTransactions(matching: CashflowHistoryQuery(cardID: card.cardUniqueID))

        #expect(filtered.count == 1)
        #expect(filtered.first?.operationGroupID == "trade-2")
        #expect(filtered.first?.transactionType == .balanceAdjustment)
    }
}
