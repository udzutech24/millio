// DataIntegrityCleanerCashflowCategoryDedupTests.swift
// millioTests
//
// Тест dedupeCashflowCustomCategoriesOnLaunch. Проверяет, что дубли CashflowCustomCategory
// с одинаковым categoryID (краш `Fatal error: Duplicate values for key: 'custom:<UUID>'`
// в ForEach/LazyVGrid) схлопываются в одну запись при старте приложения.
//
// Намеренно БЕЗ одноразового UserDefaults-флага (см. комментарий в DataIntegrityCleaner):
// холодный старт создаёт первый DIContainer на guest-сторе ДО restoreSession/
// synchronizeDataScope, а реальный user-стор открывается вторым DIContainer.create()
// через rebindDataScope. Общий на всё приложение флаг сгорал бы на guest-сторе, и
// реальный user-стор с дублями никогда бы не дочищался — это и была "Дыра 1" из
// адверсарной проверки. Патч гоняется на КАЖДОМ create(), без гейта.

import Testing
import Foundation
import SwiftData
@testable import millio

@MainActor
struct DataIntegrityCleanerCashflowCategoryDedupTests {

    // MARK: - Setup

    private static let sharedContainer: ModelContainer = {
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
            HistoricalRate.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    private func makeContext() throws -> ModelContext {
        let ctx = Self.sharedContainer.mainContext
        try ctx.deleteAll(CashflowCustomCategory.self)
        try ctx.save()
        return ctx
    }

    private func makeSeparateContainer() -> ModelContainer {
        let schema = Schema([CashflowCustomCategory.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Tests

    @Test("Два CashflowCustomCategory с одинаковым categoryID схлопываются в одну запись")
    func dedupesCategoriesWithSameCategoryID() throws {
        let ctx = try makeContext()

        let sharedID = UUID().uuidString
        let older = CashflowCustomCategory(kind: .expense, name: "Такси")
        older.categoryID = sharedID
        older.updatedAt = Date(timeIntervalSince1970: 1_000)

        let newer = CashflowCustomCategory(kind: .expense, name: "Такси (переименовано)")
        newer.categoryID = sharedID
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)

        ctx.insert(older)
        ctx.insert(newer)
        try ctx.save()

        try DataIntegrityCleaner.dedupeCashflowCustomCategoriesOnLaunch(modelContext: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<CashflowCustomCategory>())
        #expect(remaining.count == 1, "Должна остаться только одна категория с этим categoryID")
        #expect(remaining.first?.name == "Такси (переименовано)", "Побеждает объект с более поздним updatedAt")
    }

    @Test("Категории с разными categoryID не затрагиваются патчем")
    func doesNotTouchDistinctCategories() throws {
        let ctx = try makeContext()

        let a = CashflowCustomCategory(kind: .expense, name: "A")
        let b = CashflowCustomCategory(kind: .income, name: "B")
        ctx.insert(a)
        ctx.insert(b)
        try ctx.save()

        try DataIntegrityCleaner.dedupeCashflowCustomCategoriesOnLaunch(modelContext: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<CashflowCustomCategory>())
        #expect(remaining.count == 2, "Категории без дублей не должны удаляться")
    }

    @Test("Повторные запуски безопасны и продолжают чистить новые дубли (регресс на 'Дыру 1')")
    func repeatedRunsKeepCleaningNewDuplicates() throws {
        let ctx = try makeContext()

        let sharedID = UUID().uuidString
        let first = CashflowCustomCategory(kind: .expense, name: "Первая")
        first.categoryID = sharedID
        first.updatedAt = Date(timeIntervalSince1970: 1_000)
        ctx.insert(first)
        try ctx.save()

        // Первый запуск — стор без дублей, безопасен на пустом/чистом сторе
        try DataIntegrityCleaner.dedupeCashflowCustomCategoriesOnLaunch(modelContext: ctx)

        // Дубль появился ПОСЛЕ первого запуска (например, CloudKit merge между запусками)
        let duplicate = CashflowCustomCategory(kind: .expense, name: "Дубль после первого запуска")
        duplicate.categoryID = sharedID
        duplicate.updatedAt = Date(timeIntervalSince1970: 2_000)
        ctx.insert(duplicate)
        try ctx.save()

        // Второй запуск — раньше был бы заблокирован одноразовым флагом (Дыра 1).
        // Теперь флага нет — дубль обязан вычиститься.
        try DataIntegrityCleaner.dedupeCashflowCustomCategoriesOnLaunch(modelContext: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<CashflowCustomCategory>())
        #expect(remaining.count == 1, "Патч без одноразового флага обязан вычищать дубли на каждом запуске")
        #expect(remaining.first?.name == "Дубль после первого запуска", "Побеждает объект с более поздним updatedAt")
    }

    @Test("Guest→user: патч на почти пустом guest-сторе не мешает дочистке user-стора с дублями")
    func guestScopeRunDoesNotBlockUserScopeCleanup() throws {
        // Симулирует реальную последовательность холодного старта: первый DIContainer.create()
        // идёт на guest-сторе (почти пустом), второй — на user-сторе (после rebindDataScope).
        // Это ДВА РАЗНЫХ ModelContainer/ModelContext — раньше общий UserDefaults-флаг,
        // сожжённый на guest-сторе, блокировал дедуп для user-стора (Дыра 1).
        let guestContainer = makeSeparateContainer()
        let guestContext = guestContainer.mainContext
        // Guest-стор пуст — типичная ситуация холодного старта до логина.
        try DataIntegrityCleaner.dedupeCashflowCustomCategoriesOnLaunch(modelContext: guestContext)

        let userContainer = makeSeparateContainer()
        let userContext = userContainer.mainContext

        let sharedID = UUID().uuidString
        let older = CashflowCustomCategory(kind: .expense, name: "Продукты")
        older.categoryID = sharedID
        older.updatedAt = Date(timeIntervalSince1970: 1_000)
        let newer = CashflowCustomCategory(kind: .expense, name: "Продукты (дубль)")
        newer.categoryID = sharedID
        newer.updatedAt = Date(timeIntervalSince1970: 2_000)
        userContext.insert(older)
        userContext.insert(newer)
        try userContext.save()

        try DataIntegrityCleaner.dedupeCashflowCustomCategoriesOnLaunch(modelContext: userContext)

        let remaining = try userContext.fetch(FetchDescriptor<CashflowCustomCategory>())
        #expect(remaining.count == 1, "User-стор обязан дочиститься независимо от того, что патч уже отработал на guest-сторе")
    }

    @Test("Патч не падает на пустом store")
    func emptyStoreDoesNotCrash() throws {
        let ctx = try makeContext()
        try DataIntegrityCleaner.dedupeCashflowCustomCategoriesOnLaunch(modelContext: ctx)
    }
}
