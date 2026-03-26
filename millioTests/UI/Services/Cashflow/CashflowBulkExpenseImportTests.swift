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

    private var expenseOptions: [CashflowCategoryOption] {
        ExpenseCategory.allCases.map {
            CashflowCategoryOption(
                rawValue: $0.rawValue,
                displayName: $0.displayName,
                icon: $0.icon,
                isCustom: false
            )
        }
    }

    @Test("Парсер расходов понимает inline и split форматы и оставляет переводы для отдельной категории")
    func parserSupportsExpenseLayouts() {
        let rows = CashflowBulkExpenseImportParser.parseRecognizedLines([
            "Пятерочка 1 240 ₽",
            "Яндекс Такси",
            "870 ₽",
            "Перевод себе",
            "5 000 ₽",
            "Coffee Point 340"
        ])

        #expect(rows.count == 4)
        #expect(rows.contains { $0.title == "Пятерочка" && abs($0.amount - 1240) < 0.001 })
        #expect(rows.contains { $0.title == "Яндекс Такси" && abs($0.amount - 870) < 0.001 })
        #expect(rows.contains { $0.title == "Перевод себе" && abs($0.amount - 5000) < 0.001 })
        #expect(rows.contains { $0.title == "Coffee Point" && abs($0.amount - 340) < 0.001 })
    }

    @Test("Резолвер маппит очевидные траты в системные категории")
    func resolverMapsKeywordsToCategories() {
        let resolver = CashflowBulkExpenseImportCategoryResolver()
        let options = expenseOptions

        let groceries = resolver.resolve(title: "ВкусВилл у дома", availableOptions: options)
        let transport = resolver.resolve(title: "Yandex Go taxi", availableOptions: options)
        let fuel = resolver.resolve(title: "Газпромнефть АЗС", availableOptions: options)
        let shopping = resolver.resolve(title: "Ozon order", availableOptions: options)
        let transfer = resolver.resolve(title: "Перевод себе по СБП", availableOptions: options)
        let unknown = resolver.resolve(title: "Strange merchant xyz", availableOptions: options)

        #expect(groceries.option.rawValue == ExpenseCategory.groceries.rawValue)
        #expect(groceries.confidence >= .medium)
        #expect(transport.option.rawValue == ExpenseCategory.taxi.rawValue)
        #expect(transport.confidence >= .medium)
        #expect(fuel.option.rawValue == ExpenseCategory.fuel.rawValue)
        #expect(fuel.confidence >= .medium)
        #expect(shopping.option.rawValue == ExpenseCategory.shopping.rawValue)
        #expect(shopping.confidence >= .medium)
        #expect(transfer.option.rawValue == ExpenseCategory.transfers.rawValue)
        #expect(transfer.confidence >= .medium)
        #expect(unknown.option.rawValue == ExpenseCategory.other.rawValue)
        #expect(unknown.confidence == .low)
        #expect(unknown.requiresManualReview)
        #expect(!groceries.requiresManualReview)
    }

    @Test("Screenshot mode respects screenshot import entitlement")
    func screenshotModeRespectsEntitlement() {
        #expect(CashflowBulkExpenseImportMode.manual.isUnlocked(canImportScreenshots: false))
        #expect(!CashflowBulkExpenseImportMode.screenshot.isUnlocked(canImportScreenshots: false))
        #expect(CashflowBulkExpenseImportMode.screenshot.isUnlocked(canImportScreenshots: true))
    }

    @Test("Резолвер отдаёт top suggestions и поднимает запомненную категорию наверх")
    func resolverRanksSuggestionsWithLearnedCategoryFirst() {
        let resolver = CashflowBulkExpenseImportCategoryResolver()
        let options = expenseOptions

        let suggested = resolver.suggestedOptions(
            title: "Coffee Point",
            availableOptions: options,
            preferredRawValue: ExpenseCategory.dining.rawValue
        )

        #expect(!suggested.isEmpty)
        #expect(suggested.first?.rawValue == ExpenseCategory.dining.rawValue)
        #expect(suggested.count <= 3)
    }

    @Test("OCR сначала строит review-черновик для всех строк, а не мержит их молча")
    func screenshotImportBuildsPreviewRowsBeforeApplying() {
        let rows = [
            CashflowBulkExpenseParsedRow(
                rawLine: "ВкусВилл 1 240",
                title: "ВкусВилл",
                amount: 1_240,
                sourceOrderIndex: 0
            ),
            CashflowBulkExpenseParsedRow(
                rawLine: "Unknown merchant 340",
                title: "Unknown merchant",
                amount: 340,
                sourceOrderIndex: 1
            )
        ]

        let preview = CashflowBulkExpenseScreenshotReviewPolicy.makePreviewRows(
            parsedRows: rows,
            availableOptions: expenseOptions,
            preferredRawValueForTitle: { _ in nil }
        )

        #expect(preview.count == 2)
        #expect(preview[0].selectedCategoryRaw == ExpenseCategory.groceries.rawValue)
        #expect(preview[0].requiresAttention == false)
        #expect(preview[1].selectedCategoryRaw == ExpenseCategory.other.rawValue)
        #expect(preview[1].requiresAttention)
    }

    @Test("В категории переносятся только проверенные строки, сомнительные остаются в review")
    func screenshotReviewAppliesOnlyReviewedRows() {
        let categoryDrafts = [
            CashflowBulkExpenseCategoryDraft(
                category: expenseOptions.first(where: { $0.rawValue == ExpenseCategory.groceries.rawValue })!,
                sourceOrderIndex: 0
            ),
            CashflowBulkExpenseCategoryDraft(
                category: expenseOptions.first(where: { $0.rawValue == ExpenseCategory.other.rawValue })!,
                sourceOrderIndex: 1
            )
        ]
        let rows = [
            CashflowBulkExpenseRowDraft(
                rawLine: "ВкусВилл",
                titleText: "ВкусВилл",
                amountText: "1 240",
                selectedCategoryRaw: ExpenseCategory.groceries.rawValue,
                suggestedCategoryRaws: [ExpenseCategory.groceries.rawValue],
                sourceOrderIndex: 0,
                confidence: .high,
                usesSuggestedCategory: true
            ),
            CashflowBulkExpenseRowDraft(
                rawLine: "Unknown merchant",
                titleText: "Unknown merchant",
                amountText: "340",
                selectedCategoryRaw: ExpenseCategory.other.rawValue,
                suggestedCategoryRaws: [],
                sourceOrderIndex: 1,
                confidence: .low,
                usesSuggestedCategory: true
            )
        ]

        let result = CashflowBulkExpenseScreenshotReviewPolicy.applyPreviewRows(
            rows,
            to: categoryDrafts
        )

        #expect(result.appliedRows.count == 1)
        #expect(result.remainingRows.count == 1)
        #expect(result.importedCategoryRaws == [ExpenseCategory.groceries.rawValue])
        #expect(result.categoryDrafts[0].amountText == "1 240")
        #expect(result.categoryDrafts[1].amountText.isEmpty)
    }

    @Test("Поиск категорий учитывает короткое имя и синонимы каталога")
    func categoryOptionsMatchAliases() throws {
        let context = try makeContext()
        let viewModel = CashflowViewModel(modelContext: context)

        let byAlias = viewModel.categoryOptions(for: .expense, matching: "заправки")
        let byShortName = viewModel.categoryOptions(for: .expense, matching: "азс")
        let byMerchant = viewModel.categoryOptions(for: .expense, matching: "wildberries")
        let byTransfer = viewModel.categoryOptions(for: .expense, matching: "сбп")

        #expect(byAlias.contains { $0.rawValue == ExpenseCategory.fuel.rawValue })
        #expect(byShortName.contains { $0.rawValue == ExpenseCategory.fuel.rawValue })
        #expect(byMerchant.contains { $0.rawValue == ExpenseCategory.shopping.rawValue })
        #expect(byTransfer.contains { $0.rawValue == ExpenseCategory.transfers.rawValue })
    }

    @Test("Масс-импорт понимает синонимы и частые OCR-опечатки для еды вне дома")
    func categoryOptionsMatchDiningTyposAndSynonyms() throws {
        let context = try makeContext()
        let viewModel = CashflowViewModel(modelContext: context)

        let byRestaurantTypo = viewModel.categoryOptions(for: .expense, matching: "рестороны")
        let byCafe = viewModel.categoryOptions(for: .expense, matching: "кафе")
        let byCoffee = viewModel.categoryOptions(for: .expense, matching: "coffee shop")

        #expect(byRestaurantTypo.contains { $0.rawValue == ExpenseCategory.dining.rawValue })
        #expect(byCafe.contains { $0.rawValue == ExpenseCategory.dining.rawValue })
        #expect(byCoffee.contains { $0.rawValue == ExpenseCategory.dining.rawValue })
    }

    @Test("После OCR новые категории всплывают наверх по убыванию суммы")
    func importedCategoriesMoveToTopByAmount() {
        let drafts = [
            CashflowBulkExpenseCategoryDraft(
                category: CashflowCategoryOption(
                    rawValue: ExpenseCategory.groceries.rawValue,
                    displayName: ExpenseCategory.groceries.displayName,
                    icon: ExpenseCategory.groceries.icon,
                    isCustom: false
                ),
                amountText: "",
                sourceOrderIndex: 0
            ),
            CashflowBulkExpenseCategoryDraft(
                category: CashflowCategoryOption(
                    rawValue: ExpenseCategory.transfers.rawValue,
                    displayName: ExpenseCategory.transfers.displayName,
                    icon: ExpenseCategory.transfers.icon,
                    isCustom: false
                ),
                amountText: "4 000",
                sourceOrderIndex: 1
            ),
            CashflowBulkExpenseCategoryDraft(
                category: CashflowCategoryOption(
                    rawValue: ExpenseCategory.fuel.rawValue,
                    displayName: ExpenseCategory.fuel.displayName,
                    icon: ExpenseCategory.fuel.icon,
                    isCustom: false
                ),
                amountText: "1 500",
                sourceOrderIndex: 2
            ),
            CashflowBulkExpenseCategoryDraft(
                category: CashflowCategoryOption(
                    rawValue: ExpenseCategory.other.rawValue,
                    displayName: ExpenseCategory.other.displayName,
                    icon: ExpenseCategory.other.icon,
                    isCustom: false
                ),
                amountText: "300",
                sourceOrderIndex: 3
            )
        ]

        let orderedIndices = CashflowBulkExpenseCategorySortPolicy.orderedDraftIndices(
            drafts: drafts,
            searchText: "",
            importedCategoryRaws: [ExpenseCategory.fuel.rawValue, ExpenseCategory.transfers.rawValue]
        )

        #expect(orderedIndices.map { drafts[$0].category.rawValue } == [
            ExpenseCategory.transfers.rawValue,
            ExpenseCategory.fuel.rawValue,
            ExpenseCategory.other.rawValue,
            ExpenseCategory.groceries.rawValue
        ])
    }

    @Test("Категория переводов помечается как подозрительная для bulk import")
    func transferCategoryIsFlagged() {
        #expect(CashflowBulkExpenseCategorySortPolicy.isTransferCategory(ExpenseCategory.transfers.rawValue))
        #expect(!CashflowBulkExpenseCategorySortPolicy.isTransferCategory(ExpenseCategory.groceries.rawValue))
    }

    @Test("Скрытая системная категория возвращается в каталог после массового импорта")
    func bulkPersistRevealsHiddenSystemCategory() async throws {
        let context = try makeContext()
        let card = Card(name: "Main", cardNumber: "1234", bank: .tinkoff, currency: "RUB", balance: 10_000)
        let hiddenFuel = CashflowSystemCategoryOverride(
            kind: .expense,
            categoryRaw: ExpenseCategory.fuel.rawValue,
            name: ExpenseCategory.fuel.displayName,
            icon: ExpenseCategory.fuel.icon,
            isHidden: true
        )
        context.insert(card)
        context.insert(hiddenFuel)
        try context.save()

        let viewModel = CashflowViewModel(modelContext: context)

        _ = try await viewModel.persistBulkExpenseImport(
            CashflowBulkExpensePersistRequest(
                cardID: card.cardUniqueID,
                month: Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? Date(),
                shouldAffectCardBalance: false,
                entries: [
                    CashflowBulkExpensePersistEntry(
                        amount: 1_500,
                        expenseCategoryRaw: ExpenseCategory.fuel.rawValue,
                        note: "АЗС",
                        sourceOrderIndex: 0
                    )
                ]
            )
        )

        let visibleOptions = viewModel.categoryOptions(for: .expense)

        #expect(hiddenFuel.isHidden == false)
        #expect(visibleOptions.contains { $0.rawValue == ExpenseCategory.fuel.rawValue })
        #expect(viewModel.expenseCategoryDisplayName(for: ExpenseCategory.fuel.rawValue) == ExpenseCategory.fuel.displayName)
    }

    @Test("Сумма в массовом импорте понимает группировку и форматируется с разделителями")
    func groupedAmountInputIsParsedAndDisplayed() {
        #expect(abs((CashflowBulkExpenseRowDraft.parseAmount("22 222") ?? 0) - 22_222) < 0.001)
        #expect(AmountInputFormatter.display("22222", maxFractionDigits: 0) == "22 222")
    }

    @Test("Breakdown категории отделяет ручную базу от bulk-дельты")
    func categoryBreakdownSeparatesBaselineAndImportedPart() {
        let fromOnlyManual = CashflowBulkExpenseCategoryBreakdown.make(
            displayedAmount: 1_500,
            baselineAmount: 1_500
        )
        let mixed = CashflowBulkExpenseCategoryBreakdown.make(
            displayedAmount: 1_900,
            baselineAmount: 1_500
        )
        let editedDown = CashflowBulkExpenseCategoryBreakdown.make(
            displayedAmount: 1_200,
            baselineAmount: 1_500
        )

        #expect(abs(fromOnlyManual.baselineAmount - 1_500) < 0.001)
        #expect(abs(fromOnlyManual.importedAmount) < 0.001)
        #expect(abs(mixed.baselineAmount - 1_500) < 0.001)
        #expect(abs(mixed.importedAmount - 400) < 0.001)
        #expect(abs(editedDown.baselineAmount - 1_500) < 0.001)
        #expect(abs(editedDown.importedAmount) < 0.001)
    }

    @Test("После ручного выбора категории строка OCR больше не требует разбора")
    func rowDraftStopsRequiringAttentionAfterManualCategoryChoice() {
        var draft = CashflowBulkExpenseRowDraft(
            rawLine: "Unknown coffee shop",
            titleText: "Unknown coffee shop",
            amountText: "450",
            selectedCategoryRaw: ExpenseCategory.other.rawValue,
            sourceOrderIndex: 0,
            confidence: .low,
            usesSuggestedCategory: true
        )

        #expect(draft.requiresAttention)

        draft.selectedCategoryRaw = ExpenseCategory.cafe.rawValue
        draft.usesSuggestedCategory = false

        #expect(!draft.requiresAttention)
    }

    @Test("Запомненная категория мерчанта поднимается из prefs")
    func merchantCategoryPrefsRememberSelection() {
        let suiteName = "CashflowBulkExpenseImportTests.merchantPrefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = CashflowBulkExpenseMerchantCategoryPrefs(defaults: defaults)
        prefs.remember(categoryRaw: ExpenseCategory.cafe.rawValue, for: "Coffee Point")

        #expect(prefs.categoryRaw(for: "coffee point") == ExpenseCategory.cafe.rawValue)
        #expect(prefs.categoryRaw(for: "Coffee-Point!") == ExpenseCategory.cafe.rawValue)
    }

    @Test("Политика выбора фиксирует валюту и карту в одном валютном контексте")
    func selectionPolicyKeepsCurrencyAndCardAligned() {
        let rubFavorite = Card(
            name: "RUB main",
            cardNumber: "1000",
            bank: .tinkoff,
            currency: "RUB",
            balance: 1_000,
            isFavorite: true
        )
        let usdCard = Card(
            name: "USD",
            cardNumber: "2000",
            bank: .alfa,
            currency: "USD",
            balance: 200
        )

        let normalized = CashflowBulkExpenseImportSelectionPolicy.normalizeSelection(
            cards: [rubFavorite, usdCard],
            selectedCurrency: "EUR",
            selectedCardID: usdCard.cardUniqueID,
            preferredCurrency: "RUB"
        )

        #expect(normalized.currency == "RUB")
        #expect(normalized.cardID == rubFavorite.cardUniqueID)
    }

    @Test("Политика выбора сохраняет карту если она уже в выбранной валюте")
    func selectionPolicyPreservesMatchingCard() {
        let rubCard = Card(
            name: "RUB",
            cardNumber: "1111",
            bank: .tinkoff,
            currency: "RUB",
            balance: 700
        )
        let usdFavorite = Card(
            name: "USD fav",
            cardNumber: "2222",
            bank: .alfa,
            currency: "USD",
            balance: 300,
            isFavorite: true
        )

        let normalized = CashflowBulkExpenseImportSelectionPolicy.normalizeSelection(
            cards: [rubCard, usdFavorite],
            selectedCurrency: "USD",
            selectedCardID: usdFavorite.cardUniqueID,
            preferredCurrency: "RUB"
        )

        #expect(normalized.currency == "USD")
        #expect(normalized.cardID == usdFavorite.cardUniqueID)
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

    @Test("Повторное сохранение месячного импорта обновляет категории без дублей и корректирует баланс по дельте")
    func bulkPersistUpsertsMonthlyCategorySet() async throws {
        let context = try makeContext()
        let card = Card(name: "Main", cardNumber: "1234", bank: .tinkoff, currency: "RUB", balance: 10_000)
        context.insert(card)
        try context.save()

        let calendar = Calendar.current
        let month = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? Date()
        let viewModel = CashflowViewModel(
            modelContext: context,
            now: { calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12)) ?? Date() }
        )

        _ = try await viewModel.persistBulkExpenseImport(
            CashflowBulkExpensePersistRequest(
                cardID: card.cardUniqueID,
                month: month,
                shouldAffectCardBalance: true,
                entries: [
                    CashflowBulkExpensePersistEntry(
                        amount: 1_200,
                        expenseCategoryRaw: ExpenseCategory.groceries.rawValue,
                        note: "Первый заход",
                        sourceOrderIndex: 0
                    ),
                    CashflowBulkExpensePersistEntry(
                        amount: 800,
                        expenseCategoryRaw: ExpenseCategory.transport.rawValue,
                        note: nil,
                        sourceOrderIndex: 1
                    )
                ]
            )
        )

        _ = try await viewModel.persistBulkExpenseImport(
            CashflowBulkExpensePersistRequest(
                cardID: card.cardUniqueID,
                month: month,
                shouldAffectCardBalance: true,
                entries: [
                    CashflowBulkExpensePersistEntry(
                        amount: 1_500,
                        expenseCategoryRaw: ExpenseCategory.groceries.rawValue,
                        note: "Обновлено",
                        sourceOrderIndex: 0
                    ),
                    CashflowBulkExpensePersistEntry(
                        amount: 900,
                        expenseCategoryRaw: ExpenseCategory.bills.rawValue,
                        note: "Интернет",
                        sourceOrderIndex: 1
                    )
                ]
            )
        )

        let transactions = try context.fetch(FetchDescriptor<CashflowTransaction>())
        let imported = transactions.filter {
            $0.importSourceRaw == CashflowBulkExpenseImportTransactionSource.monthlyCategoryRollup.rawValue
        }

        #expect(imported.count == 2)
        #expect(abs(card.balance - 7_600) < 0.001)
        #expect(imported.contains {
            $0.expenseCategoryRaw == ExpenseCategory.groceries.rawValue
            && abs($0.amount - 1_500) < 0.001
            && $0.note == "Обновлено"
        })
        #expect(imported.contains {
            $0.expenseCategoryRaw == ExpenseCategory.bills.rawValue
            && abs($0.amount - 900) < 0.001
            && $0.note == "Интернет"
        })
        #expect(!imported.contains { $0.expenseCategoryRaw == ExpenseCategory.transport.rawValue })
    }

    @Test("Экран поднимает только сохраненный месячный набор массового импорта для карты и месяца")
    func storedEntriesReturnOnlyTaggedMonthlyImportTransactions() async throws {
        let context = try makeContext()
        let card = Card(name: "Main", cardNumber: "1234", bank: .tinkoff, currency: "RUB", balance: 5_000)
        context.insert(card)

        let month = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? Date()
        let tagged = CashflowTransaction(
            transactionType: .expense,
            amount: 1_250,
            currency: "RUB",
            transactionDate: month,
            cardID: card.cardUniqueID,
            expenseCategoryRaw: ExpenseCategory.groceries.rawValue,
            note: "Импорт",
            importSourceRaw: CashflowBulkExpenseImportTransactionSource.monthlyCategoryRollup.rawValue,
            importReferenceKey: CashflowViewModel.bulkExpenseImportReferenceKey(
                cardID: card.cardUniqueID,
                month: month,
                categoryRaw: ExpenseCategory.groceries.rawValue,
                affectsCardBalance: false
            ),
            affectsCardBalance: false
        )
        let regular = CashflowTransaction(
            transactionType: .expense,
            amount: 900,
            currency: "RUB",
            transactionDate: month,
            cardID: card.cardUniqueID,
            expenseCategoryRaw: ExpenseCategory.transport.rawValue,
            note: "Обычная транзакция",
            affectsCardBalance: true
        )
        context.insert(tagged)
        context.insert(regular)
        try context.save()

        let viewModel = CashflowViewModel(modelContext: context)
        let stored = viewModel.bulkExpenseImportStoredEntries(
            cardID: card.cardUniqueID,
            month: month,
            affectsCardBalance: false
        )

        #expect(stored.count == 1)
        #expect(stored.first?.categoryRaw == ExpenseCategory.groceries.rawValue)
        #expect(abs((stored.first?.amount ?? 0) - 1_250) < 0.001)
        #expect(stored.first?.note == "Импорт")
        #expect(stored.first?.affectsCardBalance == false)
    }

    @Test("Массовый импорт хранит отдельные месячные наборы для режимов с балансом и без")
    func bulkPersistSeparatesBalanceModes() async throws {
        let context = try makeContext()
        let card = Card(name: "Main", cardNumber: "1234", bank: .tinkoff, currency: "RUB", balance: 10_000)
        context.insert(card)
        try context.save()

        let month = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? Date()
        let viewModel = CashflowViewModel(modelContext: context)

        _ = try await viewModel.persistBulkExpenseImport(
            CashflowBulkExpensePersistRequest(
                cardID: card.cardUniqueID,
                month: month,
                shouldAffectCardBalance: true,
                entries: [
                    CashflowBulkExpensePersistEntry(
                        amount: 1_200,
                        expenseCategoryRaw: ExpenseCategory.groceries.rawValue,
                        note: "Списалось с карты",
                        sourceOrderIndex: 0
                    )
                ]
            )
        )

        _ = try await viewModel.persistBulkExpenseImport(
            CashflowBulkExpensePersistRequest(
                cardID: card.cardUniqueID,
                month: month,
                shouldAffectCardBalance: false,
                entries: [
                    CashflowBulkExpensePersistEntry(
                        amount: 900,
                        expenseCategoryRaw: ExpenseCategory.groceries.rawValue,
                        note: "Только история",
                        sourceOrderIndex: 0
                    )
                ]
            )
        )

        let affectingEntries = viewModel.bulkExpenseImportStoredEntries(
            cardID: card.cardUniqueID,
            month: month,
            affectsCardBalance: true
        )
        let historyOnlyEntries = viewModel.bulkExpenseImportStoredEntries(
            cardID: card.cardUniqueID,
            month: month,
            affectsCardBalance: false
        )
        let transactions = try context.fetch(FetchDescriptor<CashflowTransaction>())
            .filter { $0.importSourceRaw == CashflowBulkExpenseImportTransactionSource.monthlyCategoryRollup.rawValue }

        #expect(affectingEntries.count == 1)
        #expect(historyOnlyEntries.count == 1)
        #expect(abs((affectingEntries.first?.amount ?? 0) - 1_200) < 0.001)
        #expect(abs((historyOnlyEntries.first?.amount ?? 0) - 900) < 0.001)
        #expect(affectingEntries.first?.note == "Списалось с карты")
        #expect(historyOnlyEntries.first?.note == "Только история")
        #expect(transactions.count == 2)
        #expect(Set(transactions.map(\.importReferenceKey)).count == 2)
        #expect(abs(card.balance - 8_800) < 0.001)
    }

    @Test("Массовый импорт видит ручные операции месяца как baseline и не дублирует их в rollup")
    func bulkImportUsesManualTransactionsAsBaseline() async throws {
        let context = try makeContext()
        let card = Card(name: "Main", cardNumber: "1234", bank: .tinkoff, currency: "RUB", balance: 10_000)
        context.insert(card)

        let month = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1)) ?? Date()
        let manualExpense = CashflowTransaction(
            transactionType: .expense,
            amount: 1_500,
            currency: "RUB",
            transactionDate: month,
            cardID: card.cardUniqueID,
            expenseCategoryRaw: ExpenseCategory.groceries.rawValue,
            note: "Ручной ввод",
            affectsCardBalance: true
        )
        context.insert(manualExpense)
        try context.save()

        let viewModel = CashflowViewModel(modelContext: context)

        let baseline = viewModel.bulkExpenseImportBaselineCategoryTotals(
            cardID: card.cardUniqueID,
            month: month,
            affectsCardBalance: true
        )
        #expect(abs((baseline[ExpenseCategory.groceries.rawValue] ?? 0) - 1_500) < 0.001)

        _ = try await viewModel.persistBulkExpenseImport(
            CashflowBulkExpensePersistRequest(
                cardID: card.cardUniqueID,
                month: month,
                shouldAffectCardBalance: true,
                entries: [
                    CashflowBulkExpensePersistEntry(
                        amount: 400,
                        expenseCategoryRaw: ExpenseCategory.groceries.rawValue,
                        note: "Добивка из bulk",
                        sourceOrderIndex: 0
                    )
                ]
            )
        )

        let rollupEntries = viewModel.bulkExpenseImportStoredEntries(
            cardID: card.cardUniqueID,
            month: month,
            affectsCardBalance: true
        )
        let allTransactions = try context.fetch(FetchDescriptor<CashflowTransaction>())
        let manualTransactions = allTransactions.filter { $0.importSourceRaw == nil }
        let rollupTransactions = allTransactions.filter {
            $0.importSourceRaw == CashflowBulkExpenseImportTransactionSource.monthlyCategoryRollup.rawValue
        }

        #expect(manualTransactions.count == 1)
        #expect(rollupTransactions.count == 1)
        #expect(abs((rollupEntries.first?.amount ?? 0) - 400) < 0.001)
        #expect(abs(card.balance - 9_600) < 0.001)
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
