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

    @Test("Создание пользовательской категории поддерживает emoji-иконку")
    func testCreateCustomCategoryStoresEmojiIcon() throws {
        let context = try createModelContext()
        let viewModel = CashbackViewModel(modelContext: context)

        let option = viewModel.createCustomCategory("Путешествия", icon: "✈️")

        #expect(option != nil)
        #expect(option?.icon == "✈️")
        #expect(viewModel.state.customCategories.count == 1)
        #expect(viewModel.state.customCategories.first?.icon == "✈️")
    }

    @Test("Недопустимая иконка нормализуется к defaultIcon")
    func testCreateCustomCategoryNormalizesUnsupportedIcon() throws {
        let context = try createModelContext()
        let viewModel = CashbackViewModel(modelContext: context)

        let option = viewModel.createCustomCategory("Неизвестная", icon: "no-such-icon")

        #expect(option != nil)
        #expect(option?.icon == CashbackCustomCategory.defaultIcon)
        #expect(viewModel.state.customCategories.first?.icon == CashbackCustomCategory.defaultIcon)
    }

    @Test("Системное имя с другой иконкой создает кастомную категорию")
    func testCreateCustomCategoryWithSystemNameAndCustomIconCreatesCustom() throws {
        let context = try createModelContext()
        let viewModel = CashbackViewModel(modelContext: context)

        let option = viewModel.createCustomCategory("Аптеки", icon: "🍩")

        #expect(option != nil)
        #expect(option?.isCustom == true)
        #expect(option?.displayName == "Аптеки")
        #expect(option?.icon == "🍩")
        #expect(option?.rawValue.hasPrefix(Cashback.customCategoryPrefix) == true)
        #expect(viewModel.state.customCategories.count == 1)
        #expect(viewModel.state.customCategories.first?.name == "Аптеки")
        #expect(viewModel.state.customCategories.first?.icon == "🍩")
    }

    @Test("Системные категории кэшбэка используют emoji по умолчанию")
    func testSystemCashbackCategoryIconsAreEmoji() {
        #expect((35...40).contains(CashbackCategory.allCases.count))
        #expect(CashbackCategory.gasStation.icon == "⛽️")
        #expect(CashbackCategory.supermarket.icon == "🛒")
        #expect(CashbackCategory.restaurant.icon == "🍽️")
        #expect(CashbackCategory.fastFood.icon == "🍔")
        #expect(CashbackCategory.coffeeShop.icon == "☕️")
        #expect(CashbackCategory.pharmacy.icon == "💊")
        #expect(CashbackCategory.healthcare.icon == "🩺")
        #expect(CashbackCategory.transport.icon == "🚕")
        #expect(CashbackCategory.taxi.icon == "🚖")
        #expect(CashbackCategory.carSharing.icon == "🚗")
        #expect(CashbackCategory.entertainment.icon == "🎮")
        #expect(CashbackCategory.travel.icon == "🧳")
        #expect(CashbackCategory.marketplaces.icon == "📦")
        #expect(CashbackCategory.online.icon == "🌐")
        #expect(CashbackCategory.other.icon == "🧩")
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

    @Test("renameCustomCategory позволяет поменять только иконку без смены названия")
    func testRenameCustomCategoryUpdatesOnlyIcon() throws {
        let context = try createModelContext()
        let viewModel = CashbackViewModel(modelContext: context)

        let custom = viewModel.createCustomCategory("Кофе навынос", icon: "cup.and.saucer.fill")
        #expect(custom != nil)
        guard let custom else { return }

        let updated = viewModel.renameCustomCategory(
            rawValue: custom.rawValue,
            newName: "Кофе навынос",
            newIcon: "☕️"
        )

        #expect(updated)
        #expect(viewModel.state.customCategories.count == 1)
        #expect(viewModel.state.customCategories.first?.name == "Кофе навынос")
        #expect(viewModel.state.customCategories.first?.icon == "☕️")
        #expect(viewModel.categoryOption(for: custom.rawValue).icon == "☕️")
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

    @Test("deleteCategory для системной категории мигрирует кешбэки в Другое и скрывает категорию")
    func testDeleteSystemCategoryMigratesAndHidesIt() throws {
        let context = try createModelContext()

        context.insert(Cashback(
            name: CashbackCategory.pharmacy.displayName,
            category: .pharmacy,
            percentage: 6,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: Date())
        ))
        try context.save()

        let viewModel = CashbackViewModel(modelContext: context)

        let deleted = viewModel.deleteCategory(rawValue: CashbackCategory.pharmacy.rawValue)
        #expect(deleted)

        #expect(viewModel.state.cashbacks.count == 1)
        #expect(viewModel.state.cashbacks[0].categoryRaw == CashbackCategory.other.rawValue)
        #expect(viewModel.state.cashbacks[0].name == CashbackCategory.other.displayName)
        #expect(viewModel.categoryOptions().contains { $0.rawValue == CashbackCategory.pharmacy.rawValue } == false)
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

    @Test("minSelectableMonth берется из самого раннего месяца кешбэка")
    func testMinSelectableMonthUsesEarliestCashbackMonth() throws {
        let context = try createModelContext()
        let january = monthDate(year: 2025, month: 1)
        let february = monthDate(year: 2026, month: 2)

        context.insert(Cashback(
            name: "Январь",
            category: .pharmacy,
            percentage: 3,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: january)
        ))
        context.insert(Cashback(
            name: "Февраль",
            category: .transport,
            percentage: 5,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: february)
        ))
        try context.save()

        let viewModel = CashbackViewModel(
            modelContext: context,
            now: { february },
            defaults: makeDefaults()
        )

        #expect(viewModel.minSelectableMonth == january)
    }

    @Test("minSelectableMonth без кешбэков откатывается на 24 месяца назад")
    func testMinSelectableMonthFallsBackToTwoYearsBackWhenNoData() throws {
        let context = try createModelContext()
        let now = monthDate(year: 2026, month: 2)
        let expected = monthDate(year: 2024, month: 2)

        let viewModel = CashbackViewModel(
            modelContext: context,
            now: { now },
            defaults: makeDefaults()
        )

        #expect(viewModel.minSelectableMonth == expected)
    }

    @Test("Переход вперед по месяцу не может выйти за maxSelectableMonth")
    func testMoveMonthForwardStopsAtCurrentMonth() throws {
        let context = try createModelContext()
        let january = monthDate(year: 2026, month: 1)
        let february = monthDate(year: 2026, month: 2)

        let viewModel = CashbackViewModel(
            modelContext: context,
            now: { february },
            defaults: makeDefaults()
        )

        viewModel.handle(.setSelectedMonth(january))
        viewModel.handle(.moveMonthForward)
        #expect(viewModel.selectedMonthTitle == "Февраль 2026")

        viewModel.handle(.moveMonthForward)
        #expect(viewModel.selectedMonthTitle == "Февраль 2026")
    }

    @Test("Переход назад по месяцу сдвигает selectedMonth на один месяц")
    func testMoveMonthBackwardShiftsSelectedMonth() throws {
        let context = try createModelContext()
        let march = monthDate(year: 2026, month: 3)

        let viewModel = CashbackViewModel(
            modelContext: context,
            now: { march },
            defaults: makeDefaults()
        )

        #expect(viewModel.selectedMonthTitle == "Март 2026")
        viewModel.handle(.moveMonthBackward)
        #expect(viewModel.selectedMonthTitle == "Февраль 2026")
    }

    @Test("Переход назад по месяцу не выходит за minSelectableMonth")
    func testMoveMonthBackwardStopsAtMinSelectableMonth() throws {
        let context = try createModelContext()
        let may = monthDate(year: 2026, month: 5)
        let april = monthDate(year: 2026, month: 4)

        context.insert(Cashback(
            name: "Транспорт",
            category: .transport,
            percentage: 5,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: april)
        ))
        try context.save()

        let viewModel = CashbackViewModel(
            modelContext: context,
            now: { may },
            defaults: makeDefaults()
        )

        #expect(viewModel.selectedMonthTitle == "Май 2026")
        viewModel.handle(.moveMonthBackward)
        #expect(viewModel.selectedMonthTitle == "Апрель 2026")
        #expect(viewModel.canMoveMonthBackward() == false)

        viewModel.handle(.moveMonthBackward)
        #expect(viewModel.selectedMonthTitle == "Апрель 2026")
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

    @Test("Переименование кастомной категории в системную переносит избранное")
    func testRenameCustomCategoryToSystemMigratesFavorite() throws {
        let context = try createModelContext()
        let defaults = makeDefaults()
        let viewModel = CashbackViewModel(modelContext: context, defaults: defaults)

        let custom = viewModel.createCustomCategory("Кофе")
        #expect(custom != nil)
        guard let custom else { return }

        viewModel.handle(.toggleFavoriteCategory(rawValue: custom.rawValue))
        #expect(viewModel.isFavoriteCategory(rawValue: custom.rawValue))

        let renamed = viewModel.renameCustomCategory(
            rawValue: custom.rawValue,
            newName: CashbackCategory.pharmacy.displayName
        )

        #expect(renamed)
        #expect(!viewModel.isFavoriteCategory(rawValue: custom.rawValue))
        #expect(viewModel.isFavoriteCategory(rawValue: CashbackCategory.pharmacy.rawValue))
    }

    @Test("Удаление кастомной категории очищает избранное и закрепленное состояние")
    func testDeleteCustomCategoryClearsFavoriteAndPinned() throws {
        let context = try createModelContext()
        let defaults = makeDefaults()
        let viewModel = CashbackViewModel(modelContext: context, defaults: defaults)

        let custom = viewModel.createCustomCategory("Парковки")
        #expect(custom != nil)
        guard let custom else { return }

        viewModel.handle(.toggleFavoriteCategory(rawValue: custom.rawValue))
        viewModel.handle(.toggleFavoriteCategory(rawValue: custom.rawValue))
        viewModel.handle(.togglePinnedCategory(rawValue: custom.rawValue))
        #expect(viewModel.isPinnedCategory(rawValue: custom.rawValue))

        let deleted = viewModel.deleteCustomCategory(rawValue: custom.rawValue)

        #expect(deleted)
        #expect(!viewModel.isFavoriteCategory(rawValue: custom.rawValue))
        #expect(!viewModel.isPinnedCategory(rawValue: custom.rawValue))
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

    @Test("updateCashbacksForCard удаляет снятые категории для выбранной карты")
    func testUpdateCashbacksForCardRemovesDeselectedCategories() throws {
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
        let supermarket = viewModel.categoryOption(for: CashbackCategory.supermarket.rawValue)
        let pharmacy = viewModel.categoryOption(for: CashbackCategory.pharmacy.rawValue)

        viewModel.handle(.updateCashbacksForCard(
            cardID: card.cardUniqueID,
            cashbacks: [
                (
                    categoryRaw: supermarket.rawValue,
                    categoryName: supermarket.displayName,
                    percentage: 5
                ),
                (
                    categoryRaw: pharmacy.rawValue,
                    categoryName: pharmacy.displayName,
                    percentage: 10
                )
            ]
        ))
        #expect(viewModel.state.cashbacks.count == 2)

        viewModel.handle(.updateCashbacksForCard(
            cardID: card.cardUniqueID,
            cashbacks: [(
                categoryRaw: supermarket.rawValue,
                categoryName: supermarket.displayName,
                percentage: 7
            )]
        ))

        #expect(viewModel.state.cashbacks.count == 1)
        #expect(viewModel.state.cashbacks.first?.categoryRaw == supermarket.rawValue)
        #expect(viewModel.state.cashbacks.first?.percentage == 7)
    }

    @Test("updateCashbacksForCard позволяет очистить все категории карты")
    func testUpdateCashbacksForCardCanClearAllCategoriesForCard() throws {
        let context = try createModelContext()

        let card = Card(
            name: "Тест карта",
            cardNumber: "5555 6666 7777 8888",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 1_000
        )
        context.insert(card)
        try context.save()

        let viewModel = CashbackViewModel(modelContext: context)
        let transport = viewModel.categoryOption(for: CashbackCategory.transport.rawValue)

        viewModel.handle(.updateCashbacksForCard(
            cardID: card.cardUniqueID,
            cashbacks: [(
                categoryRaw: transport.rawValue,
                categoryName: transport.displayName,
                percentage: 5
            )]
        ))
        #expect(viewModel.state.cashbacks.count == 1)

        viewModel.handle(.updateCashbacksForCard(
            cardID: card.cardUniqueID,
            cashbacks: []
        ))

        #expect(viewModel.state.cashbacks.isEmpty)
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
