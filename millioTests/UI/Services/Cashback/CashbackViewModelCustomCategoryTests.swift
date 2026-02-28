//
//  CashbackViewModelCustomCategoryTests.swift
//  millioTests
//
//  Created by Codex on 25.02.2026.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct CashbackViewModelCustomCategoryTests {
    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
            Cashback.self,
            CashbackCustomCategory.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [configuration])
    }()

    private func createModelContext() throws -> ModelContext {
        let context = Self.sharedContainer.mainContext
        try context.deleteAll(Cashback.self)
        try context.deleteAll(CashbackCustomCategory.self)
        try context.deleteAll(Card.self)
        try context.save()
        return context
    }

    private func monthDate(year: Int, month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "CashbackViewModelCustomCategoryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("Создание пользовательской категории сохраняет её и возвращает custom raw")
    func testCreateCustomCategoryStoresModel() throws {
        let context = try createModelContext()
        let viewModel = CashbackViewModel(modelContext: context)

        let option = viewModel.createCustomCategory("Кофейни", icon: "cup.and.saucer.fill")

        #expect(option != nil)
        #expect(option?.isCustom == true)
        #expect(option?.rawValue.hasPrefix(Cashback.customCategoryPrefix) == true)
        #expect(option?.displayName == "Кофейни")
        #expect(option?.icon == "cup.and.saucer.fill")
        #expect(viewModel.state.customCategories.count == 1)
        #expect(viewModel.state.customCategories.first?.name == "Кофейни")
        #expect(viewModel.state.customCategories.first?.icon == "cup.and.saucer.fill")
    }

    @Test("Создание дубликата категории возвращает уже существующую")
    func testCreateCustomCategoryDeduplicatesByNormalizedName() throws {
        let context = try createModelContext()
        let viewModel = CashbackViewModel(modelContext: context)

        let first = viewModel.createCustomCategory("Кино")
        let second = viewModel.createCustomCategory("  кИНо  ")

        #expect(first != nil)
        #expect(second != nil)
        #expect(first?.rawValue == second?.rawValue)
        #expect(viewModel.state.customCategories.count == 1)
    }

    @Test("updateCashbacksForCard сохраняет кастомную категорию в кэшбэке")
    func testUpdateCashbacksForCardWithCustomCategory() throws {
        let context = try createModelContext()

        let card = Card(
            name: "Тест карта",
            cardNumber: "1111 2222 3333 4444",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000
        )
        context.insert(card)
        try context.save()

        let viewModel = CashbackViewModel(modelContext: context)
        let customOption = viewModel.createCustomCategory("Кофейни")
        #expect(customOption != nil)

        guard let customOption else { return }

        viewModel.handle(.updateCashbacksForCard(
            cardID: card.cardUniqueID,
            cashbacks: [(
                categoryRaw: customOption.rawValue,
                categoryName: customOption.displayName,
                percentage: 7
            )]
        ))

        #expect(viewModel.state.cashbacks.count == 1)
        #expect(viewModel.state.cashbacks[0].categoryRaw == customOption.rawValue)
        #expect(viewModel.state.cashbacks[0].name == "Кофейни")
        #expect(viewModel.state.cashbacks[0].percentage == 7)
    }

    @Test("renameCustomCategory обновляет название и мигрирует связанные Cashback")
    func testRenameCustomCategoryUpdatesLinkedCashbacks() throws {
        let context = try createModelContext()

        let card = Card(
            name: "Тест карта",
            cardNumber: "1111 2222 3333 4444",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000
        )
        context.insert(card)
        try context.save()

        let viewModel = CashbackViewModel(modelContext: context)
        let custom = viewModel.createCustomCategory("Кино")
        #expect(custom != nil)
        guard let custom else { return }

        viewModel.handle(.updateCashbacksForCard(
            cardID: card.cardUniqueID,
            cashbacks: [(
                categoryRaw: custom.rawValue,
                categoryName: custom.displayName,
                percentage: 8
            )]
        ))

        let renamed = viewModel.renameCustomCategory(
            rawValue: custom.rawValue,
            newName: "Кинотеатры",
            newIcon: "gift.fill"
        )
        #expect(renamed)
        #expect(viewModel.state.customCategories.count == 1)
        #expect(viewModel.state.customCategories.first?.name == "Кинотеатры")
        #expect(viewModel.state.customCategories.first?.icon == "gift.fill")
        #expect(viewModel.state.cashbacks.count == 1)
        #expect(viewModel.state.cashbacks[0].categoryRaw == custom.rawValue)
        #expect(viewModel.state.cashbacks[0].name == "Кинотеатры")
        #expect(viewModel.categoryOption(for: custom.rawValue).icon == "gift.fill")
    }

    @Test("deleteCustomCategory переносит связанные Cashback в Другое и удаляет категорию")
    func testDeleteCustomCategoryMigratesToOther() throws {
        let context = try createModelContext()

        let card = Card(
            name: "Тест карта",
            cardNumber: "1111 2222 3333 4444",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000
        )
        context.insert(card)
        try context.save()

        let viewModel = CashbackViewModel(modelContext: context)
        let custom = viewModel.createCustomCategory("Такси")
        #expect(custom != nil)
        guard let custom else { return }

        viewModel.handle(.updateCashbacksForCard(
            cardID: card.cardUniqueID,
            cashbacks: [(
                categoryRaw: custom.rawValue,
                categoryName: custom.displayName,
                percentage: 6
            )]
        ))

        let deleted = viewModel.deleteCustomCategory(rawValue: custom.rawValue)
        #expect(deleted)
        #expect(viewModel.state.customCategories.isEmpty)
        #expect(viewModel.state.cashbacks.count == 1)
        #expect(viewModel.state.cashbacks[0].categoryRaw == CashbackCategory.other.rawValue)
        #expect(viewModel.state.cashbacks[0].name == CashbackCategory.other.displayName)
    }

    @Test("Список кэшбэков фильтруется по выбранному месяцу")
    func testVisibleCashbacksAreFilteredBySelectedMonth() throws {
        let context = try createModelContext()

        let january = monthDate(year: 2026, month: 1)
        let february = monthDate(year: 2026, month: 2)

        context.insert(Cashback(
            name: "Январь",
            category: .pharmacy,
            percentage: 5,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: january)
        ))
        context.insert(Cashback(
            name: "Февраль",
            category: .restaurant,
            percentage: 7,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: february)
        ))
        try context.save()

        let viewModel = CashbackViewModel(modelContext: context, now: { february })
        #expect(viewModel.state.visibleCashbacks.count == 1)
        #expect(viewModel.state.visibleCashbacks.first?.name == "Февраль")

        viewModel.handle(.setSelectedMonth(january))
        #expect(viewModel.state.visibleCashbacks.count == 1)
        #expect(viewModel.state.visibleCashbacks.first?.name == "Январь")
    }

    @Test("maxSelectableMonth нормализуется до начала текущего месяца")
    func testMaxSelectableMonthIsNormalizedToStartOfCurrentMonth() throws {
        let context = try createModelContext()
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 21)) ?? Date()
        let expected = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? now

        let viewModel = CashbackViewModel(
            modelContext: context,
            now: { now },
            defaults: makeDefaults()
        )

        #expect(viewModel.maxSelectableMonth == expected)
    }

    @Test("Избранные категории сортируются выше остальных")
    func testFavoriteCategoriesAreSortedFirst() throws {
        let context = try createModelContext()
        let defaults = makeDefaults()
        let february = monthDate(year: 2026, month: 2)

        context.insert(Cashback(
            name: "Бензин",
            category: .gasStation,
            percentage: 5,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: february)
        ))
        context.insert(Cashback(
            name: "Аптеки",
            category: .pharmacy,
            percentage: 10,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: february)
        ))
        try context.save()

        let viewModel = CashbackViewModel(
            modelContext: context,
            now: { february },
            defaults: defaults
        )

        #expect(viewModel.state.visibleCashbacks.first?.categoryRaw == CashbackCategory.pharmacy.rawValue)

        viewModel.handle(.toggleFavoriteCategory(rawValue: CashbackCategory.gasStation.rawValue))

        #expect(viewModel.state.visibleCashbacks.first?.categoryRaw == CashbackCategory.gasStation.rawValue)
    }

    @Test("Без избранного и закрепленного категории сортируются по проценту убыванию")
    func testVisibleCashbacksAreSortedByPercentageDescending() throws {
        let context = try createModelContext()
        let defaults = makeDefaults()
        let now = monthDate(year: 2026, month: 2)

        context.insert(Cashback(
            name: "Транспорт",
            category: .transport,
            percentage: 5,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: now)
        ))
        context.insert(Cashback(
            name: "Рестораны",
            category: .restaurant,
            percentage: 10,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: now)
        ))
        try context.save()

        let viewModel = CashbackViewModel(
            modelContext: context,
            now: { now },
            defaults: defaults
        )

        #expect(viewModel.state.visibleCashbacks.count == 2)
        #expect(viewModel.state.visibleCashbacks[0].categoryRaw == CashbackCategory.restaurant.rawValue)
        #expect(viewModel.state.visibleCashbacks[1].categoryRaw == CashbackCategory.transport.rawValue)
    }

    @Test("Закрепленные выше обычных, но ниже избранных")
    func testPinnedCategoriesAreBetweenFavoritesAndRegular() throws {
        let context = try createModelContext()
        let defaults = makeDefaults()
        let now = monthDate(year: 2026, month: 2)

        context.insert(Cashback(
            name: "Рестораны",
            category: .restaurant,
            percentage: 5,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: now)
        ))
        context.insert(Cashback(
            name: "Транспорт",
            category: .transport,
            percentage: 15,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: now)
        ))
        context.insert(Cashback(
            name: "Супермаркеты",
            category: .supermarket,
            percentage: 10,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: now)
        ))
        try context.save()

        let viewModel = CashbackViewModel(
            modelContext: context,
            now: { now },
            defaults: defaults
        )

        viewModel.handle(.togglePinnedCategory(rawValue: CashbackCategory.supermarket.rawValue))
        viewModel.handle(.toggleFavoriteCategory(rawValue: CashbackCategory.restaurant.rawValue))

        #expect(viewModel.state.visibleCashbacks.count == 3)
        #expect(viewModel.state.visibleCashbacks[0].categoryRaw == CashbackCategory.restaurant.rawValue)
        #expect(viewModel.state.visibleCashbacks[1].categoryRaw == CashbackCategory.supermarket.rawValue)
        #expect(viewModel.state.visibleCashbacks[2].categoryRaw == CashbackCategory.transport.rawValue)
    }

    @Test("Избранные категории кешбэка сохраняются в UserDefaults")
    func testFavoriteCategoriesPersistAcrossViewModelInstances() throws {
        let context = try createModelContext()
        let defaults = makeDefaults()
        let now = monthDate(year: 2026, month: 2)

        let first = CashbackViewModel(
            modelContext: context,
            now: { now },
            defaults: defaults
        )
        first.handle(.toggleFavoriteCategory(rawValue: CashbackCategory.restaurant.rawValue))
        #expect(first.isFavoriteCategory(rawValue: CashbackCategory.restaurant.rawValue))

        let second = CashbackViewModel(
            modelContext: context,
            now: { now },
            defaults: defaults
        )
        #expect(second.isFavoriteCategory(rawValue: CashbackCategory.restaurant.rawValue))
    }

    @Test("Одинаковая категория и карта создаются раздельно для разных месяцев")
    func testUpdateCashbacksForCardSeparatesByMonth() throws {
        let context = try createModelContext()
        let january = monthDate(year: 2026, month: 1)
        let february = monthDate(year: 2026, month: 2)

        let card = Card(
            name: "Тест карта",
            cardNumber: "1111 2222 3333 4444",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000
        )
        context.insert(card)
        try context.save()

        let viewModel = CashbackViewModel(modelContext: context, now: { february })
        let custom = viewModel.createCustomCategory("Кофейни")
        #expect(custom != nil)
        guard let custom else { return }

        viewModel.handle(.setSelectedMonth(january))
        viewModel.handle(.updateCashbacksForCard(
            cardID: card.cardUniqueID,
            cashbacks: [(
                categoryRaw: custom.rawValue,
                categoryName: custom.displayName,
                percentage: 5
            )]
        ))

        viewModel.handle(.setSelectedMonth(february))
        viewModel.handle(.updateCashbacksForCard(
            cardID: card.cardUniqueID,
            cashbacks: [(
                categoryRaw: custom.rawValue,
                categoryName: custom.displayName,
                percentage: 10
            )]
        ))

        #expect(viewModel.state.cashbacks.count == 2)

        let janKey = Cashback.monthKey(for: january)
        let febKey = Cashback.monthKey(for: february)
        let janCashback = viewModel.state.cashbacks.first { $0.monthKey == janKey }
        let febCashback = viewModel.state.cashbacks.first { $0.monthKey == febKey }

        #expect(janCashback?.percentage == 5)
        #expect(febCashback?.percentage == 10)
    }

    @Test("Невалидная иконка пользовательской категории заменяется на дефолтную")
    func testCustomCategoryInvalidIconFallsBackToDefault() throws {
        let context = try createModelContext()
        let viewModel = CashbackViewModel(modelContext: context)

        let option = viewModel.createCustomCategory("Поездки", icon: "not.valid.icon")

        #expect(option != nil)
        #expect(option?.icon == CashbackCustomCategory.defaultIcon)
        #expect(viewModel.state.customCategories.first?.icon == CashbackCustomCategory.defaultIcon)
    }
}
