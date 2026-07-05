// DataIntegrityCleanerCashbackCategoryDedupTests.swift
// millioTests
//
// Тест dedupeCashbackCustomCategoriesOnLaunch. Проверяет, что дубли CashbackCustomCategory
// с одинаковым categoryID (та же уязвимость, что была у CashflowCustomCategory — краш
// `Fatal error: Duplicate values for key: 'custom:<UUID>'` в ForEach/LazyVGrid по
// [CashbackCategoryOption]) схлопываются в одну запись при старте приложения.
//
// Намеренно БЕЗ одноразового UserDefaults-флага (по образцу Cashflow-фикса, см.
// DataIntegrityCleanerCashflowCategoryDedupTests): холодный старт создаёт первый DIContainer
// на guest-сторе ДО restoreSession/synchronizeDataScope, а реальный user-стор открывается
// вторым DIContainer.create() через rebindDataScope. Общий флаг сгорал бы на guest-сторе,
// и реальный user-стор с дублями никогда бы не дочищался. Патч гоняется на КАЖДОМ create().

import Testing
import Foundation
import SwiftData
@testable import millio

@MainActor
struct DataIntegrityCleanerCashbackCategoryDedupTests {

    // MARK: - Setup

    private static let sharedContainer: ModelContainer = {
        let schema = Schema([
            Card.self,
            Cashback.self,
            CashbackCustomCategory.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func makeContext() throws -> ModelContext {
        let ctx = Self.sharedContainer.mainContext
        try ctx.deleteAll(Cashback.self)
        try ctx.deleteAll(CashbackCustomCategory.self)
        try ctx.deleteAll(Card.self)
        try ctx.save()
        return ctx
    }

    private func makeSeparateContainer() -> ModelContainer {
        let schema = Schema([CashbackCustomCategory.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Tests

    @Test("Два CashbackCustomCategory с одинаковым categoryID схлопываются в одну запись")
    func dedupesCategoriesWithSameCategoryID() throws {
        let ctx = try makeContext()

        let sharedID = UUID().uuidString
        let older = CashbackCustomCategory(name: "Такси")
        older.categoryID = sharedID
        older.updatedAt = Date(timeIntervalSince1970: 1_000)

        let newer = CashbackCustomCategory(name: "Такси (переименовано)")
        newer.categoryID = sharedID
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)

        ctx.insert(older)
        ctx.insert(newer)
        try ctx.save()

        try DataIntegrityCleaner.dedupeCashbackCustomCategoriesOnLaunch(modelContext: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<CashbackCustomCategory>())
        #expect(remaining.count == 1, "Должна остаться только одна категория с этим categoryID")
        #expect(remaining.first?.name == "Такси (переименовано)", "Побеждает объект с более поздним updatedAt")
    }

    @Test("Категории с разными categoryID не затрагиваются патчем")
    func doesNotTouchDistinctCategories() throws {
        let ctx = try makeContext()

        let a = CashbackCustomCategory(name: "A")
        let b = CashbackCustomCategory(name: "B")
        ctx.insert(a)
        ctx.insert(b)
        try ctx.save()

        try DataIntegrityCleaner.dedupeCashbackCustomCategoriesOnLaunch(modelContext: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<CashbackCustomCategory>())
        #expect(remaining.count == 2, "Категории без дублей не должны удаляться")
    }

    @Test("Повторные запуски безопасны и продолжают чистить новые дубли")
    func repeatedRunsKeepCleaningNewDuplicates() throws {
        let ctx = try makeContext()

        let sharedID = UUID().uuidString
        let first = CashbackCustomCategory(name: "Первая")
        first.categoryID = sharedID
        first.updatedAt = Date(timeIntervalSince1970: 1_000)
        ctx.insert(first)
        try ctx.save()

        // Первый запуск — стор без дублей, безопасен на пустом/чистом сторе
        try DataIntegrityCleaner.dedupeCashbackCustomCategoriesOnLaunch(modelContext: ctx)

        // Дубль появился ПОСЛЕ первого запуска (например, CloudKit merge между запусками)
        let duplicate = CashbackCustomCategory(name: "Дубль после первого запуска")
        duplicate.categoryID = sharedID
        duplicate.updatedAt = Date(timeIntervalSince1970: 2_000)
        ctx.insert(duplicate)
        try ctx.save()

        // Второй запуск — без одноразового флага дубль обязан вычиститься.
        try DataIntegrityCleaner.dedupeCashbackCustomCategoriesOnLaunch(modelContext: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<CashbackCustomCategory>())
        #expect(remaining.count == 1, "Патч без одноразового флага обязан вычищать дубли на каждом запуске")
        #expect(remaining.first?.name == "Дубль после первого запуска", "Побеждает объект с более поздним updatedAt")
    }

    @Test("Guest→user: патч на почти пустом guest-сторе не мешает дочистке user-стора с дублями")
    func guestScopeRunDoesNotBlockUserScopeCleanup() throws {
        // Симулирует реальную последовательность холодного старта: первый DIContainer.create()
        // идёт на guest-сторе (почти пустом), второй — на user-сторе (после rebindDataScope).
        // Это ДВА РАЗНЫХ ModelContainer/ModelContext.
        let guestContainer = makeSeparateContainer()
        let guestContext = guestContainer.mainContext
        // Guest-стор пуст — типичная ситуация холодного старта до логина.
        try DataIntegrityCleaner.dedupeCashbackCustomCategoriesOnLaunch(modelContext: guestContext)

        let userContainer = makeSeparateContainer()
        let userContext = userContainer.mainContext

        let sharedID = UUID().uuidString
        let older = CashbackCustomCategory(name: "Продукты")
        older.categoryID = sharedID
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        let newer = CashbackCustomCategory(name: "Продукты (дубль)")
        newer.categoryID = sharedID
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)
        userContext.insert(older)
        userContext.insert(newer)
        try userContext.save()

        try DataIntegrityCleaner.dedupeCashbackCustomCategoriesOnLaunch(modelContext: userContext)

        let remaining = try userContext.fetch(FetchDescriptor<CashbackCustomCategory>())
        #expect(remaining.count == 1, "User-стор обязан дочиститься независимо от того, что патч уже отработал на guest-сторе")
    }

    @Test("Патч не падает на пустом store")
    func emptyStoreDoesNotCrash() throws {
        let ctx = try makeContext()
        try DataIntegrityCleaner.dedupeCashbackCustomCategoriesOnLaunch(modelContext: ctx)
    }

    @Test("dedupeAll чистит и Cashflow, и Cashback дубли одновременно")
    func dedupeAllCleansBothCategoryKinds() throws {
        let schema = Schema([
            Investment.self,
            Card.self,
            Credit.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowTransaction.self,
            AssetCatalogItem.self,
            AssetProviderMapping.self,
            CashflowCustomCategory.self,
            CashflowSystemCategoryOverride.self,
            HistoricalRate.self,
            Cashback.self,
            CashbackCustomCategory.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let ctx = container.mainContext

        let cashbackID = UUID().uuidString
        let cashbackA = CashbackCustomCategory(name: "Кафе")
        cashbackA.categoryID = cashbackID
        cashbackA.updatedAt = Date(timeIntervalSince1970: 1_000)
        let cashbackB = CashbackCustomCategory(name: "Кафе (дубль)")
        cashbackB.categoryID = cashbackID
        cashbackB.updatedAt = Date(timeIntervalSince1970: 2_000)
        ctx.insert(cashbackA)
        ctx.insert(cashbackB)

        let cashflowID = UUID().uuidString
        let cashflowA = CashflowCustomCategory(kind: .expense, name: "Такси")
        cashflowA.categoryID = cashflowID
        cashflowA.updatedAt = Date(timeIntervalSince1970: 1_000)
        let cashflowB = CashflowCustomCategory(kind: .expense, name: "Такси (дубль)")
        cashflowB.categoryID = cashflowID
        cashflowB.updatedAt = Date(timeIntervalSince1970: 2_000)
        ctx.insert(cashflowA)
        ctx.insert(cashflowB)
        try ctx.save()

        try DataIntegrityCleaner.dedupeAll(modelContext: ctx)

        let remainingCashback = try ctx.fetch(FetchDescriptor<CashbackCustomCategory>())
        let remainingCashflow = try ctx.fetch(FetchDescriptor<CashflowCustomCategory>())
        #expect(remainingCashback.count == 1)
        #expect(remainingCashflow.count == 1)
    }
}
