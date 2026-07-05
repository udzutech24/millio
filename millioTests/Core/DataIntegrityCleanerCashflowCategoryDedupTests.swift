// DataIntegrityCleanerCashflowCategoryDedupTests.swift
// millioTests
//
// Тест однократного патча dedupeCashflowCustomCategoriesIfNeeded.
// Проверяет, что дубли CashflowCustomCategory с одинаковым categoryID (краш
// `Fatal error: Duplicate values for key: 'custom:<UUID>'` в ForEach/LazyVGrid)
// схлопываются в одну запись при старте приложения, и что патч не применяется повторно.

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

    private let migrationKey = "migration.dedupeCashflowCustomCategories.v1"

    private func resetMigrationFlag() {
        UserDefaults.standard.removeObject(forKey: migrationKey)
    }

    // MARK: - Tests

    @Test("Два CashflowCustomCategory с одинаковым categoryID схлопываются в одну запись")
    func dedupesCategoriesWithSameCategoryID() throws {
        resetMigrationFlag()
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

        try DataIntegrityCleaner.dedupeCashflowCustomCategoriesIfNeeded(modelContext: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<CashflowCustomCategory>())
        #expect(remaining.count == 1, "Должна остаться только одна категория с этим categoryID")
        #expect(remaining.first?.name == "Такси (переименовано)", "Побеждает объект с более поздним updatedAt")
    }

    @Test("Категории с разными categoryID не затрагиваются патчем")
    func doesNotTouchDistinctCategories() throws {
        resetMigrationFlag()
        let ctx = try makeContext()

        let a = CashflowCustomCategory(kind: .expense, name: "A")
        let b = CashflowCustomCategory(kind: .income, name: "B")
        ctx.insert(a)
        ctx.insert(b)
        try ctx.save()

        try DataIntegrityCleaner.dedupeCashflowCustomCategoriesIfNeeded(modelContext: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<CashflowCustomCategory>())
        #expect(remaining.count == 2, "Категории без дублей не должны удаляться")
    }

    @Test("Патч выполняется только один раз — флаг UserDefaults блокирует повторный запуск")
    func idempotency() throws {
        resetMigrationFlag()
        let ctx = try makeContext()

        let sharedID = UUID().uuidString
        let first = CashflowCustomCategory(kind: .expense, name: "Первая")
        first.categoryID = sharedID
        first.updatedAt = Date(timeIntervalSince1970: 1_000)
        ctx.insert(first)
        try ctx.save()

        // Первый запуск — стора без дублей, ничего не меняется, но флаг выставляется
        try DataIntegrityCleaner.dedupeCashflowCustomCategoriesIfNeeded(modelContext: ctx)

        // Симулируем дубль, появившийся ПОСЛЕ первого запуска патча (например, CloudKit merge)
        let duplicate = CashflowCustomCategory(kind: .expense, name: "Дубль после патча")
        duplicate.categoryID = sharedID
        duplicate.updatedAt = Date(timeIntervalSince1970: 2_000)
        ctx.insert(duplicate)
        try ctx.save()

        // Второй запуск — флаг уже установлен, повторный дубль НЕ будет вычищен этим
        // одноразовым патчем (это и есть defense-in-depth в CashflowCategoryService — сеть №2)
        try DataIntegrityCleaner.dedupeCashflowCustomCategoriesIfNeeded(modelContext: ctx)

        let remaining = try ctx.fetch(FetchDescriptor<CashflowCustomCategory>())
        #expect(remaining.count == 2, "Повторный запуск заблокирован флагом UserDefaults — новый дубль патчем не тронут")
    }

    @Test("Патч не падает на пустом store")
    func emptyStoreDoesNotCrash() throws {
        resetMigrationFlag()
        let ctx = try makeContext()
        try DataIntegrityCleaner.dedupeCashflowCustomCategoriesIfNeeded(modelContext: ctx)
    }
}
